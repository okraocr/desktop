#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
import math
import os
import re
import struct
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


# Ported verbatim from datalab-to/chandra @ chandra/prompts.py (via
# apps/api/packages/chandra-parser-agent/src/prompts.ts). The Chandra model was
# trained against these exact prompts; do NOT paraphrase.
ALLOWED_TAGS = [
    "math",
    "br",
    "i",
    "b",
    "u",
    "del",
    "sup",
    "sub",
    "table",
    "tr",
    "td",
    "p",
    "th",
    "div",
    "pre",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "ul",
    "ol",
    "li",
    "input",
    "a",
    "span",
    "img",
    "hr",
    "tbody",
    "small",
    "caption",
    "strong",
    "thead",
    "big",
    "code",
    "chem",
]

ALLOWED_ATTRIBUTES = [
    "class",
    "colspan",
    "rowspan",
    "display",
    "checked",
    "type",
    "border",
    "value",
    "style",
    "href",
    "alt",
    "align",
    "data-bbox",
    "data-label",
]

LAYOUT_LABELS = [
    "Caption",
    "Footnote",
    "Equation-Block",
    "List-Group",
    "Page-Header",
    "Page-Footer",
    "Image",
    "Section-Header",
    "Table",
    "Text",
    "Complex-Block",
    "Code-Block",
    "Form",
    "Table-Of-Contents",
    "Figure",
    "Chemical-Block",
    "Diagram",
    "Bibliography",
    "Blank-Page",
]

PROMPT_ENDING = f"""
Only use these tags {json.dumps(ALLOWED_TAGS, separators=(",", ":"))}, and these attributes {json.dumps(ALLOWED_ATTRIBUTES, separators=(",", ":"))}.

Guidelines:
* Inline math: Surround math with <math>...</math> tags. Math expressions should be rendered in KaTeX-compatible LaTeX. Use display for block math.
* Tables: Use colspan and rowspan attributes to match table structure.
* Formatting: Maintain consistent formatting with the image, including spacing, indentation, subscripts/superscripts, and special characters.
* Images: Include a description of any images in the alt attribute of an <img> tag. Do not fill out the src property. Describe in detail inside the div tag. Also convert charts to high fidelity data, and convert diagrams to mermaid.
* Forms: Mark checkboxes and radio buttons properly.
* Text: join lines together properly into paragraphs using <p>...</p> tags.  Use <br> tags for line breaks within paragraphs, but only when absolutely necessary to maintain meaning.
* Chemistry: Use <chem>...</chem> tags for chemical formulas with reactive SMILES.
* Lists: Preserve indents and proper list markers.
* Use the simplest possible HTML structure that accurately represents the content of the block.
* Make sure the text is accurate and easy for a human to read and interpret.  Reading order should be correct and natural.
""".strip()

OCR_LAYOUT_PROMPT = f"""
OCR this image to HTML, arranged as layout blocks.  Each layout block should be a div with the data-bbox attribute representing the bounding box of the block in x0 y0 x1 y1 format.  Bboxes are normalized 0-1000. The data-label attribute is the label for the block.

Use the following labels:
{chr(10).join("- " + label for label in LAYOUT_LABELS)}

{PROMPT_ENDING}
""".strip()

