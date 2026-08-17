import importlib.util
import pathlib
import unittest


SCRIPT = (
    pathlib.Path(__file__).resolve().parents[2]
    / "OkraPDF"
    / "ProviderScripts"
    / "presidio-worker.py"
)
SPEC = importlib.util.spec_from_file_location("presidio_worker", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
WORKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WORKER)


class PresidioWorkerTests(unittest.TestCase):
    def test_simulation_finds_email_ssn_and_phone_without_logging(self) -> None:
        text = "Taylor: taylor@example.com, 415-555-0198, 123-45-6789"
        findings = WORKER._simulation_results(text)

        self.assertEqual(
            {finding["entity_type"] for finding in findings},
            {"EMAIL_ADDRESS", "PHONE_NUMBER", "US_SSN"},
        )
        self.assertEqual(
            {finding["text"] for finding in findings},
            {"taylor@example.com", "415-555-0198", "123-45-6789"},
        )

    def test_only_loopback_urls_are_accepted(self) -> None:
        self.assertTrue(WORKER._is_loopback_url("http://127.0.0.1:11434"))
        self.assertTrue(WORKER._is_loopback_url("http://localhost:11434"))
        self.assertFalse(WORKER._is_loopback_url("https://example.com"))
        self.assertFalse(WORKER._is_loopback_url("file:///tmp/ollama"))


if __name__ == "__main__":
    unittest.main()
