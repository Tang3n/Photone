"""Presets: looks kept by name, to lay on any photo. One JSON file beside the catalog."""

import json
import os
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot

from photone import edit

KEPT = 200  # presets one file holds
NAME = 60   # letters of a preset's name


def clean(found) -> list[dict]:
    """Presets read from somewhere untrusted (the file may have been written by hand, or by
    a later version): each a name, the parts it carries and its look, cleaned; what is not
    that is left out."""
    out = []
    for given in found if isinstance(found, list) else []:
        if not isinstance(given, dict) or not isinstance(given.get("name"), str):
            continue
        name = " ".join(given["name"].split())[:NAME]
        parts = [part for part in edit.PARTS if part in (given.get("parts") or [])]
        if name and parts:
            out.append({"name": name, "parts": parts,
                        "look": edit.look_of(given.get("look"), parts)})
    return out[:KEPT]


class Presets(QObject):
    """The presets, as the interface lists and changes them. `path`: the file they are kept
    in; none (the checks): they last as long as the program."""

    changed = Signal()

    def __init__(self, path: Path | None = None) -> None:
        super().__init__()
        self.path, self._all, self.error = path, [], ""
        # (They were called recipes for a day, and kept in a file of that name: read from
        # there until this one has been written.)
        old = path.with_name("recipes.json") if path else None
        found = path if path and path.exists() else old if old and old.exists() else None
        try:
            if found:
                self._all = clean(json.loads(found.read_text("utf-8")))
        except (OSError, ValueError) as trouble:
            self.error = f"The presets could not be read: {trouble}"

    @Property("QVariantList", notify=changed)
    def all(self) -> list:
        return self._all

    def _write(self) -> None:
        self.changed.emit()
        if not self.path:
            return
        try:  # (whole or not at all: the file is never left half written)
            self.path.parent.mkdir(parents=True, exist_ok=True)
            part = self.path.with_name(self.path.name + ".part")
            part.write_text(json.dumps(self._all, indent=1), "utf-8")
            os.replace(part, self.path)
        except OSError as trouble:
            self.error = f"The presets could not be written: {trouble}"

    @Slot(str, "QVariantMap", "QVariantList", result=bool)
    def save(self, name: str, values: dict, parts: list) -> bool:
        """Keep the look of that edit, those parts of it, under that name. False: no name,
        no part, a name that is taken (`taken` asks beforehand), or the file is full."""
        made = clean([{"name": name, "parts": parts, "look": values}])
        if not made or self.taken(made[0]["name"]) or len(self._all) >= KEPT:
            return False
        self._all = [*self._all, made[0]]
        self._write()
        return True

    @Slot(str, result=bool)
    def taken(self, name: str) -> bool:
        """Whether a preset of that name is there (as names are kept: spaces made one)."""
        name = " ".join(name.split())[:NAME]
        return any(preset["name"] == name for preset in self._all)

    @Slot(int, str)
    def rename(self, at: int, name: str) -> None:
        name = " ".join(name.split())[:NAME]
        if 0 <= at < len(self._all) and name and not self.taken(name):
            self._all = [*self._all[:at], {**self._all[at], "name": name}, *self._all[at + 1:]]
            self._write()

    @Slot(int)
    def remove(self, at: int) -> None:
        if 0 <= at < len(self._all):
            self._all = [*self._all[:at], *self._all[at + 1:]]
            self._write()
