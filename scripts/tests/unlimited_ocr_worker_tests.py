import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


def load_worker_module():
    worker_path = (
        Path(__file__).resolve().parents[2]
        / "OkraPDF"
        / "ProviderScripts"
        / "unlimited-ocr-worker.py"
    )
    spec = importlib.util.spec_from_file_location("unlimited_ocr_worker", worker_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


worker = load_worker_module()


class UnlimitedOCROutputParserTests(unittest.TestCase):
    def test_preserves_bbox_less_markers_as_separate_ungrounded_blocks(self):
        raw = (
            "<|det|>header [438, 30, 897, 66]<|/det|>Manage Checked Bags\n"
            "<|det|>text<|/det|>View reservation\n"
            "<|det|>heading [60, 520, 200, 560]<|/det|>Note\n"
            "<|det|>list-item<|/det|>Guests must be checked in to add bags.\n"
            "<|det|>text<|/det|>Read more about checked bags\n"
        )

        page = worker.parse_model_output(raw, page_number=1, image_file="page-0001.png")

        self.assertEqual(
            [block["text"] for block in page["blocks"]],
            [
                "Manage Checked Bags",
                "View reservation",
                "Note",
                "Guests must be checked in to add bags.",
                "Read more about checked bags",
            ],
        )
        self.assertEqual(
            [block["type"] for block in page["blocks"]],
            ["header", "text", "heading", "list-item", "text"],
        )
        self.assertIsNotNone(page["blocks"][0]["bbox"])
        self.assertIsNone(page["blocks"][1]["bbox"])
        self.assertIsNotNone(page["blocks"][2]["bbox"])
        self.assertIsNone(page["blocks"][3]["bbox"])
        self.assertIsNone(page["blocks"][4]["bbox"])
        self.assertEqual(page["diagnostics"]["detectionCount"], 5)
        self.assertEqual(page["diagnostics"]["malformedDetectionCount"], 0)
        self.assertEqual(page["diagnostics"]["groundedBlockCount"], 2)
        self.assertEqual(page["diagnostics"]["ungroundedBlockCount"], 3)

    def test_decodes_layout_tokens_and_truncates_repeated_tail(self):
        repeated_tail = "".join(
            "<|det|>text [87, 632, 220, 660]<|/det|>Example BankĊ"
            for _ in range(10)
        )
        raw = (
            "Ġ[0,Ġ0,Ġ999]<|/det|>Authorization agreementĊ"
            "<|det|>title [10, 20, 300, 50]<|/det|>Deposit formĊ"
            "<|det|>table [20, 80, 900, 500]<|/det|>"
            "<table><tr><td>Total</td><td>$49.00</td></tr></table>Ċ"
            + repeated_tail
        )

        page = worker.parse_model_output(raw, page_number=1, image_file="page-0001.png")

        self.assertEqual(len(page["blocks"]), 4)
        self.assertEqual(page["blocks"][0]["text"], "Authorization agreement")
        self.assertEqual(page["blocks"][1]["type"], "title")
        self.assertEqual(
            page["blocks"][1]["bbox"],
            {
                "x": 0.01,
                "y": 0.02,
                "width": 0.29,
                "height": 0.03,
                "unit": "normalized",
                "origin": "top-left",
            },
        )
        self.assertIn("<table>", page["markdown"])
        self.assertNotIn("Ġ", page["markdown"])
        self.assertNotIn("Ċ", page["markdown"])
        self.assertNotIn("<|det|>", page["markdown"])
        self.assertEqual(page["diagnostics"]["duplicateBlockCount"], 9)
        self.assertTrue(page["diagnostics"]["loopDetected"])
        self.assertGreater(page["diagnostics"]["tokenArtifactCount"], 0)
        self.assertGreater(page["diagnostics"]["malformedDetectionCount"], 0)

    def test_plain_text_output_stays_renderable(self):
        page = worker.parse_model_output(
            "First lineĊSecond line",
            page_number=2,
            image_file="page-0002.png",
        )

        self.assertEqual(len(page["blocks"]), 1)
        self.assertEqual(page["blocks"][0]["bbox"], None)
        self.assertEqual(page["plainText"], "First line\nSecond line")
        self.assertEqual(page["markdown"], "First line\nSecond line")

    def test_preserves_already_normalized_layout_coordinates(self):
        page = worker.parse_model_output(
            "<|det|>text [0.1, 0.2, 0.7, 0.4]<|/det|>Normalized box",
            page_number=1,
            image_file="page-0001.png",
        )

        block = page["blocks"][0]
        self.assertEqual(block["sourceBboxScale"], 1)
        self.assertEqual(
            block["bbox"],
            {
                "x": 0.1,
                "y": 0.2,
                "width": 0.6,
                "height": 0.2,
                "unit": "normalized",
                "origin": "top-left",
            },
        )

    def test_parses_ollama_style_layout_lines_without_control_tags(self):
        page = worker.parse_model_output(
            "title [6, 17, 991, 82]Model request\n"
            "text [51, 124, 105, 149]Open",
            page_number=1,
            image_file="page-0001.png",
        )

        self.assertEqual(len(page["blocks"]), 2)
        self.assertEqual(page["blocks"][0]["type"], "title")
        self.assertEqual(page["blocks"][0]["text"], "Model request")
        self.assertEqual(page["blocks"][1]["type"], "text")
        self.assertEqual(page["diagnostics"]["detectionCount"], 2)

    def test_structured_page_and_document_json_round_trip(self):
        page = worker.parse_model_output(
            "<|det|>text [0, 0, 999, 999]<|/det|>Full page",
            page_number=1,
            image_file="page-0001.png",
        )
        payload = worker.document_payload(
            "sample.pdf",
            total_page_count=1,
            pages=[page],
            complete=True,
            simulation=False,
        )

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result.json"
            worker.write_atomic(
                output,
                json.dumps(payload, ensure_ascii=False),
            )
            decoded = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(decoded["schemaVersion"], 1)
        self.assertEqual(decoded["provider"]["id"], "unlimited-ocr")
        self.assertEqual(decoded["completedPageCount"], 1)
        self.assertTrue(decoded["complete"])
        self.assertEqual(decoded["pages"][0]["blocks"][0]["bbox"]["width"], 0.999)

    def test_persisted_page_rebuilds_outputs_without_running_model(self):
        page = worker.parse_model_output(
            "<|det|>text [0, 0, 999, 999]<|/det|>Already parsed",
            page_number=1,
            image_file="page-0001.png",
        )

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pages = root / "page-results"
            worker.persist_page(
                pages,
                page_number=1,
                markdown="## Page 1\n\nAlready parsed",
                structured_page=page,
            )

            restored = worker.load_persisted_page(pages, page_number=1)
            self.assertEqual(restored, page)
            worker.persist_document_outputs(
                root / "result.md",
                root / "result.json",
                pages,
                "# sample.pdf",
                "sample.pdf",
                total_page_count=1,
                pages=[restored],
                simulation=False,
            )

            self.assertIn("Already parsed", (root / "result.md").read_text())
            payload = json.loads((root / "result.json").read_text())
            self.assertTrue(payload["complete"])
            self.assertEqual(payload["completedPageCount"], 1)


if __name__ == "__main__":
    unittest.main()
