"""LUTs as .cube files: reading one (a look made elsewhere, laid on the photo by the shader),
and writing one. A .clf file of one 3D table is read too, as the same table."""

import hashlib
from xml.etree import ElementTree

import numpy as np

LARGEST = 65          # points a side a LUT may have
BYTES = 40_000_000    # a .cube file larger than this is not read (65 points a side is 8 MB)
# What a CLF table's numbers run up to, by its outBitDepth: integers to their largest, floats to 1.
DEPTHS = {"8i": 255.0, "10i": 1023.0, "12i": 4095.0, "16i": 65535.0, "16f": 1.0, "32f": 1.0}
ASIDE = {"Description", "InputDescriptor", "OutputDescriptor", "Info"}  # (a CLF's words, no step)


def _size(head: dict) -> int:
    """How many points a side the file says it has, having looked at what else it says."""
    if "LUT_1D_SIZE" in head:
        raise ValueError("it is a 1D LUT; only 3D LUTs can be used")
    if "LUT_3D_SIZE" not in head:
        raise ValueError("it does not say its size (LUT_3D_SIZE)")
    try:
        size = int(head["LUT_3D_SIZE"][0])
        low = [float(w) for w in head.get("DOMAIN_MIN", ["0", "0", "0"])]
        high = [float(w) for w in head.get("DOMAIN_MAX", ["1", "1", "1"])]
    except (IndexError, ValueError) as e:
        raise ValueError("its size or its range is not a number") from e
    if not 2 <= size <= LARGEST:
        raise ValueError(f"a LUT of {size} points a side (2 to {LARGEST} can be used)")
    if low != [0.0, 0.0, 0.0] or high != [1.0, 1.0, 1.0]:
        raise ValueError("its input range is not 0 to 1 (DOMAIN_MIN, DOMAIN_MAX)")
    return size


def parse(text: str) -> np.ndarray:
    """A 3D .cube file's table as floats, indexed [blue][green][red] (the file's own order:
    red runs fastest), or ValueError saying what is wrong with it. Read as untrusted: no
    longer than BYTES, and of the size it says. A .clf file's too (`_clf`)."""
    if len(text) > BYTES:
        raise ValueError("the file is too large to be a LUT")
    begun = text.lstrip(chr(0xFEFF) + " \t\r\n")  # (a byte order mark: some programs write one)
    return _clf(begun) if begun.startswith("<") else _cube(text)


def _cube(text: str) -> np.ndarray:
    head, rows = {}, []
    for line in text.splitlines():
        words = line.split("#")[0].split()
        if words and (words[0][0].isalpha() or words[0][0] == "_"):
            head[words[0].upper()] = words[1:]  # (TITLE and whatever else was written into it, too)
        elif words:
            rows.append(words[:3])
    size = _size(head)
    if len(rows) != size ** 3 or any(len(row) != 3 for row in rows):
        raise ValueError(f"{len(rows)} colors where {size ** 3} are needed")
    try:
        table = np.array(rows, dtype=np.float32).reshape(size, size, size, 3)
    except ValueError as e:
        raise ValueError("it holds something that is no number") from e
    if not np.isfinite(table).all():
        raise ValueError("it holds numbers that are no colors")
    return table


def _tag(element) -> str:
    """An XML element's name without its namespace (CLF 2 and 3 have each their own)."""
    return str(element.tag).rpartition("}")[2]


def _lut3d(text: str) -> ElementTree.Element:
    """The one step of a CLF file (Common LUT Format: XML) where it is a LUT3D, or ValueError
    saying what the file does instead."""
    if "<!DOCTYPE" in text or "<!ENTITY" in text:  # (an entity can be made to grow huge)
        raise ValueError("it declares a DOCTYPE, which a CLF file does not")
    try:
        root = ElementTree.fromstring(text)
    except ElementTree.ParseError as e:
        raise ValueError("it is not XML that can be read") from e
    if _tag(root) != "ProcessList":
        raise ValueError("it is no CLF file (no ProcessList)")
    steps = [step for step in root if _tag(step) not in ASIDE]
    if [_tag(step) for step in steps] != ["LUT3D"]:
        did = ", ".join(_tag(step) for step in steps) or "nothing"
        raise ValueError(f"it does {did}; a CLF of one LUT3D alone can be used")
    return steps[0]


