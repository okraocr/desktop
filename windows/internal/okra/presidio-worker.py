#!/usr/bin/env python3
"""Local Presidio analyzer worker for okraPDF Windows.

The worker exposes only a loopback HTTP surface and never logs request text.
The standard analyzer uses spaCy plus Presidio's deterministic recognizers.
When ``ollama_model`` is supplied, the official BasicLangExtractRecognizer is
added with an Ollama provider pointed at loopback.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


MAX_REQUEST_BYTES = 2 * 1024 * 1024

_base_analyzer: Any = None
_analyzers: dict[str, Any] = {}
_load_error = ""
_load_lock = threading.Lock()
_simulate = False


def _is_loopback_url(value: str) -> bool:
    try:
        parsed = urlparse(value)
    except ValueError:
        return False
    return parsed.scheme in {"http", "https"} and parsed.hostname in {
        "127.0.0.1",
        "localhost",
        "::1",
    }


def _ollama_url() -> str:
    value = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")
    if not _is_loopback_url(value):
        raise ValueError("Ollama must use a loopback URL")
    return value


def _new_base_analyzer() -> Any:
    from presidio_analyzer import AnalyzerEngine
    from presidio_analyzer.nlp_engine import NlpEngineProvider

    configuration = {
        "nlp_engine_name": "spacy",
        "models": [{"lang_code": "en", "model_name": "en_core_web_sm"}],
    }
    provider = NlpEngineProvider(nlp_configuration=configuration)
    return AnalyzerEngine(
        nlp_engine=provider.create_engine(),
        supported_languages=["en"],
    )


def _ollama_config(model: str) -> str:
    import yaml
    from presidio_analyzer.predefined_recognizers.third_party.basic_langextract_recognizer import (
        BasicLangExtractRecognizer,
    )

    default_path = Path(BasicLangExtractRecognizer.DEFAULT_CONFIG_PATH)
    config = yaml.safe_load(default_path.read_text(encoding="utf-8"))
    langextract = config["langextract"]
    for key in ("prompt_file", "examples_file"):
        value = Path(langextract[key])
        if not value.is_absolute():
            langextract[key] = str((default_path.parent / value).resolve())
    provider = langextract["model"]["provider"]
    langextract["model"]["model_id"] = model
    provider["name"] = "ollama"
    provider.setdefault("kwargs", {})["model_url"] = _ollama_url()
    provider.setdefault("language_model_params", {})["timeout"] = 240
    provider["language_model_params"]["num_ctx"] = 8192

    digest = hashlib.sha256((model + _ollama_url()).encode("utf-8")).hexdigest()[:12]
    path = Path(__file__).with_name(f"ollama-{digest}.yaml")
    path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
    return str(path)


def _analyzer_for(model: str) -> Any:
    global _base_analyzer
    with _load_lock:
        if not model:
            if _base_analyzer is None:
                _base_analyzer = _new_base_analyzer()
            return _base_analyzer
        if model in _analyzers:
            return _analyzers[model]

        from presidio_analyzer.predefined_recognizers.third_party.basic_langextract_recognizer import (
            BasicLangExtractRecognizer,
        )

        analyzer = _new_base_analyzer()
        analyzer.registry.add_recognizer(
            BasicLangExtractRecognizer(config_path=_ollama_config(model))
        )
        _analyzers[model] = analyzer
        return analyzer


def _warm_base_analyzer() -> None:
    global _load_error
    try:
        if not _simulate:
            _analyzer_for("")
    except Exception as exc:  # surfaced by /health; do not log PII
        _load_error = str(exc)


def _simulation_results(text: str) -> list[dict[str, Any]]:
    patterns = (
        ("EMAIL_ADDRESS", r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", 0.99),
        ("US_SSN", r"\b\d{3}-\d{2}-\d{4}\b", 0.99),
        ("PHONE_NUMBER", r"\b(?:\+?1[ .-]?)?\(?\d{3}\)?[ .-]\d{3}[ .-]\d{4}\b", 0.85),
    )
    found: list[dict[str, Any]] = []
    for entity_type, pattern, score in patterns:
        for match in re.finditer(pattern, text, flags=re.IGNORECASE):
            found.append(
                {
                    "entity_type": entity_type,
                    "start": match.start(),
                    "end": match.end(),
                    "score": score,
                    "text": match.group(0),
                }
            )
    return found


class Handler(BaseHTTPRequestHandler):
    server_version = "okra-presidio/1"

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def _json(self, status: int, body: Any) -> None:
        payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/health":
            self._json(404, {"error": "not found"})
            return
        self._json(
            200,
            {
                "status": "ok" if not _load_error else "error",
                "loaded": _simulate or (_base_analyzer is not None and not _load_error),
                "loadError": _load_error,
                "engine": "presidio",
                "ollamaSupported": True,
                "simulation": _simulate,
            },
        )

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/analyze":
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_REQUEST_BYTES:
            self._json(400, {"error": "invalid request size"})
            return
        try:
            body = json.loads(self.rfile.read(length))
            text = body.get("text", "")
            if not isinstance(text, str) or not text:
                raise ValueError("text is required")
            language = body.get("language", "en")
            if language != "en":
                raise ValueError("only English is configured")
            entities = body.get("entities")
            if entities is not None and not isinstance(entities, list):
                raise ValueError("entities must be an array")
            threshold = float(body.get("score_threshold", 0.5))
            threshold = max(0.0, min(1.0, threshold))
            ollama_model = str(body.get("ollama_model", "")).strip()

            if _simulate:
                results = _simulation_results(text)
            else:
                analyzer = _analyzer_for(ollama_model)
                analyzed = analyzer.analyze(
                    text=text,
                    language="en",
                    entities=entities or None,
                    score_threshold=threshold,
                )
                results = [
                    {
                        "entity_type": result.entity_type,
                        "start": result.start,
                        "end": result.end,
                        "score": result.score,
                        "text": text[result.start : result.end],
                    }
                    for result in analyzed
                ]
            results = [item for item in results if float(item["score"]) >= threshold]
            self._json(200, results)
        except Exception as exc:
            self._json(400, {"error": str(exc)})


def main() -> None:
    global _simulate
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["serve"])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--simulate", action="store_true")
    args = parser.parse_args()
    if args.host not in {"127.0.0.1", "localhost", "::1"}:
        raise SystemExit("Presidio worker must bind to loopback")
    _simulate = args.simulate

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    threading.Thread(target=_warm_base_analyzer, daemon=True).start()
    print(json.dumps({"port": server.server_address[1]}), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
