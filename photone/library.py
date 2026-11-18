"""The library: which photos there are. Folders are added by reference and scanned; nothing is
copied or moved, and nothing is ever written beside a photo (PLAN.md, safety rule 1). What a
scan finds goes into the catalog (photone/catalog.py), a thumbnail of each photo into the cache.

Nothing here needs a window: `describe`, `scan` and `thumbnail` are plain functions, tried by
tests/check.py. `Library` is what the interface talks to.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import threading
import time
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

import numpy as np
from PySide6.QtCore import (
    Property,
    QAbstractListModel,
    QBuffer,
    QByteArray,
    QModelIndex,
    QObject,
    QSize,
    Qt,
    QUrl,
    Signal,
    Slot,
)
from PySide6.QtDBus import QDBusConnection, QDBusMessage
from PySide6.QtGui import QDesktopServices, QImage, QImageReader, QTransform
from PySide6.QtQuick import QQuickItem

from photone import decode, edit
from photone.catalog import MARKS, Catalog, identify

THUMB = 512  # a thumbnail's longer side, in pixels
# In the interface's language, whatever the desktop's: Qt sets the program's locale, and the
# months would come out in it.
MONTHS = ("January", "February", "March", "April", "May", "June", "July", "August",
          "September", "October", "November", "December")


def within(path: str, folder: str) -> bool:
    """Is that photo in that folder, or in one inside it? (By the system's own separator: with
    "/" alone a folder on Windows showed no photos.)"""
    return path.startswith(folder.rstrip("/\\") + os.sep)


def thumbs() -> Path:
    """Where thumbnails are kept. ("-2": those of raw files made before 2026-11-17 did not take
    the camera's exposure compensation back; `Library` clears the folder they were in.)"""
    return Path(os.environ.get("XDG_CACHE_HOME") or os.environ.get("LOCALAPPDATA")
                or Path.home() / ".cache") / "photone" / "thumbs-2"


# ---- what a file says about itself ---------------------------------------------------------

def _tiff(file, start: int) -> dict:
    """The few tags wanted from a TIFF header at `start` of an open file (most raw formats are
    TIFF files, and a JPEG's EXIF block is one): 0x10f maker, 0x110 model, 0x112 orientation,
    0x132 and 0x9003 date and 0x9204 exposure compensation (in stops), the latter two in the
    EXIF directory that 0x8769 points to; and from there what `about` tells: 0x829a shutter
    (seconds), 0x829d aperture, 0x8827 ISO, 0x920a focal length (mm), 0xa434 lens."""
    file.seek(start)
    head = file.read(8)
    order = {b"II": "<", b"MM": ">"}.get(head[:2])
    if order is None or struct.unpack(order + "H", head[2:4])[0] not in (42, 85):  # 85: Panasonic
        return {}
    found, todo = {}, [struct.unpack(order + "I", head[4:8])[0]]
    for _ in range(4):  # the first directory and the EXIF one; never round in circles
        if not todo:
            break
        file.seek(start + todo.pop())
        count = struct.unpack(order + "H", file.read(2))[0]
        entries = file.read(12 * min(count, 200))
        for at in range(0, len(entries) - 11, 12):
            tag, kind, length, value = struct.unpack(order + "HHI4s", entries[at:at + 12])
            if tag == 0x8769:
                todo.append(struct.unpack(order + "I", value)[0])
            else:
                found.update(_entry(file, start, order, entries[at:at + 12]))
    return found


def _entry(file, start: int, order: str, entry: bytes) -> dict:
    """What one entry of a TIFF directory says, if it is one of those wanted: {tag: value}."""
    tag, kind, length, value = struct.unpack(order + "HHI4s", entry)
    where = start + struct.unpack(order + "I", value)[0]  # of what does not fit in the entry
    if tag in (0x112, 0x8827) and kind == 3:
        return {tag: struct.unpack(order + "H", value[:2])[0]}
    if tag in (0x10f, 0x110, 0x132, 0x9003, 0xa434) and kind == 2 and length < 200:
        return {tag: _text(file, where, value, length)}
    if tag in (0x9204, 0x829a, 0x829d, 0x920a) and kind in (5, 10) and length == 1:
        return {tag: _fraction(file, where, order, kind == 10)}
    return {}


def _fraction(file, where: int, order: str, signed: bool = True) -> float:
    """A fraction of a TIFF directory (an exposure compensation, signed; a shutter time,
    an aperture, a focal length, not), kept at `where`."""
    here = file.tell()
    file.seek(where)
    over, under = struct.unpack(order + ("ii" if signed else "II"), file.read(8))
    file.seek(here)
    return over / under if under else 0.0


def _text(file, where: int, value: bytes, length: int) -> str:
    """A text of a TIFF directory: in the entry itself if it is short, else at `where`."""
    text = value[:length]
    if length > 4:
        here = file.tell()
        file.seek(where)
        text = file.read(length)
        file.seek(here)
    return text.split(b"\0")[0].decode("ascii", "replace").strip()


def _exif_start(file) -> int | None:
    """Where the TIFF header lies: at the start of most raw files, in the EXIF block of a JPEG."""
    head = file.read(4)
    if head[:2] in (b"II", b"MM"):
        return 0
    if head[:2] != b"\xff\xd8":
        return None
    at = 2
    for _ in range(40):  # a JPEG's blocks, until the EXIF one
        file.seek(at)
        block = file.read(10)
        if len(block) < 10 or block[0] != 0xff or block[1] == 0xda:
            return None
        if block[1] == 0xe1 and block[4:10] == b"Exif\0\0":
            return at + 10
        at += 2 + struct.unpack(">H", block[2:4])[0]
    return None


def describe(photo: Path) -> dict:
    """When a photo was taken (seconds, as local time), with what camera, how it is turned
    (EXIF orientation, 1 upright) and with what exposure compensation (`bias`, in stops, which
    only the catalog still asks for, for edits kept when the exposure started from it; 0
    where none is given), read from the file's own header: no decoding, well under a
    millisecond. Where the header is of a kind not read here (Canon CR3, Fujifilm RAF), or says
    nothing, the date is the file's and the camera unknown."""
    tags = {}
    try:
        with photo.open("rb") as file:
            start = _exif_start(file)
            tags = _tiff(file, start) if start is not None else {}
    except (OSError, struct.error):
        pass
    taken = None
    for tag in (0x9003, 0x132):
        try:
            taken = taken or datetime.strptime(tags.get(tag, ""), "%Y:%m:%d %H:%M:%S").timestamp()
        except ValueError:
            continue
    maker, model = tags.get(0x10f, ""), tags.get(0x110, "")
    camera = model if model.lower().startswith(maker.lower().split(" ")[0]) else f"{maker} {model}"
    bias = tags.get(0x9204, 0.0)
    return {"taken": taken or photo.stat().st_mtime, "camera": camera.strip(),
            "turned": tags.get(0x112, 1), "bias": bias if abs(bias) <= 10 else 0.0}


ROMAN = {"2": "II", "3": "III", "4": "IV", "5": "V", "6": "VI", "7": "VII", "8": "VIII"}
MAKERS = {"SONY": "Sony", "NIKON": "Nikon", "NIKON CORPORATION": "Nikon", "FUJIFILM": "Fujifilm",
          "OLYMPUS": "Olympus", "PENTAX": "Pentax", "RICOH": "Ricoh", "LEICA": "Leica",
          "PANASONIC": "Panasonic", "HASSELBLAD": "Hasselblad"}


def camera_name(written: str) -> str:
    """A camera as it is sold, from the maker and model its files carry: "SONY ILCE-7M4" is
    the "Sony Alpha 7 IV" (the owner: "the real camera name is `Sony Alpha 7 IV`"). Sony's
    codes follow a rule (ILCE or ILCA, the number and letters, M and the generation; DSC-RX
    likewise); Nikon writes a second generation as "_2"; makers written in capitals are
    written as they write themselves.
    ponytail: rules, not a list of every camera; other makers' codes (Panasonic DC-S5, say)
    stay as written. The upgrade is a table of model codes, such as ExifTool's."""
    maker, _, model = written.strip().partition(" ")
    maker = MAKERS.get(maker.upper(), maker)
    sony = re.fullmatch(r"(?:ILC[EA]-)(\d+[A-Z]*?)(?:M(\d))?", model) if maker == "Sony" else None
    if sony:
        model = f"Alpha {sony[1]}" + (f" {ROMAN.get(sony[2], sony[2])}" if sony[2] else "")
    rx = re.fullmatch(r"DSC-(RX\d+[A-Z]*?)(?:M(\d))?", model) if maker == "Sony" else None
    if rx:
        model = rx[1] + (f" {ROMAN.get(rx[2], rx[2])}" if rx[2] else "")
    if maker == "Nikon":
        model = model.removeprefix("CORPORATION ").removeprefix("NIKON ")
        model = re.sub(r"_(\d)$", lambda m: ROMAN.get(m[1], m[1]), model)
    return f"{maker} {model}".strip()


# Tamron writes a product code in place of a lens's name ("E 35-150mm F2.0-F2.8 A058"; the
# owner: "`A058` doesnt tell me anything"). The codes of its mirrorless lenses, as Tamron
# names them.
TAMRON = {
    "A036": "28-75mm F/2.8 Di III RXD", "A063": "28-75mm F/2.8 Di III VXD G2",
    "A046": "17-28mm F/2.8 Di III RXD", "A047": "70-300mm F/4.5-6.3 Di III RXD",
    "A056": "70-180mm F/2.8 Di III VXD", "A065": "70-180mm F/2.8 Di III VXD G2",
    "A057": "150-500mm F/5-6.7 Di III VC VXD", "A058": "35-150mm F/2-2.8 Di III VXD",
    "A062": "20-40mm F/2.8 Di III VXD", "A068": "17-50mm F/4 Di III VXD",
    "A069": "50-400mm F/4.5-6.3 Di III VC VXD", "A071": "28-200mm F/2.8-5.6 Di III RXD",
    "A074": "28-300mm F/4-7.1 Di III VC VXD", "A075": "25-200mm F/2.8-5.6 Di III VXD G2",
    "B060": "11-20mm F/2.8 Di III-A RXD", "B061": "17-70mm F/2.8 Di III-A VC RXD",
}


def lens_name(written: str, camera: str = "") -> str:
    """A lens as it is sold, from what its photos carry: Tamron's product codes by the lens's
    name, and Sony's own lenses (FE ..., E ... on a Sony) with the maker in front.
    ponytail: a table of Tamron's mirrorless lenses; an unknown code stays as written. The
    upgrade is lensfun's database once it knows them (it did not, 2026-11-18)."""
    code = re.search(r"\b([AB]\d{3})\b", written)
    if code and code[1] in TAMRON:
        return f"Tamron {TAMRON[code[1]]}"
    if not code and camera.startswith("Sony") and re.match(r"(FE|E) \d", written):
        return f"Sony {written}"
    return written


def _shutter(seconds: float) -> str:
    return f"1/{round(1 / seconds)} s" if seconds < 0.5 else f"{seconds:g} s"


def _bytes(size: int) -> str:
    return f"{size / 1e6:.1f} MB" if size >= 1e6 else f"{max(1, round(size / 1e3))} kB"


def _when(at: time.struct_time) -> str:
    """A date and time in words, in English whatever the system's language: "4 July 2026, 13:35"."""
    return f"{at.tm_mday} {MONTHS[at.tm_mon - 1]} {at.tm_year}, {at.tm_hour:02d}:{at.tm_min:02d}"


def about(photo: Path) -> dict:
    """What the left panel tells of a photo, as words: its file, folder and size on disk, and
    from its header when it was taken, with what camera and lens, and how it was exposed.
    What the header does not say is left out. (The header only: well under a millisecond.)"""
    tags = {}
    with contextlib.suppress(OSError, struct.error), photo.open("rb") as file:
        start = _exif_start(file)
        tags = _tiff(file, start) if start is not None else {}
    seen = describe(photo)
    shutter, aperture, iso, focal = (tags.get(t) for t in (0x829a, 0x829d, 0x8827, 0x920a))
    words = {
        "file": photo.name, "folder": str(photo.parent),
        "size": _bytes(photo.stat().st_size) if photo.exists() else "",
        "taken": _when(time.localtime(seen["taken"])),
        "camera": camera_name(seen["camera"]),
        "lens": lens_name(tags.get(0xa434, ""), camera_name(seen["camera"])),
        "shutter": _shutter(shutter) if shutter else "",
        "aperture": f"f/{aperture:.1f}".replace(".0", "") if aperture else "",
        "iso": f"ISO {iso}" if iso else "", "focal": f"{focal:.0f} mm" if focal else "",
        "bias": f"{seen['bias']:+.1f} EV".replace("-", "−") if seen["bias"] else "",
    }
    return {key: value for key, value in words.items() if value}


# ---- scanning ---------------------------------------------------------------------------------

def kind_of(photo: Path) -> str:
    return "raw" if photo.suffix.lower() in decode.RAW else "picture"


BATCH = 100  # photos found, before a scan hands them on: a new folder fills as it is read


def _same_name(files) -> dict[Path, list[Path]]:
    """The files of one name whatever their kind, by that name without its ending. (Looked
    up, not searched for: with 4,000 files in a folder the search took 3 s of a scan's 3.8.)"""
    out: dict[Path, list[Path]] = {}
    for file in sorted(files):
        out.setdefault(file.with_suffix(""), []).append(file)
    return out


def scan(folder: Path, known: dict[str, tuple[int, float]],
         each=None) -> tuple[list[dict], list[str]]:
    """Every photo under a folder: (rows for those that are new or have changed, the paths of
    those that were known and are no longer there). A raw file and a JPEG of the same name in
    the same folder are one photo, the raw one; the JPEG is noted as its `pair`. `each`: a
    function that is given the rows found so far, BATCH at a time, while the scan goes on (a
    large folder shows its first photos at once); what is returned is then the rest."""
    seen, rows = set(), []
    for here, _, names in os.walk(folder):
        files = {Path(here) / n for n in names
                 if Path(n).suffix.lower() in decode.RAW | decode.RASTER and not n.startswith(".")}
        raws = {f.with_suffix("") for f in files if kind_of(f) == "raw"}
        beside = _same_name(files)
        for photo in sorted(files):
            if kind_of(photo) != "raw" and photo.with_suffix("") in raws:
                continue  # the JPEG beside a raw file
            try:
                about = photo.stat()
            except OSError:
                continue
            size, changed = about.st_size, about.st_mtime
            seen.add(str(photo))
            if known.get(str(photo)) == (size, changed):
                continue
            key = identify(photo)
            if key is None:
                continue
            pair = next((str(f) for f in beside[photo.with_suffix("")] if f != photo), None)
            said = describe(photo)
            rows.append({"key": key, "path": str(photo), "folder": here, "name": photo.name,
                         "size": size, "changed": changed, "taken": said["taken"],
                         "camera": said["camera"], "kind": kind_of(photo), "pair": pair})
            if each and len(rows) >= BATCH:
                each(rows)
                rows = []
    return rows, [path for path in known if path not in seen]


# ---- thumbnails -------------------------------------------------------------------------------

def thumb_name(key: str) -> str:
    """The name a photo's thumbnail goes by, in the cache and in the interface."""
    return hashlib.blake2b(key.encode(), digest_size=12).hexdigest()


def _small(reader, name: str):
    """What an image reader holds, scaled while it is read so that its longer side is THUMB."""
    size = reader.size()
    if size.isValid():
        scale = min(1.0, THUMB / max(size.width(), size.height()))
        reader.setScaledSize(QSize(max(1, round(size.width() * scale)),
                                   max(1, round(size.height() * scale))))
    image = reader.read()
    if image.isNull():
        raise decode.Unreadable(f"{name}: {reader.errorString()}")
    return image


def _preview(photo: Path):
    """The picture a raw file carries of itself (a JPEG, as a rule), small and upright."""
    import rawpy

    try:
        with rawpy.imread(str(photo)) as raw:
            carried = raw.extract_thumb()
    except (rawpy.LibRawError, OSError) as e:
        raise decode.Unreadable(f"{photo.name}: no preview in this file ({e})") from e
    if carried.format == rawpy.ThumbFormat.JPEG:
        data = QBuffer()
        data.setData(QByteArray(carried.data))
        data.open(QBuffer.OpenModeFlag.ReadOnly)
        image = _small(QImageReader(data, b"jpeg"), photo.name)
    else:  # plain pixels
        high, wide = carried.data.shape[:2]
        held = carried.data.tobytes()  # (kept until the image has pixels of its own)
        image = QImage(held, wide, high, wide * 3, QImage.Format.Format_RGB888)
        image = image.scaled(THUMB, THUMB, Qt.AspectRatioMode.KeepAspectRatio).copy()
    quarter = {3: 180, 6: 90, 8: 270}.get(describe(photo)["turned"])
    return image.transformed(QTransform().rotate(quarter)) if quarter else image


def lifted(image: QImage, stops: float) -> QImage:
    """A finished picture made lighter or darker by so many stops, as nearly as that can be
    done to eight bits: in linear light, each channel by itself, what goes over white cut off."""
    if abs(stops) < 0.05:
        return image
    level = np.arange(256) / 255
    light = np.where(level <= 0.04045, level / 12.92, ((level + 0.055) / 1.055) ** 2.4)
    light = np.minimum(1.0, light * 2.0 ** max(-5.0, min(5.0, stops)))
    table = np.where(light <= 0.0031308, light * 12.92, 1.055 * light ** (1 / 2.4) - 0.055)
    table = np.round(table * 255).astype(np.uint8)
    image = image.convertToFormat(QImage.Format.Format_RGB888)
    wide, high, line = image.width(), image.height(), image.bytesPerLine()
    seen = np.frombuffer(image.constBits(), np.uint8, line * high).reshape(high, line)[:, :wide * 3]
    out = np.ascontiguousarray(table[seen])
    return QImage(out.data, wide, high, wide * 3, QImage.Format.Format_RGB888).copy()


def light_in(image: QImage) -> list[float]:
    """decode.light_of's two figures (the picture's median lightness, and the level only its
    brightest twentieth is above, as shares of the sensor's white), read from a finished picture of
    the photo: the preview a raw file carries, with the camera's curve taken off as nearly as
    the Standard profile's read backwards does. Near enough for a thumbnail."""
    image = image.convertToFormat(QImage.Format.Format_RGB888)
    wide, high, line = image.width(), image.height(), image.bytesPerLine()
    seen = np.frombuffer(image.constBits(), np.uint8, line * high).reshape(high, line)
    coded = seen[:, :wide * 3].reshape(high, wide, 3) / 255
    shown = np.where(coded <= 0.04045, coded / 12.92, ((coded + 0.055) / 1.055) ** 2.4)
    light = edit.sensed(shown)
    return [float(np.median(light @ np.array(decode.LUMA))),
            float(np.percentile(light.max(axis=-1), decode.TOP))]


def forget_starts(cache: Path, photos: list[dict]) -> None:
    """Once in a cache folder for each rule of where a photo's exposure starts (the marker's
    number: edit.exposure_of tells how the rule changed): the thumbnails of raw photos that
    have no edit are deleted, and made anew when next wanted. Thumbnails of edited photos
    (renders of the photo as it was left) stay."""
    marker = cache / ".starts-3"
    if marker.exists():
        return
    cache.mkdir(parents=True, exist_ok=True)
    for photo in photos:
        if photo["kind"] == "raw" and not photo["edited"]:
            (cache / f"{thumb_name(photo['key'])}.jpg").unlink(missing_ok=True)
    marker.touch()


def thumbnail(photo: Path, key: str, folder: Path | None = None) -> Path:
    """The photo's thumbnail in the cache (never beside the photo), made if it is not there:
    from the preview a raw file carries, or from the picture itself."""
    out = (folder or thumbs()) / f"{thumb_name(key)}.jpg"
    if out.exists():
        return out
    if kind_of(photo) == "raw":
        # As the photo opens: lighter than it was shot where it has room (edit.exposure_of).
        image = _preview(photo)
        image = lifted(image, edit.exposure_of(edit.DEFAULTS, {"light": light_in(image)}))
    else:
        reader = QImageReader(str(photo))
        reader.setAutoTransform(True)
        image = _small(reader, photo.name)
    out.parent.mkdir(parents=True, exist_ok=True)
    part = out.with_name(f"{out.name}.{os.getpid()}.{time.monotonic_ns()}.part")
    if not image.save(str(part), "JPEG", 85):
        raise decode.Unreadable(f"{photo.name}: its thumbnail could not be written")
    os.replace(part, out)  # whole or not at all: two may be making the same one
    return out


def lasts_in(settings) -> dict[str, str]:
    """The photo last looked at in each place, as the settings hold it; none if unreadable."""
    try:
        found = json.loads(settings.value("library/photos", "{}", type=str))
        return {k: v for k, v in found.items() if isinstance(v, str)}
    except (ValueError, AttributeError):
        return {}


# ---- what the interface talks to ------------------------------------------------------------

class PhotoModel(QAbstractListModel):
    """The photos on show in the grid, one row each. A model, not a list: the grid asks only
    for the rows it draws, and a mark changes one row instead of sending thousands again."""

    ROLES = ("key", "path", "name", "thumb", "kind", "pair", "flag", "stars", "label", "edited")

    def __init__(self, parent: QObject, cache: Path) -> None:
        super().__init__(parent)
        self.rows: list[dict] = []
        self.cache, self.ready = cache, set()  # the thumbnails there are, by name
        # Where each photo is in the grid, by its thumbnail's name and by its path: a thumbnail
        # just made and the marks of the open photo are looked up, not searched for.
        self.named: dict[str, list[int]] = {}
        self.pathed: dict[str, int] = {}
        # How often a thumbnail has been made anew in this run (the open photo's, as it is
        # edited): part of its address, or Qt would go on showing the one it has read.
        self.versions: dict[str, int] = {}

    def address(self, name: str) -> str:
        """Where Qt reads that thumbnail from."""
        again, file = self.versions.get(name), QUrl.fromLocalFile(str(self.cache / f"{name}.jpg"))
        return file.toString() + (f"?{again}" if again else "")

    def rowCount(self, parent=QModelIndex()) -> int:  # noqa: N802, B008
        return 0 if parent.isValid() else len(self.rows)

    def roleNames(self) -> dict:  # noqa: N802
        return {Qt.ItemDataRole.UserRole + n: name.encode() for n, name in enumerate(self.ROLES)}

    def data(self, index, role):
        if not index.isValid() or not 0 <= index.row() < len(self.rows):
            return None
        name = self.ROLES[role - Qt.ItemDataRole.UserRole]
        row = self.rows[index.row()]
        if name == "thumb":  # the file itself, which Qt reads; nothing until it has been made
            return self.address(row["thumb"]) if row["thumb"] in self.ready else ""
        return bool(row["pair"]) if name == "pair" else row[name]

    def show(self, rows: list[dict]) -> None:
        self.beginResetModel()
        self.rows, self.named, self.pathed = rows, {}, {}
        for at, row in enumerate(rows):
            self.named.setdefault(row["thumb"], []).append(at)
            self.pathed[row["path"]] = at
        self.ready = {f.stem for f in self.cache.glob("*.jpg")} if self.cache.is_dir() else set()
        self.endResetModel()

    def touched(self, places: list[int]) -> None:
        for at in places:
            self.dataChanged.emit(self.index(at), self.index(at))


class Library(QObject):
    """The library as the interface sees it: the folders, the places to look (all, a folder,
    a month, a camera, the edited ones), the filter, and the photos that pass both, in `model`.
    Scanning and thumbnail making run on threads of their own, with a catalog connection of
    their own; the interface is told when there is news. And only while the library is on
    show: while a photo is being edited it rests (`rest`), so that nothing of it takes time
    from the editing (the owner, 2026-11-17)."""

    changed = Signal()
    scanned = Signal(bool)  # from the scanning thread: the catalog has more photos; and: done
    made = Signal(str, bool)  # from a thumbnail thread: that one is done, and whether it is there
    thumbsChanged = Signal()  # there is another thumbnail (the filmstrip asks again)
    thumbTaken = Signal()  # a render asked for by `grabThumb` is back
    kept = Signal(str)  # from a thumbnail thread: that thumbnail has been written anew
    # Thumbnails being made at one time. Measured on 16 threads of CPU while scrolling at 240
    # frames a second: four made 120 a second, six 170, eight 230; with eight, one frame in
    # twenty came late (4.8 ms), with six none more than with four.
    MAKERS = min(6, max(4, (os.cpu_count() or 4) // 2))
    # The filter at rest. `raw`: only raw files are on show, and counted in the side list
    # (the owner's wish: finished pictures, JPEG, PNG or TIFF, are in the way of developing).
    NO_FILTER = {"pick": False, "rejected": False, "stars": 0, "label": 0, "raw": True}

    def __init__(self, catalog: Catalog | None, cache: Path | None = None,
                 settings=None) -> None:
        """`settings` (a QSettings) remembers whether only raw files are shown, which place
        was on show and which photo was last looked at (`last`): the program starts there."""
        super().__init__()
        self.catalog, self.cache, self.settings = catalog, cache or thumbs(), settings
        if cache is None:
            self._tidy()
        self.all: list[dict] = []
        self._where, self._filter, self._busy = "all", dict(self.NO_FILTER), False
        self.last, self.lasts = "", {}  # (`lasts`: the photo last looked at in each place)
        if settings:
            self._filter["raw"] = settings.value("library/raw_only", True, type=bool)
            self.last = settings.value("library/photo", "", type=str)
            self.lasts = lasts_in(settings)
            self._look(settings.value("library/where", "all", type=str))
        self.model = PhotoModel(self, self.cache)
        # Thumbnails are made here, on threads of Python's own, and Qt only ever reads the
        # finished files: nothing of ours runs on Qt's image-loading thread (PLAN.md 4.17).
        self.makers = ThreadPoolExecutor(self.MAKERS, "thumb")
        self.asked: set[str] = set()
        # Those asked for and not begun, by name; the next to be made is the last.
        self.waiting: OrderedDict[str, dict] = OrderedDict()
        self.making, self._resting, self._stale = 0, False, False
        # For the filmstrip: thumbnails it wants, which are made also while the library rests,
        # one at a time; and photos it shows that the library does not have, by their paths.
        self.strip: set[str] = set()
        self.loose: dict[str, dict | None] = {}
        self.made.connect(self._made)
        self.kept.connect(self._kept)
        self.scanned.connect(lambda done: self._news(scanning=not done))
        self._news(scanning=False)

    def _tidy(self) -> None:
        """Of the cache folder that is the program's own: thumbnails as they were made before
        (see `thumbs`, `forget_starts`) go."""
        old = thumbs().with_name("thumbs")
        if old.is_dir():
            threading.Thread(target=shutil.rmtree, args=(old, True), daemon=True).start()
        if self.catalog:
            forget_starts(self.cache, self.catalog.photos())

    # ---- what there is --------------------------------------------------------------------

    def _news(self, scanning: bool | None = None) -> None:
        """Read the photos from the catalog again and show those the place and filter let by."""
        if scanning is not None:
            self._busy = scanning
        self.all = self.catalog.photos() if self.catalog else []
        for photo in self.all:
            photo["thumb"] = thumb_name(photo["key"])
        self._show()
        if scanning is False:  # a scan is over: the thumbnails there are not yet, in the background
            for photo in reversed(self.model.rows):
                if photo["thumb"] not in self.model.ready:
                    self._ask(photo, soon=False)

    def _passes(self, photo: dict) -> bool:
        kind, _, which = self._where.partition(":")
        month = time.strftime("%Y-%m", time.localtime(photo["taken"] or 0))
        placed = {"all": True, "edited": photo["edited"], "month": month == which,
                  "folder": within(photo["path"], which),
                  "camera": (photo["camera"] or "Unknown") == which}[kind]
        f = self._filter
        return bool(placed and photo["stars"] >= f["stars"]
                    and (not f["raw"] or photo["kind"] == "raw")
                    and (not f["pick"] or photo["flag"] == 1)
                    and (not f["rejected"] or photo["flag"] == -1)
                    and (not f["label"] or photo["label"] == f["label"]))

    def _show(self) -> None:
        self.model.show([p for p in self.all if self._passes(p)])
        self.changed.emit()

    @Property(QObject, constant=True)
    def photos(self) -> PhotoModel:
        return self.model

    @Property(int, notify=changed)
    def count(self) -> int:
        """How many photos are on show; `total`: how many the library has."""
        return len(self.model.rows)

    @Property(int, notify=changed)
    def total(self) -> int:
        return len(self.all)

    @Property(bool, notify=changed)
    def busy(self) -> bool:
        """Folders are being scanned."""
        return self._busy

    @Property("QVariantMap", notify=changed)
    def places(self) -> dict:
        """The side list: `folders`, `months` (newest first) and `cameras`, each an id (what
        `show` takes), a name and how many photos; and how many there are in `all` and how
        many are `edited`. Counted are the kinds on show: raw files only, or every picture."""
        there = [p for p in self.all if not self._filter["raw"] or p["kind"] == "raw"]

        def tally(of) -> dict:
            found: dict = {}
            for photo in there:
                found[of(photo)] = found.get(of(photo), 0) + 1
            return found

        months = tally(lambda p: time.strftime("%Y-%m", time.localtime(p["taken"] or 0)))
        cameras = tally(lambda p: p["camera"] or "Unknown")
        def count(folder: str) -> int:
            return sum(1 for p in there if within(p["path"], folder))

        folders = self.catalog.folders() if self.catalog else []
        return {
            "folders": [{"id": f"folder:{f}", "name": Path(f).name or f, "path": f,
                         "there": Path(f).is_dir(), "count": count(f)} for f in folders],
            "months": [{"id": f"month:{m}", "count": n, "name": f"{MONTHS[int(m[5:]) - 1]} {m[:4]}"}
                       for m, n in sorted(months.items(), reverse=True)],
            # (Those without a camera's name last, whatever their number, as "Other".)
            "cameras": [{"id": f"camera:{c}", "name": "Other" if c == "Unknown" else camera_name(c),
                         "count": n}
                        for c, n in sorted(cameras.items(),
                                           key=lambda item: (item[0] == "Unknown", -item[1]))],
            "all": len(there), "edited": sum(1 for p in there if p["edited"])}

    @Property(str, notify=changed)
    def where(self) -> str:
        return self._where

    def _look(self, where: str) -> bool:
        """Make that place the one on show, and remember it: "all", "edited", or an id from
        `places`. Not a folder that is no longer in the library."""
        kind, _, which = where.partition(":")
        known = kind in ("all", "edited", "month", "camera") or (
            kind == "folder" and bool(self.catalog) and which in self.catalog.folders())
        if known:
            self._where = where
            if self.settings:
                self.settings.setValue("library/where", where)
        return known

    @Slot(str)
    def show(self, where: str) -> None:
        """Look at one place: "all", "edited", or an id from `places`."""
        if self._look(where):
            self._show()

    @Slot(str)
    def lookingAt(self, path: str) -> None:  # noqa: N802
        """That photo is the one selected here or open in Edit: where the program starts
        next time (the owner: "i want the same folder and photo selected")."""
        if path and path in self.model.pathed:
            self.lasts[self._where] = path
        if path and self.settings:
            self.settings.setValue("library/photo", path)
            self.settings.setValue("library/photos", json.dumps(self.lasts))

    @Slot(result=int)
    def rowLast(self) -> int:  # noqa: N802
        """The row of the photo last looked at in the place on show (the owner: "switching
        between folders, it should remember which photo i had opened in each folder last
        time (also persisting across restarts)"); -1 if none, or it is no longer there."""
        return self.model.pathed.get(self.lasts.get(self._where, ""), -1)

    @Slot(int)
    def lookAt(self, row: int) -> None:  # noqa: N802
        if 0 <= row < len(self.model.rows):
            self.lookingAt(self.model.rows[row]["path"])

    @Slot(str, result=int)
    def rowOf(self, path: str) -> int:  # noqa: N802
        """Which row of what is on show that photo is; -1 if it is not among them."""
        return self.model.pathed.get(path, -1)

    @Property(str, constant=True)
    def lastPhoto(self) -> str:  # noqa: N802
        return self.last

    @Property("QVariantMap", notify=changed)
    def filter(self) -> dict:
        """`pick`: only picked; `rejected`: only rejected; `stars`: at least so many; `label`:
        only that one (0: any); `raw`: only raw files (and that is remembered)."""
        return self._filter

    @Slot(str, "QVariant")
    def setFilter(self, key: str, value) -> None:  # noqa: N802
        if key in self._filter and type(value) is type(self._filter[key]):
            self._filter = {**self._filter, key: value}
            if key == "raw" and self.settings:
                self.settings.setValue("library/raw_only", value)
            self._show()

    # ---- folders ---------------------------------------------------------------------------

    @Slot("QVariant")
    def addFolder(self, folder) -> None:  # noqa: N802
        """Add a folder to the library (by reference: nothing is copied or moved), look at it
        (the owner: a folder just added is the one wanted on show) and scan it."""
        path = Path(folder.toLocalFile() if isinstance(folder, QUrl) else str(folder))
        if self.catalog and path.is_dir():
            self.catalog.add_folder(path.resolve())
            self._look(f"folder:{path.resolve()}")
            self._show()
            self.rescan()

    @Slot(str)
    def removeFolder(self, folder: str) -> None:  # noqa: N802
        """Take a folder out of the library. Its photos stay where they are, and their marks
        and edits are there again if it is added back."""
        if self.catalog:
            self.catalog.remove_folder(Path(folder))
            if self._where == f"folder:{folder}":
                self._look("all")
            self._news()

    @Slot(str)
    def reveal(self, path: str) -> None:
        """Show a folder in the desktop's file manager; or a file, in its folder and chosen
        there (the owner: "open the folder *and highlight* the file"). That is asked of the
        file manager over D-Bus (org.freedesktop.FileManager1, which Dolphin, Nautilus, Nemo
        and Thunar answer); where none answers, the folder is opened as it is."""
        where = Path(path)
        if sys.platform == "win32" and where.is_file():
            subprocess.Popen(f'explorer /select,"{where}"')  # (Explorer's own way of it)
            return
        if where.is_file():
            call = QDBusMessage.createMethodCall(
                "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                "org.freedesktop.FileManager1", "ShowItems")
            encoded = QUrl.ComponentFormattingOption.FullyEncoded
            address = QUrl.fromLocalFile(str(where)).toString(encoded)
            call.setArguments([[address], ""])
            if QDBusConnection.sessionBus().call(call, timeout=3000).type() \
                    == QDBusMessage.MessageType.ReplyMessage:
                return
            where = where.parent
        if where.is_dir():
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(where)))

    @Slot()
    def refresh(self) -> None:
        """Read the catalog again (a photo may have got an edit meanwhile)."""
        self._news()

    @Slot()
    def rescan(self) -> None:
        """Look through every folder for what is new, changed or gone, on a thread of its own."""
        if not self.catalog or self._busy:
            return
        if self._resting:
            self._stale = True  # when the library is next on show
            return
        self._stale = False
        self._busy = True
        self.changed.emit()
        threading.Thread(target=self._scan, daemon=True, name="scan").start()

    def _scan(self) -> None:
        """On the scanning thread, with a catalog connection of its own."""
        mine = Catalog(self.catalog.path)
        try:
            def some(rows: list[dict]) -> None:  # what was found so far: on show at once
                mine.found(rows)
                self.scanned.emit(False)

            for folder in map(Path, mine.folders()):
                if folder.is_dir():  # a drive that is not there: its photos stay as they are
                    mine.found(*scan(folder, mine.known(folder), some))
        finally:
            mine.close()
            self.scanned.emit(True)

    @Property(bool, notify=changed)
    def resting(self) -> bool:
        return self._resting

    @Slot(bool)
    def rest(self, on: bool) -> None:
        """The library is not on show (`on`), or is again. Resting, it begins no thumbnail
        and no scan: what was asked for waits, and is taken up when it is on show again."""
        self._resting = on
        if not on:
            if self._stale:
                self.rescan()
            self._feed()

    def _ask(self, photo: dict, soon: bool = True) -> None:
        """Have a photo's thumbnail made: next (`soon`: the grid is showing it), or after
        everything else that is waiting."""
        name = photo["thumb"]
        if name in self.waiting and soon:
            self.waiting.move_to_end(name)
        elif name not in self.asked:
            self.asked.add(name)
            self.waiting[name] = photo
            self.waiting.move_to_end(name, last=soon)
        self._feed()

    def _feed(self) -> None:
        """Begin what is waiting: several at a time while the library is on show; resting, only
        what the filmstrip wants, and one at a time (the editing comes first)."""
        while self.waiting and self.making < (1 if self._resting else self.MAKERS):
            name = next((n for n in reversed(self.waiting)
                         if not self._resting or n in self.strip), None)
            if name is None:
                break
            photo = self.waiting.pop(name)
            self.making += 1
            self.makers.submit(self._make, photo, name)

    @Property(int, notify=thumbsChanged)
    def thumbs(self) -> int:
        """How many thumbnails there are: another number when one has been made."""
        return len(self.model.ready)

    @Slot(str, result=str)
    def thumbFor(self, path: str) -> str:  # noqa: N802
        """A photo's thumbnail for the filmstrip: the address of its file, or nothing while
        it is not made yet (it is asked for by this, also while the library rests)."""
        at = self.model.pathed.get(path)
        photo = self.model.rows[at] if at is not None else self._loose(path)
        if photo is None:
            return ""
        if photo["thumb"] in self.model.ready:
            return self.model.address(photo["thumb"])
        self.strip.add(photo["thumb"])
        self._ask(photo)
        return ""

    @Slot(str, QImage)
    def keep(self, path: str, image: QImage) -> None:
        """The open photo as it is edited, rendered by the interface, becomes its thumbnail:
        in the library's grid and in the filmstrip a photo looks as it has been left."""
        at = self.model.pathed.get(path)
        photo = self.model.rows[at] if at is not None else self._loose(path)
        if photo and not image.isNull():
            self.asked.add(photo["thumb"])
            with contextlib.suppress(RuntimeError):  # (shut down)
                self.makers.submit(self._keep, image.copy(), photo["thumb"])

    @Slot(QQuickItem, str, result=bool)
    def grabThumb(self, item, path: str) -> bool:  # noqa: N802
        """Take a render of that item, to be the thumbnail of the photo at `path`;
        `thumbTaken` says when it is back, and `keepTaken` then keeps it or lets it go.
        (Asked for here, not by the interface's script: app.Session.grabScope says why.)"""
        grab = item.grabToImage()
        if grab is None:
            return False
        self._grab = (grab, path)
        grab.ready.connect(self.thumbTaken)
        return True

    @Slot(bool)
    def keepTaken(self, keep: bool) -> None:  # noqa: N802
        taken, self._grab = getattr(self, "_grab", None), None
        if taken and keep:
            self.keep(taken[1], taken[0].image())

    @Slot(str, bool)
    def setEdited(self, path: str, edited: bool) -> None:  # noqa: N802
        """The open photo has an edit now, or none: its mark in the grid and the filmstrip
        says so at once, not when the catalog is next read."""
        at = self.model.pathed.get(path)
        if at is not None and self.model.rows[at]["edited"] != edited:
            self.model.rows[at]["edited"] = edited
            self.model.touched([at])
            self.changed.emit()

    @Slot("QVariantList")
    def resetEdits(self, paths: list) -> None:  # noqa: N802
        """Take these photos' edits away and show them as they are without: their checkpoints
        stay, and once a photo is open the reset is a step that undo takes back. (Not how the
        photo open in Edit is reset: that is the session's to do, see Main.qml.)"""
        if not self.catalog:
            return
        for path in paths:
            at = self.model.pathed.get(path)
            photo = self.model.rows[at] if at is not None else self._loose(path)
            if photo:
                self._reset(photo)
        self._news()
        self.thumbsChanged.emit()

    def _reset(self, photo: dict) -> None:
        key, file, name = photo["key"], Path(photo["path"]), photo["thumb"]
        was = self.catalog.load(key, file)
        if was:
            states, at = self.catalog.steps(key) or ([was], 0)
            states = [*states[:at + 1], {}][-edit.History.KEPT:]
            self.catalog.save(key, file, {}, self.catalog.checkpoints(key))
            self.catalog.save_steps(key, states, len(states) - 1)
        # Its thumbnail showed the edit: made anew from the photo itself.
        (self.cache / f"{name}.jpg").unlink(missing_ok=True)
        self.model.ready.discard(name)
        self.asked.discard(name)
        self.model.versions[name] = self.model.versions.get(name, 0) + 1
        self._ask(photo)

    def _keep(self, image: QImage, name: str) -> None:
        """On a thumbnail thread: written whole or not at all, like any thumbnail."""
        out = self.cache / f"{name}.jpg"
        part = out.with_name(f"{name}.{threading.get_ident()}.part")
        out.parent.mkdir(parents=True, exist_ok=True)
        if image.convertToFormat(QImage.Format.Format_RGB888).save(str(part), "JPEG", 85):
            os.replace(part, out)
            self.kept.emit(name)

    def _kept(self, name: str) -> None:
        self.model.versions[name] = self.model.versions.get(name, 0) + 1
        self.model.ready.add(name)
        self.model.touched(self.model.named.get(name, []))
        self.thumbsChanged.emit()

    def _loose(self, path: str) -> dict | None:
        """A photo that is open but not in the library (given on the command line, dropped
        on the window): what its thumbnail goes by. None for a file that cannot be read."""
        if path not in self.loose:
            key = identify(Path(path)) if path else None
            self.loose[path] = key and {"key": key, "path": path, "thumb": thumb_name(key)}
        return self.loose[path]

    def _make(self, photo: dict, name: str) -> None:
        """On a thumbnail thread. One that cannot be made (a file that is no picture) stays
        an empty cell."""
        done = False
        with contextlib.suppress(decode.Unreadable, OSError):
            thumbnail(Path(photo["path"]), photo["key"], self.cache)
            done = True
        self.made.emit(name, done)

    def _made(self, name: str, done: bool) -> None:
        """On the interface's thread: the cell of that photo can show its thumbnail, and the
        next one waiting is begun."""
        self.making -= 1
        self.strip.discard(name)
        if done:
            self.model.ready.add(name)
            self.model.touched(self.model.named.get(name, []))
            self.thumbsChanged.emit()
        self._feed()

    def close(self) -> None:
        """At exit: thumbnails still waiting to be made are let go (they are made when next
        wanted), or the program would stay until the last of thousands is done."""
        self.makers.shutdown(wait=False, cancel_futures=True)

    @Slot(int)
    def want(self, row: int) -> None:
        """The grid is showing a photo whose thumbnail is not there yet: make it next."""
        if 0 <= row < len(self.model.rows):
            self._ask(self.model.rows[row])

    # ---- the photos on show ----------------------------------------------------------------

    @Slot("QVariantList", str, int)
    def mark(self, rows: list, what: str, value: int) -> None:
        """Mark the photos at these rows of the grid: `what` is flag, stars or label. Asked
        for what they all have already, it takes the mark away, as the keys of a camera do."""
        chosen = [self.model.rows[int(r)] for r in rows if 0 <= int(r) < len(self.model.rows)]
        if not (self.catalog and chosen and what in MARKS):
            return
        if all(photo[what] == value for photo in chosen):
            value = 0
        self.catalog.mark([photo["key"] for photo in chosen], what, value)
        for photo in chosen:
            photo[what] = value
        self.model.touched([int(r) for r in rows])
        self.changed.emit()

    @Slot(str, str, int)
    def markPhoto(self, path: str, what: str, value: int) -> None:  # noqa: N802
        """The same for one photo by its path: the one open in Edit."""
        self.mark([self.model.pathed[path]] if path in self.model.pathed else [], what, value)

    @Slot(str, result="QVariantMap")
    def marksOf(self, path: str) -> dict:  # noqa: N802
        """A photo's marks by its path, and whether it is `edited`; empty if it is not on show."""
        at = self.model.pathed.get(path)
        return {} if at is None else {what: self.model.rows[at][what]
                                      for what in (*MARKS, "edited")}

    @Slot(result="QVariantList")
    def paths(self) -> list:
        """The photos on show, in order: what Edit steps through."""
        return [photo["path"] for photo in self.model.rows]
