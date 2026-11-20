"""The DNG file Photone's neural denoiser writes, and reading it back.

A denoised photo is no mosaic any more: it is kept as a "linear raw" DNG, three 16-bit floats
a pixel in the camera's own colors (white balance not applied, 1.0 the sensor's white), with
the camera's color matrix and as-shot white balance, so that any raw developer treats it as
the raw file it came from. The pixels lie as the sensor had them, the header says which way
is up, and the preview the camera made is carried along.

The pixels are packed without loss as DNGs pack floats: in strips of STRIP rows, each row's
bytes sorted by significance and turned into differences from the pixel before (TIFF's
floating-point predictor), then deflated. 91 MB for a 33 MP photo at ISO 12800, where plain
32-bit floats were 375 MB. (Half floats: a value is off by 0.02 % of itself at most, finer
than a sensor's 14 bits over most of its range, and what Photone shows a photo from anyway;
the owner, 2026-11-20: "lets go 16bit and packed".)

Photone does not hand such a file to LibRaw, which would round it to 16-bit integers: `read`
takes the floats as they are. What it needs beyond the pixels is in the file's private tag
(DNGPrivateData, which begins with our name), and that tag is also how a file is known to be
one of these (`made_here`): it cannot be denoised twice.
"""

from __future__ import annotations

import json
import struct
import zlib
from concurrent.futures import ThreadPoolExecutor
from fractions import Fraction
from pathlib import Path

import numpy as np

OURS = b"Photone\0"  # how the private tag begins
STRIP = 256  # rows packed together: a piece of work for one thread, writing and reading
# Quarter turns to the left (numpy's rot90) that put the sensor's picture upright, by the
# header's orientation (EXIF: 3 upside down, 6 lying on its left side, 8 on its right).
TURNS = {3: 2, 6: 3, 8: 1}
# (tag: type) of what the header carries over from the original, where it has them: maker,
# model and date in the first directory; shutter, aperture, ISO, date taken, exposure
# compensation, focal length and lens in the EXIF one. Types: 2 text, 3 short, 5 fraction,
# 10 signed fraction.
FIRST = {0x10f: 2, 0x110: 2, 0x132: 2}
EXIF = {0x829a: 5, 0x829d: 5, 0x8827: 3, 0x9003: 2, 0x9204: 10, 0x920a: 5, 0xa434: 2}
FORM = {1: "B", 2: "s", 3: "H", 4: "I", 5: "I", 10: "i"}


def _packed(kind: int, values) -> tuple[int, bytes]:
    """(how many, the bytes) of a tag's values: a text, or numbers; fractions as two each."""
    if kind == 2:
        text = str(values).encode("ascii", "replace") + b"\0"
        return len(text), text
    values = list(values) if isinstance(values, (list, tuple)) else [values]
    if kind in (5, 10):
        parts = [Fraction(float(v)).limit_denominator(1_000_000) for v in values]
        flat = [n for part in parts for n in (part.numerator, part.denominator)]
        return len(values), struct.pack(f"<{len(flat)}{FORM[kind]}", *flat)
    return len(values), struct.pack(f"<{len(values)}{FORM[kind]}", *values)


def _directory(tags: dict, at: int) -> bytes:
    """A TIFF directory that will lie at `at` of the file, with what does not fit in its
    entries straight after it. `tags`: {tag: (type, values)}; a value may be bytes (type 1)."""
    entries, extra = b"", b""
    after = at + 2 + 12 * len(tags) + 4
    for tag in sorted(tags):
        kind, values = tags[tag]
        count, data = (len(values), values) if isinstance(values, bytes) else _packed(kind, values)
        if len(data) <= 4:
            where = data.ljust(4, b"\0")
        else:
            where = struct.pack("<I", after + len(extra))
            extra += data + b"\0" * (len(data) % 2)
        entries += struct.pack("<HHI", tag, kind, count) + where
    return struct.pack("<H", len(tags)) + entries + struct.pack("<I", 0) + extra


def _size_of(tags: dict) -> int:
    return len(_directory(tags, 0))


def _pack(part: np.ndarray) -> bytes:
    """Rows of (n, wide, 3) floats as a strip of the file: half floats, each row's bytes sorted
    by significance (all the first bytes, then all the second), each less the byte a pixel
    before it, deflated."""
    high, wide = part.shape[:2]
    halves = part.astype(">f2").view(np.uint8).reshape(high, wide * 3, 2)
    sorted_ = halves.transpose(0, 2, 1).reshape(high, -1)
    apart = sorted_.copy()
    apart[:, 3:] -= sorted_[:, :-3]
    return zlib.compress(apart.tobytes(), 6)


