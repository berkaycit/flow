#!/bin/bash
# Create venv and install dependencies for NotebookLM integration.
# Exits 0 if already set up or setup succeeds.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

if [ -f "$VENV_DIR/bin/python3" ]; then
    exit 0
fi

# Find Python 3.10+
PYTHON=""
for py in python3.12 python3.13 python3.11 python3.10; do
    if command -v "$py" &>/dev/null; then
        PYTHON="$(command -v "$py")"
        break
    fi
done

# Fall back to python3 if it's 3.10+
if [ -z "$PYTHON" ] && command -v python3 &>/dev/null; then
    minor=$(python3 -c "import sys; print(sys.version_info.minor)" 2>/dev/null)
    if [ -n "$minor" ] && [ "$minor" -ge 10 ]; then
        PYTHON="$(command -v python3)"
    fi
fi

if [ -z "$PYTHON" ]; then
    echo "Python 3.10+ gerekli. 'brew install python@3.12' ile kurun." >&2
    exit 1
fi

echo "Venv olusturuluyor ($PYTHON)..." >&2
"$PYTHON" -m venv "$VENV_DIR" || exit 1

echo "Paketler kuruluyor..." >&2
"$VENV_DIR/bin/pip" install -q notebooklm-py pycookiecheat 2>&1 >&2 || exit 1

echo "ok"
