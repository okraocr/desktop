#!/bin/zsh
set -euo pipefail

provider_root="$1"
presidio_version="2.2.364"
spacy_model_version="3.8.0"
spacy_model_url="https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-${spacy_model_version}/en_core_web_sm-${spacy_model_version}-py3-none-any.whl"
python_bin=""
path_python="$(command -v python3 2>/dev/null || true)"
python_candidates=(
  /opt/homebrew/bin/python3.13
  /opt/homebrew/bin/python3.12
  /opt/homebrew/bin/python3.11
  /opt/homebrew/bin/python3.10
  /opt/homebrew/bin/python3
  /usr/local/bin/python3.13
  /usr/local/bin/python3.12
  /usr/local/bin/python3.11
  /usr/local/bin/python3.10
  /usr/local/bin/python3
  /usr/bin/python3
)

if [[ -n "$path_python" ]]; then
  python_candidates+=("$path_python")
fi

for candidate in "${python_candidates[@]}"; do
  if [[ ! -x "$candidate" ]]; then
    continue
  fi
  python_version="$("$candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
  python_major="${python_version%%.*}"
  python_minor="${python_version#*.}"
  if [[ "$python_major" == <-> && "$python_minor" == <-> ]] \
    && (( python_major > 3 || (python_major == 3 && python_minor >= 10) )); then
    python_bin="$candidate"
    break
  fi
done

if [[ -z "$python_bin" ]]; then
  print -u2 "Microsoft Presidio requires Python 3.10 or newer. Install it with 'brew install python@3.13', then retry setup."
  exit 1
fi

mkdir -p "$provider_root"
rm -f "$provider_root/.ready"
"$python_bin" -m venv --clear "$provider_root/venv"
"$provider_root/venv/bin/python" -m pip install \
  --disable-pip-version-check \
  --require-virtualenv \
  --upgrade pip
"$provider_root/venv/bin/python" -m pip install \
  --disable-pip-version-check \
  --require-virtualenv \
  "presidio-analyzer[langextract]==${presidio_version}" \
  "$spacy_model_url"
"$provider_root/venv/bin/python" -c \
  "import spacy; spacy.load('en_core_web_sm'); from presidio_analyzer.predefined_recognizers.third_party.basic_langextract_recognizer import BasicLangExtractRecognizer; print('ok')"
"$provider_root/venv/bin/python" -m pip freeze > "$provider_root/installed-packages.txt"

installed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
printf '{\n  "schemaVersion": 1,\n  "presidioVersion": "%s",\n  "spacyModelVersion": "%s",\n  "installedAt": "%s"\n}\n' \
  "$presidio_version" "$spacy_model_version" "$installed_at" > "$provider_root/.ready"