# Chandra emits data-bbox coordinates normalized 0-1000 on both axes.
BBOX_SCALE = 1000.0
MAX_OUTPUT_TOKENS = 12_384
TEMPERATURE = 0.0
# Greedy decoding keeps page output deterministic, but on simple pages the
# model can fall into emitting the same layout div forever instead of EOS.
# Stop generation once the exact same token chunk repeats back to back; the
# downstream duplicate suppression stays as the backstop and still reports
# the tail in diagnostics. Window sizes stay large enough that real repeated
# structure (table rows, form fields) never trips the cutoff.
LOOP_STOP_WINDOW_SIZES = (32, 64, 128)
LOOP_STOP_MAX_REPEATS = 3
SPECIAL_TOKENS = (
    "<s>",
    "</s>",
    "<|endoftext|>",
    "<|eot_id|>",
    "<|end_of_text|>",
    "<|im_end|>",
)
LABEL_TYPE_ALIASES = {
    "caption": "caption",
    "footnote": "footnote",
    "equation-block": "equation",
    "list-group": "list",
    "page-header": "header",
    "page-footer": "footer",
    "image": "image",
    "figure": "image",
    "diagram": "image",
    "section-header": "heading",
    "table": "table",
    "text": "text",
    "complex-block": "text",
    "code-block": "code",
    "form": "form",
    "table-of-contents": "toc",
    "chemical-block": "chem",
    "bibliography": "text",
    "blank-page": "blank",
}
MODEL_REPOSITORY = "mlx-community/chandra-ocr-2-oQ8"
MODEL_REVISION = "eafcb4c79468ff6cf8b76ecc3aedbffe0dd82282"
RUNTIME_LOCK_VERSION = "python>=3.10|mlx-vlm==0.6.6|huggingface-hub==1.24.0|v1"
PAGE_PROVENANCE = (
    f"chandra-ocr-2:model={MODEL_REPOSITORY}@{MODEL_REVISION};"
    f"runtime={RUNTIME_LOCK_VERSION}"
)
SIMULATION_PAGE_PROVENANCE = f"chandra-ocr-2:simulation;worker={RUNTIME_LOCK_VERSION}"

DIV_TAG_RE = re.compile(r"<div\b[^>]*>|</div\s*>", re.IGNORECASE | re.DOTALL)
DATA_BBOX_RE = re.compile(
    r'data-bbox\s*=\s*"(?P<x0>-?\d+(?:\.\d+)?)\s+(?P<y0>-?\d+(?:\.\d+)?)'
    r"\s+(?P<x1>-?\d+(?:\.\d+)?)\s+(?P<y1>-?\d+(?:\.\d+)?)\"",
    re.IGNORECASE,
)
DATA_BBOX_PRESENT_RE = re.compile(r"data-bbox\s*=", re.IGNORECASE)
DATA_LABEL_RE = re.compile(r'data-label\s*=\s*"(?P<label>[^"]*)"', re.IGNORECASE)
IMG_ALT_RE = re.compile(r'<img\b[^>]*\balt\s*=\s*"(?P<alt>[^"]*)"', re.IGNORECASE)
TAG_RE = re.compile(r"<[^>]+>")
VOID_ELEMENTS = {
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr",
}


class LoopStoppingCriteria:
    """Callable per-token stop hook understood by mlx_vlm's generate.

    Stops when the default EOS token arrives (delegated to the eos ids the
    processor was loaded with) or when the generated tail is the same token
    chunk repeated LOOP_STOP_MAX_REPEATS times in a row.
    """

    def __init__(
        self,
        eos_token_ids: list[int],
        window_sizes: tuple[int, ...] = LOOP_STOP_WINDOW_SIZES,
        max_repeats: int = LOOP_STOP_MAX_REPEATS,
    ) -> None:
        self.eos_token_ids = list(eos_token_ids)
        self.window_sizes = window_sizes
        self.max_repeats = max_repeats
        self._tokens: list[int] = []

    def __call__(self, token: Any) -> bool:
        if token in self.eos_token_ids:
            return True
        self._tokens.append(int(token))
        for window in self.window_sizes:
            needed = window * self.max_repeats
            if len(self._tokens) < needed:
                continue
            tail = self._tokens[-needed:]
            unit = tail[:window]
            if all(
                tail[index * window : (index + 1) * window] == unit
                for index in range(1, self.max_repeats)
            ):
                return True
        return False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Chandra OCR 2 on rendered PDF pages"
    )
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


def decode_output(raw_text: str) -> str:
    decoded = raw_text
    for token in SPECIAL_TOKENS:
        decoded = decoded.replace(token, "")
    decoded = decoded.replace("\r\n", "\n").replace("\r", "\n")
    return decoded.strip()


def canonical_label(raw_label: str) -> str:
    normalized = re.sub(r"\s+", "-", raw_label.strip().lower()).strip("-")
    if not normalized:
        return "text"
    return LABEL_TYPE_ALIASES.get(normalized, normalized)


