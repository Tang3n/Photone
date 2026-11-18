#!/usr/bin/env bash
# Build and run Photone. Arguments go to the `photone` command:
#   ./run.sh [photo]        start it and open the window (on this photo)
#   ./run.sh --hdr [photo]  the same on an HDR surface, where the desktop has one
#   ./run.sh check          run the checks (PHOTONE_SAMPLE=<raw file> also decodes a real one)
#   ./run.sh shots [name]   render every UI state to .dev/shots/ and audit the layout
#   ./run.sh lint           ruff
#   ./run.sh hdr-test       a native test window: does HDR reach this screen? (scripts/hdr_test.py)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
command -v uv >/dev/null || { echo "run.sh: uv is not installed: https://docs.astral.sh/uv/" >&2; exit 1; }
case "${1:-}" in
  check) shift; exec uv run --project "$here" python "$here/tests/check.py" "$@" ;;
  shots) shift; exec uv run --project "$here" python "$here/scripts/shots.py" "$@" ;;
  hdr-test) shift; exec uv run --project "$here" python "$here/scripts/hdr_test.py" "$@" ;;
  lint) shift; exec uv run --project "$here" --with ruff ruff check "$here" "$@" ;;
esac
# Not cd: a photo given as a relative path is relative to where the user is.
exec uv run --project "$here" photone "$@"
