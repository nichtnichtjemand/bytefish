#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -x "$SCRIPT_DIR/.venv/bin/python" ]]; then
    exec "$SCRIPT_DIR/.venv/bin/python" "$SCRIPT_DIR/uci.py"
fi

if command -v uv >/dev/null 2>&1; then
    exec uv run --no-project --with "chess>=1.11.2" python "$SCRIPT_DIR/uci.py"
fi

echo "Bytefish requires a Python environment with the 'chess' package." >&2
echo "Run 'uv sync' in $SCRIPT_DIR or install chess for the selected interpreter." >&2
exit 1
