"""Where edits are kept: one SQLite file, never beside a photo (PLAN.md, safety rule 1).

One row per photo, the edit as JSON. A photo is known by what it is, not by where it lies or
what it is called (`identify`): its edit follows it when it is renamed or moved, and a copy of
it is a photo of its own. Every write is its own transaction, so the file is never left
half-written; a catalog made by a newer Photone is not opened at all rather than guessed at.

The library is here too (photone/library.py fills it): the folders that were added, and one
row per photo found in them, with what the user has marked it (flag, stars, label). Those
marks are kept by the same identity, so they follow a photo as its edit does.
"""

from __future__ import annotations

import ctypes
import hashlib
import json
import math
import os
import shutil
import sqlite3
import time
from pathlib import Path

from photone import edit

# 2: the library's tables (folders, photos). 3: an edit that names no Exposure takes the
# camera's exposure compensation back; edits kept before, where none meant 0, say so now.
# 4: it takes it back only as far as the picture has room; 5: it starts by the picture alone
# (edit.exposure_of). Each time, edits kept under the version before that named no Exposure
# say what they had (`Catalog._keep_exposure`).
VERSION = 5
PIECE = 64 * 1024
# What a photo can be marked, and how far: rejected to picked, no stars to five, no label to
# the fifth color.
MARKS = {"flag": (-1, 1), "stars": (0, 5), "label": (0, 5)}
LIBRARY = """
CREATE TABLE IF NOT EXISTS folders (path TEXT PRIMARY KEY, added REAL NOT NULL);
-- A photo's undo and redo, kept from one opening of it to the next (edit.History.kept).
CREATE TABLE IF NOT EXISTS steps (key TEXT PRIMARY KEY, states TEXT NOT NULL, at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS photos (
    key TEXT PRIMARY KEY, path TEXT NOT NULL, folder TEXT NOT NULL, name TEXT NOT NULL,
    -- size, changed: of the file when it was scanned; unchanged, it is skipped next time
    size INTEGER NOT NULL, changed REAL NOT NULL,
    taken REAL, camera TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL, pair TEXT,
    flag INTEGER NOT NULL DEFAULT 0, stars INTEGER NOT NULL DEFAULT 0,
    label INTEGER NOT NULL DEFAULT 0,
    -- gone: no longer found where it was; the row is kept for its marks
    gone INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS photos_path ON photos (path);
"""
FIELDS = ("key", "path", "folder", "name", "size", "changed", "taken", "camera", "kind", "pair")


def _taken_back(path: str | None) -> float | None:
    """Where Exposure started under version 3 for the photo at that path: its camera's whole
    exposure compensation taken back, for a raw file; None if the file is not there to ask."""
    from photone import decode
    from photone.library import describe  # (which imports this module)

    if not path or Path(path).suffix.lower() not in decode.RAW:
        return None  # (a finished picture started at 0 then as it does now)
    try:
        return min(5.0, max(-5.0, 0.0 - describe(Path(path))["bias"]))
    except OSError:
        return None


def _start_4(whole: float, light: list[float] | None) -> float:
    """The rule of version 4, kept for the edits made under it: the camera's compensation taken
    back (`whole`) as far as the picture (decode.light_of's figures) had room, at most three
    stops."""
    if not light:
        return 0.0
    room = min(math.log2(0.5 / max(light[1], 1e-4)), math.log2(0.06 / max(light[0], 1e-4)))
    return round(max(0.0, min(whole, room, 3.0)), 2)


def _held_back(path: str | None) -> float | None:
    """Where Exposure started under version 4 for the photo at that path, or None if the file
    is not there to ask. (It reads the sensor's picture: a tenth of a second a file, for the
    few edits that named no Exposure.)"""
    import rawpy

    from photone import decode

    whole = _taken_back(path)
    if whole is None:
        return None
    try:
        with rawpy.imread(path) as raw:
            return _start_4(whole, decode.light_of(raw))
    except (rawpy.LibRawError, OSError):
        return None


class Unusable(Exception):
    """The catalog cannot be used; the message is for the user. Photone runs on without it."""


