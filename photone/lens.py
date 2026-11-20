"""Lens corrections from what a raw file carries: the camera's own figures for the lens that
was on it (distortion, chromatic aberration, vignetting), whatever the lens. Sony's so far."""

import math
import struct
from pathlib import Path

KNOTS = 16  # figures a correction has at most, from the picture's middle to its corner


def _directory(file, start: int, order: str, wanted: dict, depth: int = 0) -> dict:
    """The tags `wanted` ({tag: how many values at most}) from the TIFF directory at `start`
    and from the directories of pictures it points to (0x14a), as lists of signed numbers.
    Read as untrusted: counts are bounded, and it never goes deeper than two levels."""
    found = {}
    file.seek(start)
    count = struct.unpack(order + "H", file.read(2))[0]
    entries = file.read(12 * min(count, 200))
    for at in range(0, len(entries) - 11, 12):
        tag, kind, length, value = struct.unpack(order + "HHI4s", entries[at:at + 12])
        where = struct.unpack(order + "I", value)[0]
        if tag == 0x14a and depth < 2 and kind in (4, 13):
            places = [where]
            if length > 1:
                file.seek(where)
                several = min(length, 8)
                places = list(struct.unpack(order + f"{several}I", file.read(4 * several)))
            for place in places:
                found = {**_directory(file, place, order, wanted, depth + 1), **found}
        elif tag in wanted and kind in (3, 8) and 1 <= length <= wanted[tag]:
            if length > 2:
                file.seek(where)
                raw = file.read(2 * length)
            else:
                raw = value[:2 * length]
            if len(raw) == 2 * length:
                found[tag] = list(struct.unpack(order + f"{length}h", raw))
    return found


def figures(path: Path) -> dict | None:
    """The camera's correction figures in a raw file, or None where there are none (not a
    Sony raw file, or a lens the camera knew nothing of): `distortion`, `red`, `blue` and
    `vignetting`, each a list of as many numbers (2 to KNOTS) as the camera wrote them, from
    near the picture's middle to its corner. Any of the four may be missing."""
    wanted = {0x7032: KNOTS + 1, 0x7035: 2 * KNOTS + 1, 0x7037: KNOTS + 1}
    try:
        with open(path, "rb") as file:
            head = file.read(8)
            order = {b"II": "<", b"MM": ">"}.get(head[:2])
            if order is None or struct.unpack(order + "H", head[2:4])[0] != 42:
                return None
            found = _directory(file, struct.unpack(order + "I", head[4:8])[0], order, wanted)
    except (OSError, struct.error):
        return None
    out = {}
    for tag, name in ((0x7037, "distortion"), (0x7032, "vignetting")):
        had = found.get(tag, [0])
        if 2 <= had[0] <= KNOTS and len(had) >= had[0] + 1:
            out[name] = had[1:had[0] + 1]
    had = found.get(0x7035, [0])  # (how many, then that many for red and as many for blue)
    count = had[0] // 2
    if had[0] % 2 == 0 and 2 <= count <= KNOTS and len(had) >= 2 * count + 1:
        out["red"], out["blue"] = had[1:count + 1], had[count + 1:2 * count + 1]
    return out or None


def _at(values: list, r: float) -> float:
    """A correction's figure at that distance from the middle (1: the corner): its figures
    stand at (i + 0.5) / (count - 1), with a straight line between two and the first and the
    last holding beyond them."""
    x = min(max(r * (len(values) - 1) - 0.5, 0.0), len(values) - 1.0)
    low = min(int(x), len(values) - 2)
    return values[low] + (values[low + 1] - values[low]) * (x - low)


def _at_table(table: list, r: float) -> float:
    """One of `tables`' sixteen numbers at that distance from the middle, as the shader reads
    it: the first at the middle, the last at the corner, a straight line between two."""
    x = min(max(r, 0.0), 1.0) * (KNOTS - 1)
    low = min(int(x), KNOTS - 2)
    return table[low] + (table[low + 1] - table[low]) * (x - low)


def tables(found: dict | None, distortion: bool, color: bool, vignetting: bool) -> dict:
    """The corrections that are switched on, as the shader takes them: sixteen numbers each,
    at sixteenths of the way from the picture's middle to its corner (the first at 0, the last
    at the corner). `lensGreen`: a pixel at that distance shows what the stored picture has
    this many times further out (distortion; 1: where it is); `lensRed`, `lensBlue`: the same
    for red and for blue, which the lens draws a little larger or smaller than green
    (chromatic aberration); `lensLight`: it is made this many times lighter (vignetting).
    `lensOn`: whether any of it is anything. With distortion the whole is drawn that much
    larger that the corner still shows the corner: nothing of the frame is left empty."""
    found = found or {}
    ones = [1.0] * KNOTS
    out = {"lensOn": 0.0, "lensGreen": ones, "lensRed": ones, "lensBlue": ones, "lensLight": ones}
    places = [n / (KNOTS - 1) for n in range(KNOTS)]
    if distortion and "distortion" in found:
        far = [1 + _at(found["distortion"], r) * 2 ** -14 for r in places]
        # (As far as is furthest anywhere along the frame's edges, which lie from half way out
        # on: of three ways tried against the camera's own corrected preview in the owner's
        # files, this one put the corners nearest to where the camera has them.)
        fit = max(far[KNOTS // 2:])
        out["lensGreen"] = [f / fit for f in far]
    out["lensRed"], out["lensBlue"] = out["lensGreen"], out["lensGreen"]
    if color and "red" in found:
        for name, key in (("lensRed", "red"), ("lensBlue", "blue")):
            out[name] = [green * (1 + _at(found[key], r) * 2 ** -21)
                         for green, r in zip(out["lensGreen"], places, strict=True)]
    if vignetting and "vignetting" in found:
        out["lensLight"] = [2 ** (2 ** (_at(found["vignetting"], r) * 2 ** -13 - 1) - 0.5)
                            for r in places]
    changed = any(not math.isclose(value, 1.0, abs_tol=1e-7)
                  for name in ("lensGreen", "lensRed", "lensBlue", "lensLight")
                  for value in out[name])
    return {**out, "lensOn": 1.0 if changed else 0.0}