def _unpack(strip: bytes, high: int, wide: int) -> np.ndarray:
    """`_pack` backwards: (high, wide, 3) half floats. A ValueError where it is not such a strip."""
    try:
        apart = np.frombuffer(zlib.decompress(strip), np.uint8)
    except zlib.error as e:
        raise ValueError(f"its pixels do not unpack ({e})") from None
    if apart.size != high * wide * 6:
        raise ValueError("its pixels are cut short")
    sorted_ = np.cumsum(apart.reshape(high, wide * 2, 3), axis=1, dtype=np.uint8)
    halves = sorted_.reshape(high, 2, wide * 3).transpose(0, 2, 1)
    return np.ascontiguousarray(halves).view(">f2").reshape(high, wide, 3)


def write(path: Path, rows, size: tuple[int, int], about: dict) -> None:  # noqa: PLR0915
    """The DNG at `path`, whole or not at all. `rows(top, bottom)`: those rows of the picture
    as (n, wide, 3) floats, in the camera's colors with 1.0 its white, lying as the sensor
    had it (asked for from several threads at once); `size`: (wide, high) of all of it.
    `about`: `cam_xyz` and `wb` (the camera's
    matrix from XYZ and its white balance as gains, green 1), `turned` (the header's
    orientation), `header` ({tag: value} of FIRST and EXIF), `preview` (a JPEG and its
    (wide, high), or None), `kept` (what `read` hands on: see there) and `neural` (what was
    done: the model and the shares)."""
    wide, high = size
    tops = range(0, high, STRIP)
    with ThreadPoolExecutor(8) as threads:
        strips = list(threads.map(lambda top: _pack(rows(top, min(top + STRIP, high))), tops))
    private = OURS + json.dumps({"neural": about["neural"], **about["kept"]}).encode("utf-8")
    header, preview = about.get("header", {}), about.get("preview")
    neutral = [1 / gain for gain in about["wb"]]
    first = {
        254: (4, 0), 256: (4, wide), 257: (4, high), 258: (3, [16, 16, 16]), 259: (3, 8),
        262: (3, 34892), 273: (4, [0] * len(strips)), 274: (3, about.get("turned", 1)),
        277: (3, 3), 278: (4, STRIP), 279: (4, [len(strip) for strip in strips]), 284: (3, 1),
        305: (2, about.get("software", "Photone")), 317: (3, 3), 339: (3, [3, 3, 3]),
        50706: (1, bytes([1, 4, 0, 0])), 50707: (1, bytes([1, 4, 0, 0])),
        50708: (2, " ".join(filter(None, (header.get(0x10f), header.get(0x110)))) or "Photone"),
        50714: (5, [0, 0, 0]), 50717: (4, [1, 1, 1]),
        50721: (10, [v for row in about["cam_xyz"] for v in row]), 50728: (5, neutral),
        50740: (1, private), 50778: (3, 21),
        **{tag: (kind, header[tag]) for tag, kind in FIRST.items() if header.get(tag)},
    }
    exif = {tag: (kind, header[tag]) for tag, kind in EXIF.items() if header.get(tag)}
    small = preview and {
        254: (4, 1), 256: (4, preview[1][0]), 257: (4, preview[1][1]), 258: (3, [8, 8, 8]),
        259: (3, 7), 262: (3, 6), 273: (4, 0), 277: (3, 3), 278: (4, preview[1][1]),
        279: (4, len(preview[0]))}
    # Where each part lies: the directories one after another, the preview, then the pixels.
    if exif:
        first[34665] = (4, 0)
    if small:
        first[330] = (4, 0)
    exif_at = 8 + _size_of(first)
    small_at = exif_at + (_size_of(exif) if exif else 0)
    jpeg_at = small_at + (_size_of(small) if small else 0)
    pixels_at = -(-(jpeg_at + (len(preview[0]) if small else 0)) // 8) * 8
    first[273] = (4, [pixels_at + sum(len(s) for s in strips[:n]) for n in range(len(strips))])
    if exif:
        first[34665] = (4, exif_at)
    if small:
        first[330], small[273] = (4, small_at), (4, jpeg_at)
    head = b"II*\0" + struct.pack("<I", 8) + _directory(first, 8)
    head += _directory(exif, exif_at) if exif else b""
    head += (_directory(small, small_at) + preview[0]) if small else b""
    new = path.with_name(path.name + ".part")
    try:
        with new.open("wb") as file:
            file.write(head.ljust(pixels_at, b"\0"))
            for strip in strips:
                file.write(strip)
        new.replace(path)
    finally:
        new.unlink(missing_ok=True)


def _first(file) -> dict:
    """{tag: (type, count, the entry's four bytes)} of the first directory of a little-endian
    TIFF file, or nothing. Read as untrusted: any .dng is asked whether it is ours."""
    head = file.read(8)
    if len(head) < 8 or head[:4] != b"II*\0":
        return {}
    file.seek(struct.unpack("<I", head[4:])[0])
    count = struct.unpack("<H", file.read(2).ljust(2, b"\0"))[0]
    entries = file.read(12 * min(count, 200))
    each = (struct.unpack("<HHI4s", entries[at:at + 12]) for at in range(0, len(entries) - 11, 12))
    return {tag: (kind, length, value) for tag, kind, length, value in each}


def _number(entry: tuple) -> int:
    kind, _, value = entry
    return struct.unpack("<H", value[:2])[0] if kind == 3 else struct.unpack("<I", value)[0]


def _held(file) -> tuple[dict, dict] | None:
    """(the first directory, what the private tag holds) of a file of ours; None for any other."""
    tags = _first(file)
    kind, length, value = tags.get(50740, (0, 0, b""))
    if kind != 1 or not len(OURS) < length < 1 << 20:
        return None
    file.seek(struct.unpack("<I", value)[0])
    private = file.read(length)
    if not private.startswith(OURS):
        return None
    try:
        held = json.loads(private[len(OURS):].decode("utf-8"))
    except ValueError:
        return None
    return (tags, held) if isinstance(held, dict) and "neural" in held else None


def made_here(path: Path) -> dict | None:
    """What Photone's neural denoiser says it did to this file ({"model", "color", "grain"}),
    or None for a file it did not make. The header only: well under a millisecond."""
    if path.suffix.lower() != ".dng":
        return None
    try:
        with path.open("rb") as file:
            found = _held(file)
    except (OSError, struct.error):
        return None
    return found[1]["neural"] if found else None


def _numbers(file, entry: tuple) -> list[int]:
    """A tag's numbers (shorts or longs), from the entry itself or from where it points."""
    kind, count, value = entry
    size = 2 if kind == 3 else 4
    if not 0 < count <= 1 << 16:
        raise ValueError("a count out of range")
    if count * size > 4:
        file.seek(struct.unpack("<I", value)[0])
        value = file.read(count * size)
    return list(struct.unpack(f"<{count}{'H' if kind == 3 else 'I'}", value[:count * size]))


def _laid(file, tags: dict) -> tuple[int, int, int, list]:
    """(wide, high, the orientation, where each strip lies and how long it is) of a file of
    ours; a KeyError or ValueError where its first directory is not as `write` makes it."""
    wide, high, each = (_number(tags[tag]) for tag in (256, 257, 278))
    places = list(zip(_numbers(file, tags[273]), _numbers(file, tags[279]), strict=True))
    if not (0 < wide < 1 << 16 and 0 < high < 1 << 16 and each == STRIP
            and len(places) == -(-high // STRIP)):
        raise ValueError
    return wide, high, _number(tags[274]) if 274 in tags else 1, places


def read(path: Path, half: bool) -> tuple[dict, np.ndarray] | None:
    """A file of ours as Photone shows any raw file: (what it kept of the original: `camera`
    ({"wb", "cam_xyz", "lens"}), `light` (decode.light_of's figures) and `full` (the upright
    picture's (wide, high)); the picture upright, (h, w, 4) half floats of linear Rec.2020
    with the camera's white balance on, between 0 and 1 as LibRaw hands a raw file over).
    `half`: every second pixel each way, for the quick first picture. None for a file that is
    not ours; a ValueError where one of ours is cut short or otherwise not as written."""
    with path.open("rb") as file:
        found = _held(file)
        if not found:
            return None
        try:
            wide, high, turned, places = _laid(file, found[0])
            matrix = np.array(found[1]["matrix"], np.float32).reshape(3, 3)
        except (KeyError, ValueError, TypeError, struct.error):
            raise ValueError(f"{path.name}: not as Photone wrote it") from None
    step = 2 if half else 1
    out = np.ones((-(-high // step), -(-wide // step), 4), np.float16)

    def strip(n: int) -> None:
        with path.open("rb") as file:  # (one each: they read at the same time)
            file.seek(places[n][0])
            packed = file.read(places[n][1])
        rows = _unpack(packed, min(STRIP, high - n * STRIP), wide)[::step, ::step]
        out[n * STRIP // step:n * STRIP // step + len(rows), :, :3] = np.clip(
            rows.astype(np.float32) @ matrix.T, 0, 1)

    try:
        with ThreadPoolExecutor(8) as threads:
            list(threads.map(strip, range(len(places))))
    except ValueError as e:
        raise ValueError(f"{path.name}: {e}") from None
    if turned in TURNS:
        out = np.ascontiguousarray(np.rot90(out, TURNS[turned]))
    full = (wide, high) if turned not in (6, 8) else (high, wide)
    return {"camera": found[1].get("camera"), "light": found[1].get("light"), "full": full}, out