def _clf(text: str) -> np.ndarray:
    """A CLF file of one 3D table as `parse` has a .cube file's. In a CLF blue runs fastest,
    and the numbers run up to what its outBitDepth says."""
    lut3d = _lut3d(text)
    arrays = [part for part in lut3d if _tag(part) == "Array"]
    if len(arrays) != 1 or any(_tag(part) == "IndexMap" for part in lut3d):
        raise ValueError("its LUT3D is not one Array alone")
    depth = DEPTHS.get(lut3d.get("outBitDepth", ""))
    if depth is None:
        said = lut3d.get("outBitDepth")
        raise ValueError(f"its outBitDepth {said!r} is none of {', '.join(DEPTHS)}")
    dim = arrays[0].get("dim", "").split()
    if len(dim) != 4 or not "".join(dim).isdigit() or len(set(dim[:3])) != 1 or dim[3] != "3":
        raise ValueError(f"its Array is not of N N N 3 (dim {' '.join(dim)!r})")
    size = int(dim[0])
    if not 2 <= size <= LARGEST:
        raise ValueError(f"a LUT of {size} points a side (2 to {LARGEST} can be used)")
    words = (arrays[0].text or "").split()
    if len(words) != 3 * size ** 3:
        raise ValueError(f"{len(words) // 3} colors where {size ** 3} are needed")
    table = _colors(words, size) / np.float32(depth)
    return np.ascontiguousarray(table.transpose(2, 1, 0, 3))  # ([red][green][blue] as it is)


def fingerprint(table: np.ndarray) -> str:
    """What a table is told by: its colors themselves, not the file they came in. Two files
    that differ in their name, title, comments or spacing have the same."""
    exact = np.ascontiguousarray(table, dtype="<f4")
    return hashlib.sha1(str(len(table)).encode() + exact.tobytes()).hexdigest()[:20]


def written(text: str) -> str:
    """What a .cube file's text is told by. (What an installed LUT was kept under before LUTs
    were told by their colors: a photo may still name its LUT so.)"""
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:20]


def title(text: str) -> str:
    """The name a .cube file gives itself (TITLE), or nothing."""
    for line in text.splitlines()[:50]:
        if line.strip().upper().startswith("TITLE"):
            return line.strip()[5:].strip().strip('"').strip()[:80]
    return ""


def atlas(table: np.ndarray) -> np.ndarray:
    """The table as the picture the shader reads it from: its slices of one blue each side by
    side, red across and green down, as half floats with an alpha of 1 (rows, columns, 4)."""
    size = len(table)
    flat = np.ones((size, size * size, 4), np.float16)
    flat[..., :3] = table.transpose(1, 0, 2, 3).reshape(size, size * size, 3)
    return flat


def stacked(tables: list[np.ndarray]) -> np.ndarray:
    """Several tables as one picture, each one's slices (`atlas`) in a band of its own, one
    under the other from the left edge: what the shader reads a photo's LUTs from."""
    bands = [atlas(table) for table in tables]
    wide = max(band.shape[1] for band in bands)
    whole = np.ones((sum(len(band) for band in bands), wide, 4), np.float16)
    top = 0
    for band in bands:
        whole[top:top + len(band), :band.shape[1]] = band
        top += len(band)
    return whole


def bands(luts: list[dict]) -> dict[tuple[str, int], int]:
    """Where each of a photo's LUTs lies in the picture they are read from: the row its band
    begins at, by (id, size). By id, not by their order on the photo, and one band for a LUT
    that is there twice: the picture is then the same whatever their order."""
    tops, top = {}, 0
    for key in sorted({(one["id"], int(one["size"])) for one in luts}):
        tops[key] = top
        top += key[1]
    return tops


def address(luts: list[dict]) -> str:
    """What the picture of those LUTs (the edit's `luts`) is asked for by: each band's id and
    size, so that one whose file is gone can be stood in for by a table that changes nothing."""
    return "-".join(f"{name}.{size}" for name, size in bands(luts))


def asked(which: str) -> list[tuple[str, int]]:
    """`address` read back as (id, size) each, or ValueError: it comes from outside."""
    found = []
    for part in which.split("-"):
        name, _, size = part.partition(".")
        if not (name.isalnum() and size.isdigit() and 2 <= int(size) <= LARGEST):
            raise ValueError(which)
        found.append((name, int(size)))
    return found


def identity(size: int) -> np.ndarray:
    """The table that changes nothing: each point its own color, [blue][green][red]."""
    steps = np.linspace(0.0, 1.0, size, dtype=np.float32)
    blue, green, red = np.meshgrid(steps, steps, steps, indexing="ij")
    return np.stack([red, green, blue], axis=-1)


def cube(table: np.ndarray, title: str) -> str:
    """The table as the text of a .cube file."""
    size = len(table)
    rows = "\n".join(f"{r:.6f} {g:.6f} {b:.6f}" for r, g, b in table.reshape(-1, 3).tolist())
    name = "".join(c for c in title if c.isprintable() and c != '"')[:80]
    return f'TITLE "{name}"\nLUT_3D_SIZE {size}\n\n{rows}\n'
