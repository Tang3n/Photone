#!/usr/bin/env bash
# Install Photone for this user (Linux): the `photone` command, and its entry in the
# desktop's menu and in "Open with" for raw files and pictures.
#   ./install.sh               install, or bring an installed one up to this folder's state
#   ./install.sh --uninstall   take it away again (the catalog and the settings stay)
# The program is copied (by `uv tool install`): this folder is not needed afterwards.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
command -v uv >/dev/null || { echo "install.sh: uv is not installed: https://docs.astral.sh/uv/" >&2; exit 1; }
data="${XDG_DATA_HOME:-$HOME/.local/share}"
entry="$data/applications/photone.desktop"
icon="$data/icons/hicolor/scalable/apps/photone.svg"
menu() { command -v update-desktop-database >/dev/null && update-desktop-database -q "$data/applications" || true; }

if [ "${1:-}" = "--uninstall" ]; then
  uv tool uninstall photone || true
  rm -f "$entry" "$icon"
  menu
  echo "Photone is uninstalled."
  exit
fi

uv tool install --force --reinstall --python "$(cat "$here/.python-version")" "$here"
command="$(uv tool dir --bin)/photone"  # in full: a desktop's menu may not have it on its PATH
install -Dm644 "$here/photone/ui/icon.svg" "$icon"
mkdir -p "$(dirname "$entry")"
cat > "$entry" <<END
[Desktop Entry]
Type=Application
Name=Photone
GenericName=Raw Photo Editor
Comment=A raw photo editor built around a color wheel
Exec="$command" %F
Icon=photone
Terminal=false
Categories=Graphics;Photography;2DGraphics;RasterGraphics;
MimeType=image/x-sony-arw;image/x-canon-cr2;image/x-canon-cr3;image/x-adobe-dng;image/x-nikon-nef;image/x-olympus-orf;image/x-pentax-pef;image/x-fuji-raf;image/x-panasonic-rw2;image/jpeg;image/png;image/tiff;
StartupWMClass=photone
END
menu
echo "Photone is installed: it is in the desktop's menu, and \`photone\` starts it from a terminal"
echo "(if that is not found, add $(dirname "$command") to PATH: uv tool update-shell)."