def extract_layout_divs(text: str) -> tuple[list[tuple[str, str, str]], str]:
    """Split decoded output into (open_tag, inner_html, trailing) layout divs.

    Returns the list of (start_tag, inner_html) tuples for each top-level div
    carrying a data-bbox attribute, plus any text outside those divs.
    """
    blocks: list[tuple[str, str, str]] = []
    remainder_parts: list[str] = []
    cursor = 0
    while True:
        match = DIV_TAG_RE.search(text, cursor)
        if match is None:
            remainder_parts.append(text[cursor:])
            break
        tag = match.group(0)
        is_close = tag.startswith("</")
        has_bbox = not is_close and DATA_BBOX_PRESENT_RE.search(tag) is not None
        if not has_bbox:
            remainder_parts.append(text[cursor : match.end()])
            cursor = match.end()
            continue

        remainder_parts.append(text[cursor : match.start()])
        depth = 1
        scan = match.end()
        while depth > 0:
            nested = DIV_TAG_RE.search(text, scan)
            if nested is None:
                break
            if nested.group(0).startswith("</"):
                depth -= 1
                if depth == 0:
                    inner_html = text[match.end() : nested.start()]
                    blocks.append((tag, inner_html, nested.group(0)))
                    cursor = nested.end()
                    break
            else:
                depth += 1
            scan = nested.end()
        if depth > 0:
            # Unterminated layout div: keep the raw tail as remainder.
            remainder_parts.append(text[match.start() :])
            cursor = len(text)
            break

    remainder = "".join(remainder_parts).strip()
    return blocks, remainder


def normalized_bbox(values: list[float]) -> dict[str, float | str]:
    x0, y0, x1, y1 = values
    left, right = sorted(
        (min(max(x0, 0.0), BBOX_SCALE), min(max(x1, 0.0), BBOX_SCALE))
    )
    top, bottom = sorted(
        (min(max(y0, 0.0), BBOX_SCALE), min(max(y1, 0.0), BBOX_SCALE))
    )
    return {
        "x": round(left / BBOX_SCALE, 6),
        "y": round(top / BBOX_SCALE, 6),
        "width": round((right - left) / BBOX_SCALE, 6),
        "height": round((bottom - top) / BBOX_SCALE, 6),
        "unit": "normalized",
        "origin": "top-left",
    }


def strip_tags(html_text: str) -> str:
    return html.unescape(TAG_RE.sub("", html_text)).strip()


