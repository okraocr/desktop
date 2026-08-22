#!/bin/zsh
set -euo pipefail

provider_root="$1"
python_bin="${2:-}"
requirements_file="${0:A:h}/requirements-mlx.lock"
trusted_python_candidates=(
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

python_is_trusted=false
for candidate in "${trusted_python_candidates[@]}"; do
  if [[ "$python_bin" == "$candidate" ]]; then
    python_is_trusted=true
    break
  fi
done
python_version_supported=false
if [[ "$python_is_trusted" == true && -x "$python_bin" ]]; then
  python_version="$("$python_bin" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
  python_major="${python_version%%.*}"
  python_minor="${python_version#*.}"
  if [[ "$python_major" == <-> && "$python_minor" == <-> ]] \
    && (( python_major > 3 || (python_major == 3 && python_minor >= 10) )); then
    python_version_supported=true
  fi
fi
if [[ "$python_version_supported" != true ]]; then
  print -u2 "Dots OCR 1.5 requires Python 3.10 or newer. Install it with 'brew install python@3.13', then retry setup."
  exit 1
fi

if [[ ! -r "$requirements_file" ]]; then
  print -u2 "Dots OCR 1.5 is missing its hash-locked Python requirements. Reinstall okraPDF, then retry setup."
  exit 1
fi

mkdir -p "$provider_root/huggingface"
"$python_bin" -m venv --clear "$provider_root/venv"
"$provider_root/venv/bin/python" -m pip install \
  --disable-pip-version-check \
  --require-virtualenv \
  --require-hashes \
  --only-binary=:all: \
  --requirement "$requirements_file"
"$provider_root/venv/bin/python" -m pip freeze > "$provider_root/installed-packages.txt"
