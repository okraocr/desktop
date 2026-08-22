#!/usr/bin/env python3
import argparse
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


# Unlimited-OCR's upstream DET_RE makes the coordinate group optional. Keep
# bbox-less detections as distinct blocks instead of absorbing their marker and
# text into the preceding grounded block.
DETECTION_PATTERN = re.compile(
    r"<\|det\|>\s*([^\[\n<]{1,80}?)\s*"
    r"(?:\[\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*"
    r"(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\])?\s*"
    r"<\|/det\|>",
    re.IGNORECASE,
)
PLAIN_DETECTION_PATTERN = re.compile(
    r"^\s*([A-Za-z][A-Za-z0-9_-]{0,79})\s*"
    r"\[\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*"
    r"(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\]\s*",
    re.IGNORECASE | re.MULTILINE,
)
TOKEN_ARTIFACTS = {
    "Ġ": " ",
    "Ċ": "\n",
    "ĉ": "\t",
    "▁": " ",
}
SPECIAL_TOKENS = (
    "<s>",
    "</s>",
    "<|endoftext|>",
    "<|eot_id|>",
    "<|end_of_text|>",
    "<｜end▁of▁sentence｜>",
    "<｜end of sentence｜>",
)
CATEGORY_ALIASES = {
    "section-header": "heading",
    "section_header": "heading",
    "header": "header",
    "page-header": "header",
    "page_header": "header",
    "page-footer": "footer",
    "page_footer": "footer",
    "list-item": "list-item",
    "list_item": "list-item",
    "figure": "image",
    "picture": "image",
    "formula": "equation",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Baidu Unlimited-OCR on rendered PDF pages")
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--page-output-directory", required=True)
    parser.add_argument("--page-progress", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--images", nargs="+", required=True)
    parser.add_argument(
        "--simulate",
        action="store_true",
        help="Exercise the PDF-to-worker contract without loading model weights",
    )
    return parser.parse_args()


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def decode_token_artifacts(raw_text: str) -> tuple[str, int]:
    decoded = raw_text
    replacement_count = 0
    for artifact, replacement in TOKEN_ARTIFACTS.items():
        count = decoded.count(artifact)
        if count:
            decoded = decoded.replace(artifact, replacement)
            replacement_count += count
    for token in SPECIAL_TOKENS:
        decoded = decoded.replace(token, "")
    decoded = decoded.replace("\r\n", "\n").replace("\r", "\n")
    return decoded, replacement_count


def canonical_category(raw_category: str) -> str:
    normalized = re.sub(r"\s+", "-", raw_category.strip().lower()).strip("-")
    if not normalized:
        return "text"
    return CATEGORY_ALIASES.get(normalized, normalized)


def bbox_scale(values: list[float]) -> int:
    # Unlimited-OCR's native layout space is 0...1000, but compatible model
    # conversions can emit already-normalized coordinates. Preserve both
    # contracts instead of shrinking normalized boxes by another factor of 1000.
    return 1 if all(abs(value) <= 1.0 for value in values) else 1000


def normalized_bbox(values: list[float]) -> dict[str, float | str]:
    scale = bbox_scale(values)
    x1, y1, x2, y2 = [min(max(value, 0.0), float(scale)) for value in values]
    left, right = sorted((x1, x2))
    top, bottom = sorted((y1, y2))
    return {
        "x": round(left / scale, 6),
        "y": round(top / scale, 6),
        "width": round((right - left) / scale, 6),
        "height": round((bottom - top) / scale, 6),
        "unit": "normalized",
        "origin": "top-left",
    }


def clean_unmarked_text(text: str) -> str:
    # Some MLX/GGUF conversions occasionally emit a malformed leading detection
    # trailer such as "[0, 0, 999]<|/det|>". Remove the unusable marker while
    # retaining the recognized text that follows it.
    cleaned = re.sub(
        r"(?:[A-Za-z_-]+\s*)?\[[^\]\n]{1,100}\]\s*<\|/det\|>",
        "",
        text,
    )
    cleaned = cleaned.replace("<|det|>", "").replace("<|/det|>", "")
    cleaned = re.sub(r"[ \t]+\n", "\n", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def block_markdown(block: dict[str, Any]) -> str:
    text = block["text"].strip()
    category = block["type"]
    if not text:
        return ""
    if category == "title":
        return text if text.startswith("#") else f"### {text}"
    if category in ("heading", "header"):
        return text if text.startswith("#") else f"#### {text}"
    if category == "list-item":
        return text if re.match(r"^(?:[-*+] |\d+[.)] )", text) else f"- {text}"
    if category == "equation":
        return text if text.startswith(("$", "\\[")) else f"$$\n{text}\n$$"
    if category == "caption":
        return text if text.startswith("_") else f"_{text}_"
    if category == "image":
        return f"> Figure: {text}"
    return text


def parse_model_output(
    raw_text: str,
    page_number: int,
    image_file: str,
) -> dict[str, Any]:
    decoded, token_artifact_count = decode_token_artifacts(raw_text)
    matches = list(DETECTION_PATTERN.finditer(decoded))
    if not matches:
        matches = list(PLAIN_DETECTION_PATTERN.finditer(decoded))
    blocks: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    duplicate_block_count = 0
    consecutive_duplicate_count = 0
    longest_duplicate_run = 0

    def append_block(
        text: str,
        raw_category: str = "text",
        source_bbox: list[float] | None = None,
    ) -> None:
        nonlocal duplicate_block_count
        nonlocal consecutive_duplicate_count
        nonlocal longest_duplicate_run
        cleaned_text = clean_unmarked_text(text)
        if not cleaned_text:
            return
        category = canonical_category(raw_category)
        collapsed_text = re.sub(r"\s+", " ", cleaned_text).strip()
        bbox_key = tuple(round(value, 3) for value in source_bbox) if source_bbox else None
        signature = (category, bbox_key, collapsed_text)
        if signature in seen:
            duplicate_block_count += 1
            consecutive_duplicate_count += 1
            longest_duplicate_run = max(longest_duplicate_run, consecutive_duplicate_count)
            return
        consecutive_duplicate_count = 0
        seen.add(signature)
        block_number = len(blocks) + 1
        block: dict[str, Any] = {
            "id": f"page-{page_number}-block-{block_number}",
            "type": category,
            "sourceType": raw_category.strip() or "text",
            "text": cleaned_text,
            "bbox": normalized_bbox(source_bbox) if source_bbox else None,
            "sourceBbox": [round(value, 3) for value in source_bbox]
            if source_bbox
            else None,
            "sourceBboxScale": bbox_scale(source_bbox) if source_bbox else None,
        }
        blocks.append(block)

    cursor = 0
    for index, match in enumerate(matches):
        append_block(decoded[cursor : match.start()])
        content_end = matches[index + 1].start() if index + 1 < len(matches) else len(decoded)
        source_bbox = (
            [float(match.group(group)) for group in range(2, 6)]
            if match.group(2) is not None
            else None
        )
        append_block(
            decoded[match.end() : content_end],
            raw_category=match.group(1),
            source_bbox=source_bbox,
        )
        cursor = content_end

    if not matches:
        append_block(decoded)

    residual = DETECTION_PATTERN.sub("", decoded)
    orphan_open_count = residual.count("<|det|>")
    orphan_close_count = residual.count("<|/det|>")
    malformed_detection_count = orphan_open_count + orphan_close_count
    loop_detected = longest_duplicate_run >= 3 or duplicate_block_count >= 8
    warnings: list[str] = []
    if token_artifact_count:
        warnings.append("Decoded byte-level tokenizer whitespace markers.")
    if malformed_detection_count:
        warnings.append("Ignored malformed detection markers while preserving their text.")
    if duplicate_block_count:
        warnings.append(
            f"Removed {duplicate_block_count} duplicate layout block"
            f"{'s' if duplicate_block_count != 1 else ''}."
        )
    if loop_detected:
        warnings.append("Truncated a repeated generation tail.")

    markdown_parts = [block_markdown(block) for block in blocks]
    markdown = "\n\n".join(part for part in markdown_parts if part).strip()
    plain_text = "\n".join(block["text"] for block in blocks).strip()
    grounded_block_count = sum(1 for block in blocks if block["bbox"] is not None)
    return {
        "pageNumber": page_number,
        "imageFile": image_file,
        "markdown": markdown,
        "plainText": plain_text,
        "blocks": blocks,
        "diagnostics": {
            "rawCharacterCount": len(raw_text),
            "decodedCharacterCount": len(decoded),
            "tokenArtifactCount": token_artifact_count,
            "detectionCount": len(matches),
            "malformedDetectionCount": malformed_detection_count,
            "duplicateBlockCount": duplicate_block_count,
            "loopDetected": loop_detected,
            "groundedBlockCount": grounded_block_count,
            "ungroundedBlockCount": len(blocks) - grounded_block_count,
            "warnings": warnings,
        },
    }


def document_payload(
    title: str,
    total_page_count: int,
    pages: list[dict[str, Any]],
    complete: bool,
    simulation: bool,
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "object": "local_extraction",
        "provider": {
            "id": "unlimited-ocr",
            "name": "Baidu Unlimited-OCR",
        },
        "title": title,
        "pageCount": total_page_count,
        "completedPageCount": len(pages),
        "complete": complete,
        "simulation": simulation,
        "pages": pages,
    }


def persist_page(
    page_output_directory: Path,
    page_number: int,
    markdown: str,
    structured_page: dict[str, Any],
) -> None:
    write_atomic(
        page_output_directory / f"page-{page_number:04d}.md",
        markdown.rstrip("\n") + "\n",
    )
    write_atomic(
        page_output_directory / f"page-{page_number:04d}.json",
        json.dumps(structured_page, indent=2, sort_keys=True, ensure_ascii=False)
        + "\n",
    )


def append_page(output: Path, markdown: str) -> None:
    with output.open("a", encoding="utf-8") as output_file:
        output_file.write(markdown.rstrip("\n") + "\n\n")


def load_persisted_page(
    page_output_directory: Path,
    page_number: int,
) -> dict[str, Any] | None:
    markdown_path = page_output_directory / f"page-{page_number:04d}.md"
    json_path = page_output_directory / f"page-{page_number:04d}.json"
    if not markdown_path.exists() or not json_path.exists():
        return None
    try:
        page = json.loads(json_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return page if isinstance(page, dict) else None


def persist_document_outputs(
    output: Path,
    structured_output: Path,
    page_output_directory: Path,
    header: str,
    title: str,
    total_page_count: int,
    pages: list[dict[str, Any]],
    simulation: bool,
) -> None:
    ordered_pages = sorted(pages, key=lambda page: int(page["pageNumber"]))
    markdown_sections = [
        (
            page_output_directory
            / f"page-{int(page['pageNumber']):04d}.md"
        ).read_text(encoding="utf-8").strip()
        for page in ordered_pages
    ]
    markdown = header.strip() + "\n\n"
    if markdown_sections:
        markdown += "\n\n".join(markdown_sections) + "\n"
    write_atomic(output, markdown)
    write_atomic(
        structured_output,
        json.dumps(
            document_payload(
                title,
                total_page_count,
                ordered_pages,
                complete=len(ordered_pages) == total_page_count,
                simulation=simulation,
            ),
            indent=2,
            sort_keys=True,
            ensure_ascii=False,
        )
        + "\n",
    )


def update_page_progress(
    progress_path: Path,
    page_number: int,
    status: str,
    completed_page_count: int,
) -> None:
    manifest = json.loads(progress_path.read_text(encoding="utf-8"))
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )
    manifest["updatedAt"] = timestamp
    manifest["completedPageCount"] = completed_page_count
    manifest["currentPageNumber"] = page_number
    manifest["currentPageStatus"] = status
    manifest["errorMessage"] = None
    if status == "succeeded":
        manifest["lastCompletedPageNumber"] = page_number
        manifest["lastCompletedAt"] = timestamp
    write_atomic(
        progress_path,
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    )


def main() -> None:
    args = parse_args()
    output = Path(args.output)
    page_output_directory = Path(args.page_output_directory)
    page_progress = Path(args.page_progress)
    structured_output = output.with_suffix(".json")
    page_output_directory.mkdir(parents=True, exist_ok=True)
    structured_pages: list[dict[str, Any]] = []

    if args.simulate:
        header = "\n\n".join([
            f"# {args.title}",
            "> Simulation: Baidu Unlimited-OCR model weights were not loaded.",
            (
                "Offline flags: "
                f"HF_HUB_OFFLINE={os.environ.get('HF_HUB_OFFLINE', '')}, "
                f"TRANSFORMERS_OFFLINE={os.environ.get('TRANSFORMERS_OFFLINE', '')}, "
                f"HF_DATASETS_OFFLINE={os.environ.get('HF_DATASETS_OFFLINE', '')}."
            ),
        ])
        for page_number, image_path in enumerate(args.images, start=1):
            persisted_page = load_persisted_page(page_output_directory, page_number)
            if persisted_page is not None:
                structured_pages.append(persisted_page)
                persist_document_outputs(
                    output,
                    structured_output,
                    page_output_directory,
                    header,
                    args.title,
                    len(args.images),
                    structured_pages,
                    simulation=True,
                )
                update_page_progress(
                    page_progress,
                    page_number,
                    "succeeded",
                    len(structured_pages),
                )
                print(f"Restored page {page_number} of {len(args.images)}", flush=True)
                continue
            update_page_progress(
                page_progress,
                page_number,
                "processing",
                page_number - 1,
            )
            simulated_text = (
                "<|det|>text [80, 100, 920, 220]<|/det|>"
                f"Simulated local OCR for `{Path(image_path).name}`."
            )
            structured_page = parse_model_output(
                simulated_text,
                page_number=page_number,
                image_file=Path(image_path).name,
            )
            structured_pages.append(structured_page)
            section = f"## Page {page_number}\n\n{structured_page['markdown']}"
            persist_page(
                page_output_directory,
                page_number,
                section,
                structured_page,
            )
            persist_document_outputs(
                output,
                structured_output,
                page_output_directory,
                header,
                args.title,
                len(args.images),
                structured_pages,
                simulation=True,
            )
            update_page_progress(
                page_progress,
                page_number,
                "succeeded",
                page_number,
            )
            print(f"Processed page {page_number} of {len(args.images)}", flush=True)
        return

    from mlx_vlm import generate, load
    from mlx_vlm.prompt_utils import apply_chat_template
    from mlx_vlm.utils import load_config

    model, processor = load(args.model)
    config = load_config(args.model)
    header = f"# {args.title}"

    for page_number, image_path in enumerate(args.images, start=1):
        persisted_page = load_persisted_page(page_output_directory, page_number)
        if persisted_page is not None:
            structured_pages.append(persisted_page)
            persist_document_outputs(
                output,
                structured_output,
                page_output_directory,
                header,
                args.title,
                len(args.images),
                structured_pages,
                simulation=False,
            )
            update_page_progress(
                page_progress,
                page_number,
                "succeeded",
                len(structured_pages),
            )
            print(f"Restored page {page_number} of {len(args.images)}", flush=True)
            continue
        update_page_progress(
            page_progress,
            page_number,
            "processing",
            page_number - 1,
        )
        prompt = apply_chat_template(
            processor,
            config,
            "document parsing.",
            num_images=1,
        )
        result = generate(
            model,
            processor,
            prompt,
            [image_path],
            max_tokens=8192,
            temperature=0.0,
            cropping=False,
            image_size=1024,
            verbose=False,
        )
        raw_text = result.text if hasattr(result, "text") else str(result)
        structured_page = parse_model_output(
            raw_text,
            page_number=page_number,
            image_file=Path(image_path).name,
        )
        structured_pages.append(structured_page)
        section = f"## Page {page_number}\n\n{structured_page['markdown']}"
        persist_page(
            page_output_directory,
            page_number,
            section,
            structured_page,
        )
        persist_document_outputs(
            output,
            structured_output,
            page_output_directory,
            header,
            args.title,
            len(args.images),
            structured_pages,
            simulation=False,
        )
        update_page_progress(
            page_progress,
            page_number,
            "succeeded",
            page_number,
        )
        print(f"Processed page {page_number} of {len(args.images)}", flush=True)


if __name__ == "__main__":
    main()