class _MarkdownHTMLParser(HTMLParser):
    """Best-effort Chandra layout-HTML to Markdown converter."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.list_stack: list[str] = []
        self.ordered_item_counts: list[int] = []
        self.math_depth = 0
        self.math_display = False
        self.skip_depth = 0
        self.pre_depth = 0

    def _append(self, text: str) -> None:
        if self.skip_depth == 0:
            self.parts.append(text)

    def _ensure_blank_line(self) -> None:
        current = "".join(self.parts)
        if current and not current.endswith("\n\n"):
            self.parts.append("\n\n" if not current.endswith("\n") else "\n")

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr = {key: (value or "") for key, value in attrs}
        if tag in ("script", "style"):
            self.skip_depth += 1
            return
        if self.skip_depth:
            return
        if tag == "math":
            self.math_depth += 1
            self.math_display = attr.get("display") == "block"
            self._append("\n\n$$\n" if self.math_display else "$")
        elif tag == "br":
            self._append("\n")
        elif tag == "p":
            self._ensure_blank_line()
        elif tag in ("h1", "h2", "h3", "h4", "h5"):
            self._ensure_blank_line()
            self._append("#" * int(tag[1]) + " ")
        elif tag in ("ul", "ol"):
            self.list_stack.append(tag)
            if tag == "ol":
                self.ordered_item_counts.append(0)
            self._append("\n")
        elif tag == "li":
            self._append("\n")
            if self.list_stack and self.list_stack[-1] == "ol":
                self.ordered_item_counts[-1] += 1
                self._append(f"{self.ordered_item_counts[-1]}. ")
            else:
                self._append("- ")
        elif tag in ("b", "strong"):
            self._append("**")
        elif tag == "i":
            self._append("*")
        elif tag == "del":
            self._append("~~")
        elif tag == "sup":
            self._append("^")
        elif tag == "sub":
            self._append("~")
        elif tag == "pre":
            self._ensure_blank_line()
            self._append("```\n")
            self.pre_depth += 1
        elif tag == "code" and self.pre_depth == 0:
            self._append("`")
        elif tag == "img":
            alt = attr.get("alt", "").strip()
            if alt:
                self._append(f"![{alt}]")
        elif tag == "input":
            checked = "checked" in attrs_dict_lower(attrs)
            self._append("[x] " if checked else "[ ] ")
        elif tag == "hr":
            self._ensure_blank_line()
            self._append("---\n")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in VOID_ELEMENTS or tag in ("br", "img", "input", "hr"):
            self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag: str) -> None:
        if tag in ("script", "style"):
            self.skip_depth = max(0, self.skip_depth - 1)
            return
        if self.skip_depth:
            return
        if tag == "math":
            self._append("\n$$\n\n" if self.math_display else "$")
            self.math_depth = max(0, self.math_depth - 1)
            if self.math_depth == 0:
                self.math_display = False
        elif tag in ("p", "h1", "h2", "h3", "h4", "h5"):
            self._ensure_blank_line()
        elif tag in ("ul", "ol"):
            if self.list_stack:
                popped = self.list_stack.pop()
                if popped == "ol" and self.ordered_item_counts:
                    self.ordered_item_counts.pop()
            self._append("\n")
        elif tag in ("b", "strong"):
            self._append("**")
        elif tag == "i":
            self._append("*")
        elif tag == "del":
            self._append("~~")
        elif tag == "pre":
            self._append("\n```\n\n")
            self.pre_depth = max(0, self.pre_depth - 1)
        elif tag == "code" and self.pre_depth == 0:
            self._append("`")

    def handle_data(self, data: str) -> None:
        self._append(data)

    def markdown(self) -> str:
        text = "".join(self.parts)
        text = re.sub(r"[ \t]+\n", "\n", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.strip()


def attrs_dict_lower(attrs: list[tuple[str, str | None]]) -> dict[str, str]:
    return {key.lower(): (value or "") for key, value in attrs}


def html_to_markdown(html_text: str) -> str:
    parser = _MarkdownHTMLParser()
    try:
        parser.feed(html_text)
        parser.close()
    except Exception:
        return strip_tags(html_text)
    markdown = parser.markdown()
    return markdown if markdown else strip_tags(html_text)


def block_markdown(block: dict[str, Any]) -> str:
    category = block["type"]
    if category == "table":
        return block.get("html") or block["text"]
    markdown = block.get("markdown") or ""
    if not markdown:
        return ""
    if category == "image":
        return f"> Figure: {markdown}"
    return markdown


def parse_model_output(
    raw_text: str,
    page_number: int,
    image_file: str,
    provenance: str = PAGE_PROVENANCE,
) -> dict[str, Any]:
    decoded = decode_output(raw_text)
    layout_divs, remainder = extract_layout_divs(decoded)
    warnings: list[str] = []
    malformed_count = 0
    duplicate_count = 0
    longest_duplicate_run = 0
    consecutive_duplicates = 0
    blocks: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()

    if strip_tags(remainder):
        warnings.append("Ignored Chandra output outside layout blocks.")

    if not layout_divs:
        malformed_count = 1
        warnings.append(
            "Model output did not contain Chandra layout blocks; preserved it as plain text."
        )
        fallback_text = strip_tags(decoded)
        layout_divs = []
        if fallback_text:
            blocks.append(
                {
                    "id": f"page-{page_number}-block-1",
                    "type": "text",
                    "sourceType": "Text",
                    "text": fallback_text,
                    "markdown": html_to_markdown(decoded),
                    "html": None,
                    "bbox": None,
                    "sourceBbox": None,
                    "sourceBboxScale": None,
                }
            )
        detection_count = 0
    else:
        detection_count = len(layout_divs)

    for start_tag, inner_html, _close_tag in layout_divs:
        label_match = DATA_LABEL_RE.search(start_tag)
        bbox_match = DATA_BBOX_RE.search(start_tag)
        raw_label = (
            html.unescape(label_match.group("label")).strip() if label_match else "Text"
        )
        category = canonical_label(raw_label)
        bbox_values: list[float] | None = None
        if bbox_match is not None:
            try:
                bbox_values = [float(bbox_match.group(axis)) for axis in ("x0", "y0", "x1", "y1")]
            except (TypeError, ValueError):
                bbox_values = None
            if bbox_values is not None and not all(
                math.isfinite(value) for value in bbox_values
            ):
                bbox_values = None
        if bbox_values is None:
            malformed_count += 1

        text = strip_tags(inner_html)
        if not text:
            alt_match = IMG_ALT_RE.search(inner_html)
            if alt_match is not None:
                text = html.unescape(alt_match.group("alt")).strip()
        markdown = html_to_markdown(inner_html)
        if category == "image":
            markdown = text
        if not text and category not in ("image", "blank"):
            malformed_count += 1
            continue

        bbox_key = (
            tuple(round(value, 3) for value in bbox_values)
            if bbox_values is not None
            else None
        )
        collapsed_text = re.sub(r"\s+", " ", text).strip()
        signature = (category, bbox_key, collapsed_text)
        if signature in seen:
            duplicate_count += 1
            consecutive_duplicates += 1
            longest_duplicate_run = max(longest_duplicate_run, consecutive_duplicates)
            continue
        seen.add(signature)
        consecutive_duplicates = 0

        block: dict[str, Any] = {
            "id": f"page-{page_number}-block-{len(blocks) + 1}",
            "type": category,
            "sourceType": raw_label or "Text",
            "text": text,
            "markdown": markdown,
            "html": inner_html.strip() if category == "table" else None,
            "bbox": normalized_bbox(bbox_values) if bbox_values is not None else None,
            "sourceBbox": [round(value, 3) for value in bbox_values]
            if bbox_values is not None
            else None,
            "sourceBboxScale": int(BBOX_SCALE) if bbox_values is not None else None,
        }
        blocks.append(block)

    if malformed_count:
        warnings.append(
            f"Ignored or repaired {malformed_count} malformed layout "
            f"element{'s' if malformed_count != 1 else ''}."
        )
    if duplicate_count:
        warnings.append(
            f"Removed {duplicate_count} duplicate layout "
            f"element{'s' if duplicate_count != 1 else ''}."
        )
    loop_detected = longest_duplicate_run >= 3 or duplicate_count >= 8
    if loop_detected:
        warnings.append("Truncated a repeated generation tail.")

    markdown_parts = [block_markdown(block) for block in blocks]
    markdown = "\n\n".join(part for part in markdown_parts if part).strip()
    plain_text = "\n".join(block["text"] for block in blocks if block["text"]).strip()
    if not blocks:
        raise ValueError(
            f"Chandra OCR 2 returned no usable layout blocks for page {page_number}."
        )
    return {
        "pageNumber": page_number,
        "imageFile": image_file,
        "markdown": markdown,
        "plainText": plain_text,
        "blocks": [
            {key: value for key, value in block.items() if key != "markdown"}
            for block in blocks
        ],
        "provenance": provenance,
        "diagnostics": {
            "rawCharacterCount": len(raw_text),
            "decodedCharacterCount": len(decoded),
            "tokenArtifactCount": 0,
            "detectionCount": detection_count,
            "malformedDetectionCount": malformed_count,
            "duplicateBlockCount": duplicate_count,
            "loopDetected": loop_detected,
            "warnings": warnings,
            "blockCount": len(blocks),
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
            "id": "chandra-ocr-2",
            "name": "Chandra OCR 2",
            "modelRepository": MODEL_REPOSITORY,
            "modelRevision": MODEL_REVISION,
            "runtimeLockVersion": RUNTIME_LOCK_VERSION,
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


def load_persisted_page(
    page_output_directory: Path,
    page_number: int,
    expected_provenance: str = PAGE_PROVENANCE,
) -> dict[str, Any] | None:
    markdown_path = page_output_directory / f"page-{page_number:04d}.md"
    json_path = page_output_directory / f"page-{page_number:04d}.json"
    if not markdown_path.exists() or not json_path.exists():
        return None
    try:
        page = json.loads(json_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(page, dict) or page.get("provenance") != expected_provenance:
        return None
    return page


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
        (page_output_directory / f"page-{int(page['pageNumber']):04d}.md")
        .read_text(encoding="utf-8")
        .strip()
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
    write_atomic(progress_path, json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def image_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as image_file:
        header = image_file.read(24)
    if len(header) >= 24 and header.startswith(b"\x89PNG\r\n\x1a\n"):
        width, height = struct.unpack(">II", header[16:24])
        if width > 0 and height > 0:
            return width, height
    raise ValueError(f"Chandra OCR 2 requires a valid rendered PNG page: {path}")


def simulated_layout(image_path: Path) -> str:
    return (
        '<div data-bbox="0 0 1000 160" data-label="Section-Header">'
        "<h2>Chandra OCR 2 simulation</h2></div>\n"
        '<div data-bbox="80 240 920 800" data-label="Text">'
        f"<p>Simulated local OCR for <code>{image_path.name}</code>.</p></div>"
    )


def main() -> None:
    args = parse_args()
    output = Path(args.output)
    page_output_directory = Path(args.page_output_directory)
    page_progress = Path(args.page_progress)
    structured_output = output.with_suffix(".json")
    page_output_directory.mkdir(parents=True, exist_ok=True)
    structured_pages: list[dict[str, Any]] = []
    simulation = bool(args.simulate)
    header_parts = [f"# {args.title}"]
    if simulation:
        header_parts.extend(
            [
                "> Simulation: Chandra OCR 2 model weights were not loaded.",
                (
                    "Offline flags: "
                    f"HF_HUB_OFFLINE={os.environ.get('HF_HUB_OFFLINE', '')}, "
                    f"TRANSFORMERS_OFFLINE={os.environ.get('TRANSFORMERS_OFFLINE', '')}, "
                    f"HF_DATASETS_OFFLINE={os.environ.get('HF_DATASETS_OFFLINE', '')}."
                ),
            ]
        )
    header = "\n\n".join(header_parts)

    if not simulation:
        from mlx_vlm import generate, load
        from mlx_vlm.prompt_utils import apply_chat_template

        model, processor = load(args.model)
        formatted_prompt = apply_chat_template(
            processor,
            model.config,
            OCR_LAYOUT_PROMPT,
            num_images=1,
        )
        tokenizer = getattr(processor, "tokenizer", processor)
        default_eos = getattr(tokenizer, "eos_token_id", None)
        tokenizer_eos = getattr(tokenizer, "eos_token_ids", None)
        if isinstance(tokenizer_eos, int):
            eos_token_ids = [tokenizer_eos]
        elif tokenizer_eos:
            eos_token_ids = list(tokenizer_eos)
        elif default_eos is not None:
            eos_token_ids = [default_eos]
        else:
            eos_token_ids = []
        generation_config_eos = getattr(model.config, "eos_token_id", None)
        if isinstance(generation_config_eos, int):
            eos_token_ids.append(generation_config_eos)
        elif isinstance(generation_config_eos, (list, tuple)):
            eos_token_ids.extend(int(token) for token in generation_config_eos)
        stopping_criteria = LoopStoppingCriteria(eos_token_ids)

    for page_number, image_name in enumerate(args.images, start=1):
        image_path = Path(image_name)
        expected_provenance = (
            SIMULATION_PAGE_PROVENANCE if simulation else PAGE_PROVENANCE
        )
        persisted_page = load_persisted_page(
            page_output_directory,
            page_number,
            expected_provenance=expected_provenance,
        )
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
                simulation=simulation,
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
            len(structured_pages),
        )
        image_dimensions(image_path)
        if simulation:
            raw_text = simulated_layout(image_path)
        else:
            result = generate(
                model=model,
                processor=processor,
                prompt=formatted_prompt,
                image=image_name,
                max_tokens=MAX_OUTPUT_TOKENS,
                temperature=TEMPERATURE,
                stopping_criteria=stopping_criteria,
            )
            raw_text = result.text if hasattr(result, "text") else str(result)

        structured_page = parse_model_output(
            raw_text,
            page_number=page_number,
            image_file=image_path.name,
            provenance=expected_provenance,
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
            simulation=simulation,
        )
        update_page_progress(
            page_progress,
            page_number,
            "succeeded",
            len(structured_pages),
        )
        print(f"Processed page {page_number} of {len(args.images)}", flush=True)


if __name__ == "__main__":
    main()
