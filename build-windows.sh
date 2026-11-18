#!/usr/bin/env bash
# Make the Windows build of Photone in ./bin (scripts/build_windows.py says what is in it).
# Needs Python 3.11 or later; uv, where there is one, brings its own.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if command -v uv >/dev/null; then exec uv run --no-project --python 3.13 python "$here/scripts/build_windows.py" "$@"; fi
exec python3 "$here/scripts/build_windows.py" "$@"