def content(photo: Path) -> str:
    """A fingerprint of what is in the file: its size and three pieces of it (start, middle,
    end), hashed.

    The start of a raw file holds its capture time, the camera's serial number and maker
    notes; the middle and end are sensor data, different in any two exposures. So no two shots
    share one: over 4,004 photos of the owner's, the only fingerprints shared were of files
    that are byte for byte the same. Reading the whole 38 MB of each is not needed: this takes
    about a millisecond."""
    with photo.open("rb") as file:
        size = file.seek(0, os.SEEK_END)
        digest = hashlib.blake2b(size.to_bytes(8, "little"), digest_size=16)
        for start in (0, max(0, size // 2 - PIECE // 2), max(0, size - PIECE)):
            file.seek(start)
            digest.update(file.read(PIECE))
    return digest.hexdigest()


def born(photo: Path) -> str:
    """When the file itself was made, as the file system keeps it; empty where it keeps none
    (some network shares). Renaming or moving a file on its disk leaves it as it is, copying
    it gives the copy a new one, and nothing a program does to the file's dates changes it."""
    try:
        buf = ctypes.create_string_buffer(256)  # struct statx
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        if libc.statx(-100, os.fsencode(photo), 0, 0x800, buf) == 0 and buf.raw[1] & 0x08:
            seconds = int.from_bytes(buf.raw[80:88], "little", signed=True)
            return f"{seconds * 10**9 + int.from_bytes(buf.raw[88:92], 'little'):x}"
    except (OSError, AttributeError):
        pass  # not Linux, or an old C library
    time_made = getattr(photo.stat(), "st_birthtime_ns", None)  # macOS, Windows, BSD
    return f"{time_made:x}" if time_made else ""


def identify(photo: Path) -> str | None:
    """Which photo this is: its content and when the file was made, or None when it cannot be
    read. The same after a rename or a move on its disk; different for a copy, which is a
    photo of its own (the owner's rule). A move to another disk makes a new file too: `load`
    recognizes that case by the old one being gone."""
    try:
        return f"c1:{content(photo)}:{born(photo)}"  # c1: this scheme, should it ever change
    except OSError:
        return None


def default_path() -> Path:
    data = Path(os.environ.get("XDG_DATA_HOME") or os.environ.get("LOCALAPPDATA")  # (Windows)
                or Path.home() / ".local/share")
    return data / "photone" / "catalog.db"


class Catalog:
    def __init__(self, path: Path) -> None:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            self.path = path
            self.db = sqlite3.connect(path)
            found = self.db.execute("PRAGMA user_version").fetchone()[0]
            if found > VERSION:
                raise Unusable(f"{path.name} was made by a newer Photone; edits will not be saved")
            if 0 < found < VERSION:  # about to be changed for good: keep it as it was (rule 5)
                self.db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                shutil.copy2(path, path.with_name(f"{path.name}.v{found}"))
            with self.db:
                self.db.execute("PRAGMA journal_mode=WAL")
                # path: where the photo was last seen; NULL once its edit has gone along with
                # a file that turned up elsewhere (see `load`).
                self.db.execute("CREATE TABLE IF NOT EXISTS edits (key TEXT PRIMARY KEY, "
                                "content TEXT NOT NULL, path TEXT, edit TEXT NOT NULL, "
                                "saved REAL NOT NULL, checkpoints TEXT NOT NULL DEFAULT '[]')")
                if "checkpoints" not in {c[1] for c in self.db.execute("PRAGMA table_info(edits)")}:
                    self.db.execute(  # a catalog from the few hours before checkpoints
                        "ALTER TABLE edits ADD COLUMN checkpoints TEXT NOT NULL DEFAULT '[]'")
                self.db.execute("CREATE INDEX IF NOT EXISTS same_content ON edits (content)")
                self.db.executescript(LIBRARY)
                if 0 < found < VERSION:  # (where Exposure started then: 0 before version 3)
                    self._keep_exposure({3: _taken_back, 4: _held_back}.get(found, lambda at: 0.0))
                self.db.execute(f"PRAGMA user_version={VERSION}")
        except (sqlite3.Error, OSError) as e:
            raise Unusable(f"the catalog cannot be opened ({e}); edits will not be saved") from e

    def _keep_exposure(self, start) -> None:
        """Edits and checkpoints name no Exposure while it is where a photo starts, and where
        that is has changed three times: 0 before version 3; the camera's whole exposure
        compensation taken back in version 3; as far as the picture had room for it in
        version 4; by the picture alone since (edit.exposure_of). So that no photo looks other
        than it was left, an edit kept under an older rule has its Exposure written out as
        what it was then: `start(path)`, or nothing if that cannot be known any more. (A photo
        with no edit at all is left so: it takes the new start like any untouched photo.)"""
        rows = self.db.execute("SELECT key, path, edit, checkpoints FROM edits").fetchall()
        for key, path, stored, points in rows:
            was = start(path)

            def as_it_was(values, was=was) -> dict:
                known = not isinstance(values, dict) or "exposure" in values or was is None
                return values if known else {**values, "exposure": was}

            try:
                values = json.loads(stored)
                kept = json.dumps(as_it_was(values) if values else values)
                marks = json.dumps([{**point, "edit": as_it_was(point.get("edit", {}))}
                                    for point in json.loads(points)])
            except (ValueError, TypeError, AttributeError):
                continue  # not what was written there: `load` will not read it either
            self.db.execute("UPDATE edits SET edit = ?, checkpoints = ? WHERE key = ?",
                            (kept, marks, key))

    def load(self, key: str | None, photo: Path) -> dict:
        """The photo's edit; empty when it has none or what is stored cannot be read."""
        if key is None:
            return {}
        try:
            row = self.db.execute("SELECT edit, path FROM edits WHERE key = ?", (key,)).fetchone()
            if row and row[1] != str(photo):  # renamed or moved since: note where it is now,
                with self.db:                 # or a copy made next would pass for the photo
                    self.db.execute("UPDATE edits SET path = ? WHERE key = ?", (str(photo), key))
            stored = row[0] if row else self._moved_here(key, photo)
            return edit.clean(json.loads(stored)) if stored else {}
        except (sqlite3.Error, ValueError):
            return {}

    def checkpoints(self, key: str | None) -> list[dict]:
        """The photo's checkpoints. Ask after `load`, which may just have brought them along."""
        try:
            row = self.db.execute("SELECT checkpoints FROM edits WHERE key = ?", (key,)).fetchone()
            return edit.clean_checkpoints(json.loads(row[0])) if row else []
        except (sqlite3.Error, ValueError):
            return []

    def _moved_here(self, key: str, photo: Path) -> str | None:
        """A photo not known as this file, but known by its content as another: if that other
        file is no longer where it was, this is it, moved to another disk or put back from a
        backup, and its edit comes along. If it is still there, this is a copy and starts
        with no edit.

        The old row is kept, without its path so that it is handed on only once: should the
        old file come back after all (a drive that was unplugged), its edit is still its own."""
        same = self.db.execute(
            "SELECT key, path, edit, checkpoints FROM edits WHERE content = ? AND key != ? "
            "AND path NOT NULL ORDER BY saved DESC", (key.split(":")[1], key)).fetchall()
        for was, path, stored, points in same:
            if identify(Path(path)) != was:
                with self.db:
                    self.db.execute("UPDATE edits SET path = NULL WHERE key = ?", (was,))
                    self.db.execute("INSERT INTO edits VALUES (?, ?, ?, ?, ?, ?)",
                                    (key, key.split(":")[1], str(photo), stored, time.time(),
                                     points))
                return stored
        return None

    def save(self, key: str | None, photo: Path, values: dict, points: list | tuple = ()) -> None:
        """The photo's edit and its checkpoints, as they are now. A photo with neither keeps no
        row. Raises sqlite3.Error when it cannot be written: the caller tells the user."""
        if key is None:
            return  # a file that cannot be read has no picture to edit
        with self.db:
            if values or points:
                self.db.execute("INSERT OR REPLACE INTO edits VALUES (?, ?, ?, ?, ?, ?)",
                                (key, key.split(":")[1], str(photo), json.dumps(values),
                                 time.time(), json.dumps(list(points))))
            else:
                self.db.execute("DELETE FROM edits WHERE key = ?", (key,))

    def steps(self, key: str | None) -> tuple | None:
        """The photo's undo and redo as they were left: (the states, which one it stood at),
        or None. Whether they still fit the edit is for edit.History to say."""
        try:
            row = self.db.execute("SELECT states, at FROM steps WHERE key = ?", (key,)).fetchone()
            return (json.loads(row[0]), row[1]) if row else None
        except (sqlite3.Error, ValueError):
            return None

    def save_steps(self, key: str | None, states: list[dict], at: int) -> None:
        """Keep them (the owner: "Undo/Redo queue seems to clear when photos are switched..
        maybe the undo/redo could also be persistent on disk in case the program crashes").
        A photo that has only its untouched state keeps none."""
        if key is None:
            return
        with self.db:
            if len(states) > 1:
                self.db.execute("INSERT OR REPLACE INTO steps VALUES (?, ?, ?)",
                                (key, json.dumps(states), at))
            else:
                self.db.execute("DELETE FROM steps WHERE key = ?", (key,))

    # ---- the library ---------------------------------------------------------------------------

    def folders(self) -> list[str]:
        return [row[0] for row in self.db.execute("SELECT path FROM folders ORDER BY path")]

    def add_folder(self, folder: Path) -> None:
        with self.db:
            self.db.execute("INSERT OR IGNORE INTO folders VALUES (?, ?)",
                            (str(folder), time.time()))

    def remove_folder(self, folder: Path) -> None:
        """Out of the library. Its photos' rows stay, marked gone: their marks and edits are
        there again should the folder be added back. Not those that another folder of the
        library holds too (one inside this one, or one this one is inside): they stay. (They
        went with it, and the folders left showed no photos until the next scan.)"""
        with self.db:
            self.db.execute("DELETE FROM folders WHERE path = ?", (str(folder),))
            kept = [_under(Path(other)) for other in self.folders()]
            self.db.execute(
                "UPDATE photos SET gone = 1 WHERE path LIKE ? ESCAPE '!'"
                + " AND path NOT LIKE ? ESCAPE '!'" * len(kept), (_under(folder), *kept))

    def known(self, folder: Path) -> dict[str, tuple[int, float]]:
        """The photos last found under a folder: path to (size, changed), to skip what has
        not changed since."""
        rows = self.db.execute("SELECT path, size, changed FROM photos WHERE gone = 0 AND "
                               "path LIKE ? ESCAPE '!'", (_under(folder),))
        return {path: (size, changed) for path, size, changed in rows}

    def found(self, rows: list[dict], lost: list[str] = ()) -> None:
        """What a scan found (FIELDS each) and no longer found. A photo known already keeps
        its marks; one that turned up elsewhere is the same photo, there now."""
        keep = ", ".join(f"{name} = excluded.{name}" for name in FIELDS[1:])
        with self.db:
            self.db.executemany(
                f"INSERT INTO photos ({', '.join(FIELDS)}) VALUES ({', '.join('?' * len(FIELDS))}) "
                f"ON CONFLICT(key) DO UPDATE SET {keep}, gone = 0",
                [tuple(row[name] for name in FIELDS) for row in rows])
            self.db.executemany("UPDATE photos SET gone = 1 WHERE path = ?", [(p,) for p in lost])

    def photos(self) -> list[dict]:
        """Every photo of the library, newest first, each with its marks and whether it has
        an edit."""
        names = (*FIELDS, *MARKS)
        rows = self.db.execute(
            f"SELECT {', '.join('photos.' + n for n in names)}, edits.key IS NOT NULL FROM photos "
            "LEFT JOIN edits ON edits.key = photos.key AND edits.edit != '{}' WHERE gone = 0 "
            "ORDER BY taken DESC, photos.path")
        return [{**dict(zip(names, row, strict=False)), "edited": bool(row[-1])} for row in rows]

    def mark(self, keys: list[str], what: str, value: int) -> None:
        """Flag (-1 rejected, 0 none, 1 picked), stars (0 to 5) or label (0 none, 1 to 5) for
        these photos."""
        low, high = MARKS[what]
        with self.db:
            self.db.executemany(f"UPDATE photos SET {what} = ? WHERE key = ?",
                                [(min(high, max(low, int(value))), key) for key in keys])

    def close(self) -> None:
        self.db.close()


def _under(folder: Path) -> str:
    """A LIKE pattern for every path under a folder (with ! as the escape character)."""
    text = str(folder).rstrip("/\\")
    for special in "!%_":
        text = text.replace(special, "!" + special)
    return text + os.sep + "%"  # (os.sep: a backslash on Windows, where "/%" found nothing)
