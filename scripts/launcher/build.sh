#!/usr/bin/env bash
# Build scripts/launcher/Photone.exe (and its icon, from photone/ui/icon.svg). Only needed
# when launcher.c or the icon changes: the built file is kept in the repository.
# Needs mingw (Ubuntu: gcc-mingw-w64-x86-64) and uv.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
QT_QPA_PLATFORM=offscreen uv run --project "$here/../.." python - "$here/../../photone/ui/icon.svg" "$here/Photone.ico" <<'END'
import sys
from PySide6.QtCore import QSize
from PySide6.QtGui import QGuiApplication, QIcon
app = QGuiApplication([])
assert QIcon(sys.argv[1]).pixmap(QSize(256, 256)).save(sys.argv[2], "ICO"), "the icon was not written"
END
cd "$here"
x86_64-w64-mingw32-windres launcher.rc -O coff -o launcher.res
x86_64-w64-mingw32-gcc -O2 -s -municode -mwindows -o Photone.exe launcher.c launcher.res -lshell32
rm launcher.res
ls -l Photone.exe Photone.ico
