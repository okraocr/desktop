#!/bin/zsh
set -euo pipefail

provider_root="$1"
python_bin=""
requirements_file="${0:A:h}/requirements-mlx.lock"

for candidate in /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  if [[ -x "$candidate" ]]; then
    python_bin="$candidate"
    break
  fi
done

if [[ -z "$python_bin" ]]; then
  print -u2 "Python 3 is required to set up Baidu Unlimited-OCR."
  exit 1
fi

if [[ ! -r "$requirements_file" ]]; then
  print -u2 "Baidu Unlimited-OCR is missing its hash-locked Python requirements. Reinstall okraPDF, then retry setup."
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
