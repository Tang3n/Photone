"""Shaders are written as Vulkan-style GLSL (ui/*.frag) and Qt wants them as .qsb packages that
carry a version for each graphics API. They are compiled on first use and kept in the cache,
named by the hash of their source, so an edited shader is rebuilt and an unchanged one is free."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
from pathlib import Path

import PySide6
from PySide6.QtGui import QMatrix4x4, QVector4D

from photone import QUIET

UI = Path(__file__).parent / "ui"


def cache() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME") or os.environ.get("LOCALAPPDATA")
                or Path.home() / ".cache") / "photone" / "shaders"


def whole(file: str) -> str:
    """ui/<file> with every `#include "x"` line replaced by ui/x: the compiler has no include."""
    return re.sub(r'(?m)^#include "(.+)"$', lambda found: (UI / found[1]).read_text("utf-8"),
                  (UI / file).read_text("utf-8"))


def compiled(file: str) -> Path:
    """ui/<file> (pipeline.frag, wheel.vert, …) as a .qsb, built if its source changed."""
    text = whole(file)
    digest = hashlib.sha1(text.encode()).hexdigest()[:12]
    source = cache() / f"{Path(file).stem}-{digest}{Path(file).suffix}"  # as given to the compiler
    out = source.with_name(source.name + ".qsb")
    if out.exists():
        return out
    # Inside PySide6 itself, wherever that is (an environment, or the Windows build's folder).
    tool = shutil.which("qsb", path=str(Path(PySide6.__file__).parent))
    if not tool:
        raise RuntimeError("qsb, the shader compiler that comes with PySide6, is missing")
    out.parent.mkdir(parents=True, exist_ok=True)
    source.write_text(text, "utf-8")
    # SPIR-V for Vulkan is always in; GLSL for OpenGL and OpenGL ES, HLSL and Metal for the rest.
    done = subprocess.run([tool, "--glsl", "300 es,330", "--hlsl", "50", "--msl", "12",
                           "-o", str(out), str(source)], capture_output=True, text=True, **QUIET)
    if done.returncode:
        out.unlink(missing_ok=True)
        raise RuntimeError(f"{file} does not compile ({source}):\n{done.stderr or done.stdout}")
    return out


def by_columns(sixteen: list) -> QMatrix4x4:
    """Sixteen numbers as the matrix a shader reads them from, column by column."""
    return QMatrix4x4(*sixteen).transposed()


def for_qml(values: dict) -> dict:
    """What edit.uniforms works out, as the values a ShaderEffect's properties take: matrices
    of three rows of three, and the lists of sixteen numbers, which the shader reads by
    columns."""
    out = dict(values)
    for key in ("toCam", "fromCam"):
        rows = out[key]
        out[key] = QMatrix4x4(*rows[0], 0, *rows[1], 0, *rows[2], 0, 0, 0, 0, 1)
    for key, value in out.items():
        if isinstance(value, list) and len(value) == 16:
            out[key] = by_columns(value)
    out["wbGain"] = QVector4D(*out["wbGain"])
    return out
