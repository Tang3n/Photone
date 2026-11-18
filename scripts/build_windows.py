#!/usr/bin/env python3
"""Make the Windows build of Photone in ./bin: a folder that runs as it is, nothing to install.

    build-windows.bat  (Windows)   or   ./build-windows.sh  (Linux)
    then start bin\\Photone.exe (or copy bin to a Windows machine)

Those two only call this file with whatever Python is there. It needs Python 3.11 or later
and nothing else: the packages are fetched by uv
where there is one and by pip otherwise. Nothing is compiled: Windows' own Python and the
Windows wheels of the packages, at the versions in uv.lock, are laid out beside the program.

    bin/Photone.exe          starts it (photos dropped on it are opened)
    bin/Photone-console.bat  the same with a console, to read what it says when it will not start
    bin/python/              Python for Windows (the "embeddable" one)
    bin/lib/                 PySide6 (Qt), rawpy, numpy
    bin/photone/             the program

ponytail: no installer and no file associations; Photone.exe is not signed, so Windows may
ask before it runs a downloaded copy. The upgrade is an installer and a signing certificate.
"""

import io
import shutil
import subprocess
import sys
import tempfile
import tomllib
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent  # the project
OUT = HERE / "bin"
PYTHON = "3.13.15"  # the same 3.x as .python-version
# Of Qt only the "Essentials" half: the other (web engine, PDF, 3D, charts: 500 MB) is not
# used, but for the shader compiler, which is taken out of it.
LEFT_OUT = {"photone", "pyside6", "pyside6-addons", "pyside6-pdf", "pyside6-webengine"}
COMPILER = ("qsb.exe", "Qt6ShaderTools.dll")
# What comes in the wheels and no run of Photone loads: Qt's own tools and what belongs to
# them, the software OpenGL, type stubs, Qt's translations (the interface has its own words),
# numpy's tests. And the bindings for the parts of Qt the program does not import (KEPT are
# those it does, with the ones they import in turn). About 90 MB.
UNUSED = ("bin", "PySide6/*.exe", "PySide6/*.pyi", "PySide6/opengl32sw.dll",
          "PySide6/Qt6Designer*.dll", "PySide6/translations", "PySide6/metatypes",
          "PySide6/resources", "PySide6/typesystems", "PySide6/include", "PySide6/glue",
          "PySide6/doc", "PySide6/plugins/sqldrivers", "PySide6/plugins/qmltooling",
          "PySide6/plugins/designer", "numpy/**/tests")
KEPT = {"QtCore", "QtDBus", "QtGui", "QtNetwork", "QtOpenGL", "QtQml", "QtQuick"}


def fetch(packages: list[str], to: Path) -> None:
    """Their Windows wheels, unpacked into `to`."""
    if uv := shutil.which("uv"):
        tool = [uv, "pip", "install", "--python", sys.executable,  # (uv wants one to go by)
                "--python-platform", "x86_64-pc-windows-msvc"]
    else:
        tool = [sys.executable, "-m", "pip", "install", "--platform", "win_amd64",
                "--implementation", "cp", "--disable-pip-version-check"]
    subprocess.run([*tool, "--quiet", "--no-deps", "--only-binary", ":all:", "--python-version",
                    PYTHON.rpartition(".")[0], "--target", str(to), *packages], check=True)


def main() -> None:
    locked = {package["name"]: package["version"]
              for package in tomllib.loads((HERE / "uv.lock").read_text("utf-8"))["package"]}
    shutil.rmtree(OUT, ignore_errors=True)

    print(f"Python {PYTHON} for Windows ...", flush=True)
    address = f"https://www.python.org/ftp/python/{PYTHON}/python-{PYTHON}-embed-amd64.zip"
    with urllib.request.urlopen(address) as answer:
        zipfile.ZipFile(io.BytesIO(answer.read())).extractall(OUT / "python")
    # Where this Python looks for modules: only what is listed here (nothing of the machine's).
    paths = next((OUT / "python").glob("python3*._pth"))
    paths.write_text(f"{paths.stem}.zip\n.\n..\\lib\n..\n")

    print("The packages ...", flush=True)
    fetch([f"{name}=={version}" for name, version in locked.items() if name not in LEFT_OUT],
          OUT / "lib")
    unused = [found for pattern in UNUSED for found in (OUT / "lib").glob(pattern)]
    unused += [b for b in (OUT / "lib" / "PySide6").glob("Qt*.pyd") if b.stem not in KEPT]
    for found in unused:
        shutil.rmtree(found) if found.is_dir() else found.unlink()
    with tempfile.TemporaryDirectory() as other:
        fetch([f"pyside6-addons=={locked['pyside6-addons']}"], Path(other))
        for name in COMPILER:
            shutil.copy(Path(other) / "PySide6" / name, OUT / "lib" / "PySide6")

    shutil.copytree(HERE / "photone", OUT / "photone", ignore=shutil.ignore_patterns("__pycache__"))
    # Photone.exe starts it (scripts/launcher: built once, kept in the repository). The .bat
    # does the same through python.exe, with a console that stays: for when it will not start.
    shutil.copy(HERE / "scripts" / "launcher" / "Photone.exe", OUT)
    (OUT / "Photone-console.bat").write_text(
        '@echo off\n"%~dp0python\\python.exe" -X utf8 -m photone %*\npause\n', newline="\r\n")
    size = sum(file.stat().st_size for file in OUT.rglob("*") if file.is_file())
    print(f"Built {OUT} ({size / 2 ** 20:.0f} MB). On Windows, start Photone.exe in it.")


if __name__ == "__main__":
    main()
