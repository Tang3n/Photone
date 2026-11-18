"""What can be done to a photo, and what the pipeline shader needs to do it.

An edit is a plain dict of the values that differ from DEFAULTS. It is what the catalog keeps,
what undo steps through, and what `uniforms` turns into numbers for ui/pipeline.frag. Nothing
here touches pixels or Qt: it is small arithmetic, done once per change.
"""

from __future__ import annotations

import math
from itertools import pairwise

import numpy as np

# None for the white balance means "as the camera shot it", which differs per photo; and None
# for the exposure "where this photo starts": as shot, or lighter where the picture has room
# (`exposure_of`).
STRAIGHT = [[0.0, 0.0], [1.0, 1.0]]  # the tone curve that changes nothing
DEFAULTS = {"profile": "standard", "temperature": None, "tint": None,
            "exposure": None, "contrast": 0.0, "brightness": 0.0, "highlights": 0.0,
            "midtones": 0.0, "shadows": 0.0, "whites": 0.0, "blacks": 0.0, "curve": STRAIGHT,
            "pins": [],
            "saturation": 100.0, "vibrance": 0.0, "chroma": STRAIGHT, "eq": [],
            "turns": 0.0, "angle": 0.0, "crop": [0.0, 0.0, 1.0, 1.0], "masks": []}
RANGES = {"temperature": (2000.0, 15000.0), "tint": (-150.0, 150.0), "exposure": (-5.0, 5.0),
          "contrast": (-100.0, 100.0), "brightness": (-100.0, 100.0),
          "highlights": (-100.0, 100.0), "midtones": (-100.0, 100.0), "shadows": (-100.0, 100.0),
          "whites": (-100.0, 100.0), "blacks": (-100.0, 100.0), "vibrance": (-100.0, 100.0),
          "saturation": (0.0, 200.0), "turns": (0.0, 3.0), "angle": (-15.0, 15.0)}
# The photo's frame: quarter turns to the right, an angle (degrees) that turns the picture to
# the right inside its frame to straighten it, and the crop, [left, top, right, bottom] of the
# picture as it stands after the turns, 0..1. They are what stays when the original is shown.
FRAME = ("turns", "angle", "crop")
# The tools of the rail and the settings each one owns: what its dot, its reset and its
# "compare" are about.
TOOLS = {"tone": ("profile", "exposure", "contrast", "brightness", "highlights", "midtones",
                  "shadows", "whites", "blacks"),
         "curve": ("curve",), "balance": ("temperature", "tint"), "pins": ("pins", "masks"),
         "saturation": ("saturation", "vibrance"), "eq": ("eq",), "chroma": ("chroma",),
         "crop": FRAME}
POINTS = 16     # of a tone curve: what the shader's three matrices hold
GAP = 0.01      # the least two neighboring curve points are apart, left to right
PINS = 12       # color pins a photo can have: what the shader's nine matrices hold
# A color pin: every color near `from` on the wheel (OKLab a, b) moves as `from` moves to `to`.
# `range` is how far from `from` it reaches, in chroma; `feather` how much of that is a soft
# edge (percent); `light` makes those colors lighter or darker; `variance` gathers their hues
# around the pin's (negative) or spreads them (positive); `low`..`high` is the span of
# lightness it works in. "offset" moves the colors together and can tint a gray; "rotate"
# turns the hue and scales the chroma, so a gray stays gray; "protect" moves nothing and
# keeps the other pins off its colors.
PIN = {"light": 0.0, "range": 0.08, "feather": 70.0, "variance": 0.0, "low": 0.0, "high": 1.0,
       "mode": "offset", "mask": 0}  # mask: which of the photo's masks it is kept to; 0: none
MASKS = 8       # masks a photo can have: what the shader's four matrices hold
# A mask: a part of the picture a pin can be kept to. Places are in the stored picture's own
# 0..1 (so a mask stays on what it covers when the photo is cropped or turned). "radial": an
# ellipse about `at`, one of its axes ending at `to`, the other `ratio` times as long; full
# inside, fading out over the outer `feather` of it. "linear": half at `at`, fading to nothing
# at `to` and to full as far the other way. `invert` swaps inside and outside.
MASK = {"ratio": 1.0, "feather": 0.5, "invert": False}
MASK_RANGES = {"ratio": (0.1, 10.0), "feather": (0.0, 1.0)}
# What a mask changes of the picture inside it, its "edit": for each of these settings an
# amount added to the whole image's (the owner: "masks that ... allow me to change exposure
# and all kinds of basic parameters like if i need to dim, saturate or color-correct a spot").
# A temperature in kelvin, like the whole image's; the rest in their own units.
LOCAL = {"exposure": 5.0, "contrast": 100.0, "brightness": 100.0, "highlights": 100.0,
         "midtones": 100.0, "shadows": 100.0, "whites": 100.0, "blacks": 100.0,
         "temperature": 4000.0, "tint": 150.0, "saturation": 100.0, "vibrance": 100.0}
# And these of a mask's edit are whole things of its own, in place of the whole image's inside
# the mask (two curves cannot be added like two numbers): the tone curve, the chroma curve, the
# color EQ. Until a mask has one, the whole image's holds inside it too.
LOCAL_WHOLE = ("curve", "chroma", "eq")
# "brush": painted by hand, as `strokes`, each a run of places in the stored picture (0..1 both
# ways) painted (or, `erase`, rubbed out) with a round brush: `size` its radius as a share of
# the picture's width, `feather` how much of that radius fades out. `painted` makes the
# strokes a raster, which is what the shader reads (the photo's painted masks in the red,
# green and blue of one texture, hence BRUSHES).
# `off`: the mask does nothing for now (the eye in the list); `name`: the user's own for it.
KINDS = ("radial", "linear", "brush")
BRUSHES = 3     # painted masks a photo can have: one color channel of the raster each
STROKES = 400   # strokes a painted mask keeps
REACH = 2000    # places in one stroke
PAINT = 2048    # the raster's longer side, in pixels
STROKE = {"size": (0.001, 0.5), "feather": (0.0, 1.0)}
PIN_RANGES = {"light": (-0.5, 0.5), "range": (0.01, 0.5), "feather": (0.0, 100.0),
              "variance": (-100.0, 100.0), "low": (0.0, 1.0), "high": (0.0, 1.0)}
MODES = ("offset", "rotate", "protect")
NEUTRAL = 0.02  # a source color with less chroma than this has no hue to turn: it is offset
VIVID = 0.4     # the chroma at the right end of the chroma curve
BANDS = 8       # points a color EQ can have: what the shader's two matrices hold
# A point of the color EQ: around `hue` (degrees on the wheel: 0 red, 90 yellow, 140 green, 260
# blue), colors get `gain` percent of their chroma; in full within half of `width` degrees to
# either side, not at all beyond `width`.
BAND_RANGES = {"hue": (0.0, 360.0), "gain": (0.0, 200.0), "width": (8.0, 120.0)}
BAND = 0.05     # how softly a pin's span of lightness ends

# A profile is the base tone curve from what the sensor measured to a picture: its contrast,
# and how bright it shows a mid gray (which a sensor records at about 1/8 of its white).
# Standard is fitted to the camera's own JPEGs: over twelve Sony A7 IV shots, brightness at
# seven percentiles is within 4.4 levels (of 255) of the camera's; the first guess, (1.3, 0.19),
# was 16.8 off, darker from the midtones up. Other makers' cameras are untested.
PROFILES = {"standard": (1.6, 0.32), "flat": (1.2, 0.26)}
MID = 0.125
MID_FINISHED = 0.18  # the mid gray of a finished picture (JPEG, PNG, TIFF), in linear light

SRGB_TO_XYZ = np.array([[0.4124564, 0.3575761, 0.1804375],
                        [0.2126729, 0.7151522, 0.0721750],
                        [0.0193339, 0.1191920, 0.9503041]])
XYZ_TO_2020 = np.array([[1.7166512, -0.3556708, -0.2533663],
                        [-0.6666844, 1.6164812, 0.0157685],
                        [0.0176399, -0.0427706, 0.9421031]])
IDENTITY = np.eye(3)
# A finished picture has no camera behind it, but its white can be moved all the same: as a
# gain on the eye's three kinds of cone (the Bradford matrix), starting from daylight. To the
# arithmetic below that is a camera like any other, without a sensor that clips.
BRADFORD = np.array([[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367],
                     [0.0389, -0.0685, 1.0296]])
FINISHED = {"wb": (1 / (BRADFORD @ SRGB_TO_XYZ.sum(axis=1))).tolist(),
            "cam_xyz": BRADFORD.tolist(), "sensor": False}


def valid(key: str, value):
    """The value as the edit keeps it, or ValueError. Everything that enters an edit passes
    here: what the interface sends and what a catalog file holds."""
    if key in SHAPES:  # a setting that is more than one number
        return SHAPES[key](value)
    if key not in RANGES:
        raise ValueError(f"no such setting: {key!r}")
    if value is None and DEFAULTS[key] is None:
        return None
    if not _number(value):
        raise ValueError(f"{key} must be a number")
    low, high = RANGES[key]
    return min(high, max(low, float(value)))


def _ranged(key: str, value) -> float:
    if not _number(value):
        raise ValueError(f"{key} must be a number")
    low, high = RANGES[key]
    return min(high, max(low, float(value)))


def valid_profile(value) -> str:
    if value not in PROFILES:
        raise ValueError(f"no such profile: {value!r}")
    return value


def _number(value) -> bool:
    return (not isinstance(value, bool) and isinstance(value, (int, float))
            and math.isfinite(value))


def valid_curve(value) -> list[list[float]]:
    """A tone curve: 2 to POINTS points [in, out] of lightness, 0..1, running left to right.
    Lists, not tuples: it must compare equal to itself after a trip through JSON."""
    if not isinstance(value, (list, tuple)) or not 2 <= len(value) <= POINTS:
        raise ValueError("a curve has 2 to 16 points")
    points = []
    for point in value:
        if not (isinstance(point, (list, tuple)) and len(point) == 2 and all(map(_number, point))):
            raise ValueError("a curve point is two numbers")
        points.append([round(min(1.0, max(0.0, float(v))), 4) for v in point])
    if any(b[0] - a[0] < GAP - 1e-9 for a, b in pairwise(points)):
        raise ValueError("curve points must run left to right")
    return points


def _color(value) -> list[float]:
    """A place on the wheel: OKLab [a, b], each within half a unit of gray."""
    if not (isinstance(value, (list, tuple)) and len(value) == 2 and all(map(_number, value))):
        raise ValueError("a color on the wheel is two numbers")
    return [round(min(0.5, max(-0.5, float(v))), 5) for v in value]


def valid_pins(value) -> list[dict]:
    """Color pins as the edit keeps them: every pin whole, every number in its range. Plain
    lists, dicts and rounded numbers, so that an edit is equal to itself after JSON."""
    if not isinstance(value, (list, tuple)) or len(value) > PINS:
        raise ValueError(f"at most {PINS} pins")
    pins = []
    for given in value:
        if not isinstance(given, dict) or "from" not in given:
            raise ValueError("a pin is a source color and what happens to it")
        pin = {"from": _color(given["from"]), "to": _color(given.get("to", given["from"]))}
        for key, (low, high) in PIN_RANGES.items():
            number = given.get(key, PIN[key])
            if not _number(number):
                raise ValueError(f"a pin's {key} is a number")
            pin[key] = round(min(high, max(low, float(number))), 5)
        pin["mode"], pin["mask"] = given.get("mode", PIN["mode"]), given.get("mask", 0)
        if pin["mode"] not in MODES or pin["high"] - pin["low"] < 0.02:
            raise ValueError("no such kind of pin, or no span of lightness left")
        if isinstance(pin["mask"], bool) or pin["mask"] not in range(MASKS + 1):
            raise ValueError("a pin's mask is one of the photo's masks, or none")
        pin["mask"] = int(pin["mask"])
        pins.append(pin)
    return pins


def _place(point) -> list[float]:
    """A place in the picture (it may lie somewhat outside it: a mask's handle can)."""
    if not (isinstance(point, (list, tuple)) and len(point) == 2 and all(map(_number, point))):
        raise ValueError("a mask's place is two numbers")
    return [round(min(2.0, max(-1.0, float(v))), 5) for v in point]


def valid_masks(value) -> list[dict]:
    """The photo's masks as the edit keeps them."""
    if not isinstance(value, (list, tuple)) or len(value) > MASKS:
        raise ValueError(f"at most {MASKS} masks")
    masks = [_mask(given) for given in value]
    if sum(mask["kind"] == "brush" for mask in masks) > BRUSHES:
        raise ValueError(f"at most {BRUSHES} painted masks")
    return masks


def _mask(given) -> dict:
    if not isinstance(given, dict) or given.get("kind") not in KINDS:
        raise ValueError("a mask is radial, linear or painted")
    if given["kind"] == "brush":
        mask = {"kind": "brush", "strokes": _strokes(given.get("strokes", []))}
    else:
        mask = {"kind": given["kind"], "at": _place(given.get("at")), "to": _place(given.get("to"))}
        if math.dist(mask["at"], mask["to"]) < 0.005:
            raise ValueError("a mask needs some size")
        for key, (low, high) in MASK_RANGES.items():
            mask[key] = _within(given.get(key, MASK[key]), low, high, f"a mask's {key}")
    mask["invert"] = bool(given.get("invert", False))
    local = _local(given.get("edit", {}))
    if local:  # (kept only where there is one: a mask without is as it always was)
        mask["edit"] = local
    if given.get("off"):
        mask["off"] = True
    name = given.get("name", "")
    if isinstance(name, str) and name.strip():
        mask["name"] = name.strip()[:40]
    return mask


def _within(number, low: float, high: float, what: str) -> float:
    if not _number(number):
        raise ValueError(f"{what} is a number")
    return round(min(high, max(low, float(number))), 5)


def _strokes(given) -> list[dict]:
    """A painted mask's strokes as they are kept."""
    if not isinstance(given, (list, tuple)) or len(given) > STROKES:
        raise ValueError(f"at most {STROKES} strokes")
    out = []
    for stroke in given:
        if not isinstance(stroke, dict):
            raise ValueError("a stroke is a brush and the places it went")
        try:
            points = np.asarray(stroke.get("points", []), dtype=float)
        except (TypeError, ValueError):
            raise ValueError("a stroke's places are numbers") from None
        if points.ndim != 2 or points.shape[1] != 2 or not 1 <= len(points) <= REACH \
                or not np.isfinite(points).all():
            raise ValueError("a stroke is one place or more, two numbers each")
        out.append({**{key: _within(stroke.get(key), low, high, f"a brush's {key}")
                       for key, (low, high) in STROKE.items()},
                    "erase": bool(stroke.get("erase", False)),
                    "points": np.round(np.clip(points, -1.0, 2.0), 4).tolist()})
    return out


def raster_size(shape: float) -> tuple[int, int]:
    """How large the raster of a picture's painted masks is: (width, height)."""
    shape = shape or 1.0
    if shape >= 1:
        return PAINT, max(1, round(PAINT / shape))
    return max(1, round(PAINT * shape)), PAINT


class Painter:
    """A painted mask's raster as it is being made: `canvas` (heights by widths, 0..1), and
    what is needed to go on with the stroke under way.

    From each place of a stroke to the next the brush leaves a straight band with round
    ends: every pixel by how far it is from that line, whole within the brush's core and
    fading over its feather. (At first the brush was pressed down every quarter of its
    radius, which showed as scallops along a soft edge; the owner: "a straight line has
    circle artifacts".)

    How bands are put together. Along a stroke, one stretch and the next take the larger of
    the two (or the band would be harder at every joint). But a stroke is cut into pieces
    some brush widths long, and a piece is laid onto all that is older than the piece before
    it as paint onto paint: what is left clear is the product of what each leaves clear. So
    where a soft edge lies over another, of another stroke or of this one coming back, they
    run into one another smoothly. (With the larger of the two everywhere, two soft edges
    met in a crease, and the gaps between passes had hard pointed ends; the owner: "there
    cannot be any sharp patches like that".) Rubbing out is the same with clear for paint.

    ponytail: each stretch costs its bounding box (a brush of 5 %: a millisecond; at its
    largest, a million pixels and some 30 ms), and a mask of hundreds of long strokes takes
    a moment to paint anew when a photo is opened. The upgrade is painting on the GPU."""

    PIECE = 6.0  # a piece of a stroke, in brush radii of the way gone

    def __init__(self, shape: float) -> None:
        wide, high = raster_size(shape)
        self.canvas = np.zeros((high, wide), dtype=np.float32)
        self.under = self.before = self.piece = None

    def begin(self) -> None:
        """A stroke begins: nothing of it is there yet."""
        self.under = self.canvas.copy()          # all but the piece under way
        self.before = np.zeros_like(self.canvas)  # the piece before the one under way
        self.piece = np.zeros_like(self.canvas)   # the one under way
        self.gone, self.reach, self.reached = 0.0, None, None  # (where each of the two pieces is)

    def add(self, stroke: dict, start: int = 0) -> None:
        """Go on with the stroke begun, from its place `start`."""
        high, wide = self.canvas.shape
        radius = max(0.5, stroke["size"] * wide)
        core = 1 - max(stroke["feather"], 1e-4)
        points = np.asarray(stroke["points"][max(0, start - 1):], dtype=float) * (wide, high)
        for a, b in list(zip(points, points[1:], strict=False)) or [(points[0], points[0])]:
            self._stretch(a, b, radius, core, stroke["erase"])
            self.gone += float(np.hypot(*(b - a)))
            if self.gone > self.PIECE * radius:  # the next stretch begins another piece
                self._turn()

    def _turn(self) -> None:
        """The piece under way becomes the one before, and a new one begins. Only where the
        two pieces are is anything moved: whole rasters copied at every piece made a fast
        stroke with a small brush stutter (some twenty megabytes every few frames)."""
        here, there = self.reach, self.reached
        if there:
            self.before[there] = 0
        if here:
            self.under[here] = self.canvas[here]
            self.before[here] = self.piece[here]
            self.piece[here] = 0
        self.reached, self.reach, self.gone = here, None, 0.0

    def _stretch(self, a, b, radius: float, core: float, erase: bool) -> None:
        high, wide = self.canvas.shape
        low = np.floor(np.minimum(a, b) - radius).astype(int)
        top = np.ceil(np.maximum(a, b) + radius).astype(int) + 1
        box = (slice(max(0, low[1]), min(high, top[1])), slice(max(0, low[0]), min(wide, top[0])))
        if box[0].start >= box[0].stop or box[1].start >= box[1].stop:
            return
        was_at = self.reach  # (the piece under way reaches as far as its stretches' boxes)
        self.reach = box if was_at is None else tuple(
            slice(min(old.start, new.start), max(old.stop, new.stop))
            for old, new in zip(was_at, box, strict=True))
        # (A pixel is its middle.) How far each is from the stretch a to b.
        ys, xs = np.mgrid[box] + 0.5
        along = b - a
        long = float(along @ along)
        t = np.clip(((xs - a[0]) * along[0] + (ys - a[1]) * along[1]) / long, 0, 1) if long else 0.0
        far = np.hypot(xs - a[0] - t * along[0], ys - a[1] - t * along[1]) / radius
        np.maximum(self.piece[box], 1 - _step(core, 1.0, far), out=self.piece[box])
        # This piece and the one before it as one (the larger), less what the one before
        # put there already: that much paint, or that much rubbed out, onto what is under.
        was = self.before[box]
        both = np.maximum(self.piece[box], was)
        more = np.where(was < 1, (both - was) / np.maximum(1 - was, 1e-6), 0)
        under = self.under[box]
        self.canvas[box] = under * (1 - more) if erase else 1 - (1 - under) * (1 - more)

    def bytes(self) -> np.ndarray:
        return np.round(self.canvas * 255).astype(np.uint8)


def painted(strokes: list[dict], shape: float) -> np.ndarray:
    """A painted mask as a raster: 0 where it is not, 255 where it is whole."""
    painter = Painter(shape)
    for stroke in strokes:
        painter.begin()
        painter.add(stroke)
    return painter.bytes()


def _local(given) -> dict:
    """A mask's own edit as it is kept: the amounts that are numbers, within their reach,
    and not nothing."""
    if not isinstance(given, dict):
        raise ValueError("a mask's edit is settings and their amounts")
    out = {}
    for key, reach in LOCAL.items():
        amount = given.get(key, 0.0)
        if not _number(amount):
            raise ValueError(f"a mask's {key} is a number")
        amount = round(min(reach, max(-reach, float(amount))), 5)
        if amount:
            out[key] = amount
    for key in LOCAL_WHOLE:
        if key in given:
            out[key] = valid(key, given[key])
    return out


def merged(edit: dict, local: dict, camera: dict | None) -> dict:
    """The edit of the picture inside a mask: the whole image's with the mask's amounts
    added, each kept within what the setting can be. Where the whole image's says nothing
    (the exposure a photo starts with, the white balance as shot), that is what is added to."""
    full, out = {**DEFAULTS, **edit}, dict(edit)
    shot = (camera.get("shot") or as_shot(camera)) if camera else (6500.0, 0.0)
    rest = {"exposure": exposure_of(full, camera), "temperature": shot[0], "tint": shot[1]}
    for key, amount in local.items():
        if key in LOCAL_WHOLE:
            out[key] = amount
            continue
        low, high = RANGES[key]
        base = rest[key] if full[key] is None else full[key]
        out[key] = min(high, max(low, base + amount))
    return out


def layers(edit: dict, camera: dict | None) -> list[tuple[int, dict]]:
    """(mask's number, the edit inside it) for every mask that changes anything: what is
    developed a second time and laid over the picture by the mask's weight."""
    return [(n + 1, merged(edit, mask["edit"], camera))
            for n, mask in enumerate(edit.get("masks", []))
            if mask.get("edit") and not mask.get("off")]


def valid_crop(value) -> list[float]:
    """A crop: [left, top, right, bottom] within the picture, with something left of it."""
    if not (isinstance(value, (list, tuple)) and len(value) == 4 and all(map(_number, value))):
        raise ValueError("a crop is four numbers")
    left, top, right, bottom = (round(min(1.0, max(0.0, float(v))), 5) for v in value)
    if right - left < 0.02 or bottom - top < 0.02:
        raise ValueError("a crop must leave something of the picture")
    return [left, top, right, bottom]


def valid_eq(value) -> list[dict]:
    """The color EQ's points as the edit keeps them: each a hue, a gain and a width."""
    if not isinstance(value, (list, tuple)) or len(value) > BANDS:
        raise ValueError(f"at most {BANDS} points")
    points = []
    for given in value:
        if not isinstance(given, dict) or not all(_number(given.get(key)) for key in BAND_RANGES):
            raise ValueError("a point of the color EQ is a hue, a gain and a width")
        point = {key: round(min(high, max(low, float(given[key]))), 3)
                 for key, (low, high) in BAND_RANGES.items()}
        point["hue"] = round(float(given["hue"]) % 360, 3)  # once round the wheel is the same hue
        points.append(point)
    return points


SHAPES = {"profile": valid_profile, "curve": valid_curve, "chroma": valid_curve,
          "pins": valid_pins, "eq": valid_eq, "crop": valid_crop, "masks": valid_masks,
          "turns": lambda value: float(round(_ranged("turns", value)) % 4)}


def clean(values) -> dict:
    """An edit read from somewhere untrusted: only what is known and valid, and not default."""
    out = {}
    for key, value in (values.items() if isinstance(values, dict) else ()):
        try:
            value = valid(key, value)
        except ValueError:
            continue
        if value != DEFAULTS[key]:
            out[key] = value
    return out


# ---- white balance -----------------------------------------------------------------------

def planck_xy(kelvin: float) -> tuple[float, float]:
    """Where a glowing body of that temperature sits in CIE xy (Kang et al., 1667-25000 K)."""
    t = min(25000.0, max(1667.0, kelvin))
    if t <= 4000:
        x = -0.2661239e9 / t**3 - 0.2343589e6 / t**2 + 0.8776956e3 / t + 0.179910
    else:
        x = -3.0258469e9 / t**3 + 2.1070379e6 / t**2 + 0.2226347e3 / t + 0.240390
    if t <= 2222:
        y = -1.1063814 * x**3 - 1.34811020 * x**2 + 2.18555832 * x - 0.20219683
    elif t <= 4000:
        y = -0.9549476 * x**3 - 1.37418593 * x**2 + 2.09137015 * x - 0.16748867
    else:
        y = 3.0817580 * x**3 - 5.87338670 * x**2 + 3.75112997 * x - 0.37001483
    return x, y


def _uv(x: float, y: float) -> np.ndarray:
    """CIE 1960 uv, where a step across the temperature line is a step of tint."""
    d = -2 * x + 12 * y + 3
    return np.array([4 * x / d, 6 * y / d])


TINT = 3000.0  # tint units per unit of uv: +150 is a strong magenta, as in other raw editors


def white_xyz(kelvin: float, tint: float) -> np.ndarray:
    """The color of light of that temperature and tint, Y = 1. A positive tint is greener
    light, so that raising the tint setting makes the picture more magenta, as raising the
    temperature setting makes it warmer: both name the light to be taken out."""
    here, ahead = _uv(*planck_xy(kelvin)), _uv(*planck_xy(kelvin + 1))
    along = (ahead - here) / np.linalg.norm(ahead - here)
    u, v = here + np.array([along[1], -along[0]]) * (tint / TINT)  # toward green
    x, y = 3 * u / (2 * u - 8 * v + 4), 2 * v / (2 * u - 8 * v + 4)
    return np.array([x / y, 1.0, (1 - x - y) / y])


def light(cam_xyz, neutral) -> tuple[float, float]:
    """The temperature and tint of the light under which the camera saw `neutral` (its three
    channels' answer to something white or gray)."""
    xyz = np.linalg.inv(np.array(cam_xyz)) @ np.array(neutral)
    target = _uv(xyz[0] / xyz.sum(), xyz[1] / xyz.sum())

    def off(mired: float) -> float:
        return float(np.linalg.norm(_uv(*planck_xy(1e6 / mired)) - target))

    mired = min(range(40, 600), key=off)  # coarse, then around the best
    mired = min((mired + step / 20 for step in range(-20, 21)), key=off)
    kelvin = round(1e6 / mired / 10) * 10.0
    here, ahead = _uv(*planck_xy(kelvin)), _uv(*planck_xy(kelvin + 1))
    along = (ahead - here) / np.linalg.norm(ahead - here)
    tint = float(np.dot(target - here, [along[1], -along[0]])) * TINT
    return kelvin, float(round(tint))


# Where a photo's exposure starts (`exposure_of`): raised until the brightest twentieth of the
# picture is at this share of the sensor's white (a gray there is shown at level 238 of 255),
# or until the picture's middle is as light as this (the owner's photos shot as metered have
# theirs at 0.047), and never by more stops than MOST: a picture darker than that is a night,
# and is left one.
TOP_AT, MIDDLE_AT, MOST = 0.5, 0.06, 2.0


def exposure_of(full: dict, camera: dict | None) -> float:
    """The exposure in stops: what the edit says; or, where it says nothing, where the photo
    starts: as much lighter than it was shot as the picture has room for (`light`:
    decode.light_of's two figures), never lower. A photo shot under to keep its highlights
    starts lighter; one that is light already, or has something bright in a twentieth of it,
    starts as shot. By the picture alone, whatever the camera was set to.

    How it came to this, 2026-11-17. First the camera's exposure compensation was taken back
    whole (the owner's wish: "so that its not so dark if i had -2EV on the camera"), which
    was wrong: "that exposure compensation made the photos very overexposed". A compensation
    is the photographer's correction of the meter as often as a habit; of 120 of his photos it
    left 11 % with more than 2 % of the picture cut off at white, where as shot 2 % are. Then
    the compensation was taken back only as far as the picture had room; held back by the
    brightest hundredth, a window in the frame kept a dark room dark ("i cant find any
    photo" that starts lighter), so it is the brightest twentieth: at most 4 % of any picture
    newly near white. Then the owner: "maybe ALL the photos could have their default EV be
    set based on the same rule, independent of metadata?" So the compensation is no longer
    asked. Of 300 photos 84 % start lighter, by 1.3 stops on average before the limit of two
    stops, which is there for the 6 % (night scenes, frames nearly black) that would
    otherwise be raised by three or more. Without the two figures (a sensor that is no Bayer
    mosaic, a finished picture) a photo starts as shot.

    ponytail: an edit that names no Exposure follows this rule, so every change of the rule
    needs the catalog to write out what such edits had (`Catalog._keep_exposure`, three times
    so far, each needing the old rule kept). The upgrade is to keep the start with the edit
    when it is first made."""
    if full["exposure"] is not None:
        return full["exposure"]
    light = (camera or {}).get("light")
    if not light:
        return 0.0
    room = min(math.log2(TOP_AT / max(light[1], 1e-4)), math.log2(MIDDLE_AT / max(light[0], 1e-4)))
    return round(max(0.0, min(room, MOST)), 2)


def sensed(shown, profile: str = "standard"):
    """The light a sensor recorded (a share of its white) where the profile's curve shows
    `shown` (a share of the display's white; a number or an array): the curve read backwards.
    For reading a camera's own finished picture as if it were the sensor's."""
    c, s, k = curve(profile)
    shown = np.clip(shown, 0.0, 1.0)
    return (s * shown / (k - shown)) ** (1 / c)


def as_shot(camera: dict) -> tuple[float, float]:
    """The temperature and tint the camera's own white balance stands for."""
    return light(camera["cam_xyz"], 1 / np.array(camera["wb"]))


def neutral_at(camera: dict, rgb) -> tuple[float, float] | None:
    """The temperature and tint that make this color a gray ("pick neutral"): `rgb` is a pixel
    as decoded, linear Rec.2020. None where the pixel says nothing (a channel at or below
    zero)."""
    seen = np.linalg.inv(camera_matrix(camera)) @ np.array(rgb, dtype=float)
    if seen.min() <= 0:
        return None
    return light(camera["cam_xyz"], seen / np.array(camera["wb"]))


def camera_matrix(camera: dict) -> np.ndarray:
    """From the camera's own colors (white-balanced) to linear Rec.2020, as LibRaw builds it:
    checked against LibRaw's output to five decimals."""
    cam_rgb = np.array(camera["cam_xyz"]) @ SRGB_TO_XYZ
    cam_rgb /= cam_rgb.sum(axis=1, keepdims=True)
    return (XYZ_TO_2020 @ SRGB_TO_XYZ) @ np.linalg.inv(cam_rgb)


def balance(edit: dict, camera: dict | None) -> tuple[np.ndarray, np.ndarray, list[float]]:
    """(to the camera's colors, back from them, [gain r, g, b, ceiling]).

    White balance is a gain on each of the camera's own channels, so the pixels go back there
    for it. The gain is relative to the camera's own white balance, which the decoder already
    applied: at the defaults it is exactly 1."""
    if not camera:
        return IDENTITY, IDENTITY, [1.0, 1.0, 1.0, 1e9]  # no sensor: nothing to cut off
    shot = camera.get("shot") or as_shot(camera)  # the caller may keep it: it is a search
    kelvin = shot[0] if edit.get("temperature") is None else edit["temperature"]
    tint = shot[1] if edit.get("tint") is None else edit["tint"]
    cam_xyz = np.array(camera["cam_xyz"])

    def gains(k: float, t: float) -> np.ndarray:
        g = 1 / (cam_xyz @ white_xyz(k, t))
        return g / g[1]

    gain = gains(kelvin, tint) / gains(*shot)
    out = camera_matrix(camera)
    # ponytail: a channel the sensor clipped stays clipped, so all three are cut at the lowest
    # gain to keep blown highlights neutral (a little gray rather than tinted). The upgrade is
    # rebuilding clipped channels from the others, in the decoder.
    ceiling = float(min(gain.min(), 1.0)) if camera.get("sensor", True) else 1e9
    return np.linalg.inv(out), out, [*map(float, gain), ceiling]


# ---- the base tone curve ------------------------------------------------------------------

def curve(profile: str) -> tuple[float, float, float]:
    """(c, s, k) of y = k * x^c / (x^c + s): mid gray lands where the profile says and the
    sensor's white lands on the display's white."""
    c, mid = PROFILES[profile]
    a = MID ** c
    s = a * (1 - mid) / (mid - a)
    return c, s, 1 + s


def tone_at(x, u: dict):
    """What is shown for neutral light `x` (a share of the sensor's white, as recorded; a
    number or an array), by the shader's numbers `u`, as the shader's `develop` does it with
    the white balance as shot: exposure; contrast, shadows and highlights as gains in stops
    from mid gray; midtones, a gain round mid gray, on what those made; the profile's curve;
    then Blacks and Whites, the two ends of what is shown, mid gray staying put (Blacks takes
    light away below it, most at black, or adds some; Whites is a gain in stops above it,
    most at white); then HDR. In HDR (`hdrLift`, the display's peak less one) what is shown
    climbs on by the square of how light it is, so that the sensor's white lands on the peak:
    all of the picture is deeper, a shadow a little, white by the whole headroom. That is the
    last thing done, after brightness and (in the shader) after the tone curve and the colors'
    tools, which so work on the same picture in HDR as in SDR.

    ponytail: the square is judged on a display with one stop above white (the owner's: 500
    nits white, 1015 peak). With two or three stops the light midtones may rise too fast; the
    upgrade is a power that grows with the peak."""
    shown, gray = np.maximum(np.asarray(x, float), 0) * u["gain"], u["mid"]
    stops = np.log2(np.maximum(shown, 1e-6) / gray)
    shown = shown * 2.0 ** (u["contrast"] * stops + u["shadows"] * (1 - _step(-4.5, 0.5, stops))
                            + u["highlights"] * _step(-0.5, 3.0, stops))
    away = np.abs(np.log2(np.maximum(shown, 1e-6) / gray))
    shown = shown * 2.0 ** (u["midtones"] * (1 - _step(0.5, 2.5, away)))
    if u["curveC"] > 0:
        p, middle = shown ** u["curveC"], u["mid"] ** u["curveC"]
        shown = u["curveK"] * p / (p + u["curveS"])
        gray = u["curveK"] * middle / (middle + u["curveS"])
    shown = np.maximum(shown - u["blacks"] * (1 - _step(0.0, gray, shown)), 0)
    shown = shown * 2.0 ** (u["whites"] * _step(gray, 1.0, shown))
    shown = shown * np.clip(shown, 1e-6, 1.0) ** u["brightness"]
    # (HDR last: in the shader after the colors' tools too.)
    return shown + u["hdrLift"] * np.maximum(shown, 0) ** 2


# ---- the tone curve the user draws -----------------------------------------------------------

def slopes(points: list[list[float]]) -> list[float]:
    """The curve's slope at each point, for a smooth line through them that never swings past
    a point (monotone cubic: between two points it stays between their heights)."""
    rise = [(b[1] - a[1]) / (b[0] - a[0]) for a, b in pairwise(points)]
    wide = [b[0] - a[0] for a, b in pairwise(points)]
    # At a point between two others: the slope of the parabola through the three (each
    # neighbor counting by how near it is), which bends as much on one side of the point as
    # on the other; held to three times the flatter of the two rises, which is as far as it
    # can go without the line swinging past a point, and flat where the line turns back.
    # (It was the harmonic mean of the two rises, which is always nearer the flatter one:
    # the line left a point gently on that side and with a sharp bend on the other; the
    # owner: "on one side, its properly interpolated, but on the other ... a way sharper
    # turn".)
    inner = [0.0 if a * b <= 0 else
             math.copysign(min(abs((a * h1 + b * h0) / (h0 + h1)), 3 * min(abs(a), abs(b))), a)
             for (a, b), (h0, h1) in zip(pairwise(rise), pairwise(wide), strict=True)]
    if not inner:
        return [rise[0], rise[0]]

    def end(rise_here: float, slope_next: float) -> float:  # bends on, never back
        slope = (3 * rise_here - slope_next) / 2
        if slope * rise_here <= 0:
            return 0.0
        return math.copysign(min(abs(slope), 3 * abs(rise_here)), slope)

    return [end(rise[0], inner[0]), *inner, end(rise[-1], inner[-1])]


def curve_at(points, x: float) -> float:
    """The tone curve's output for lightness x. The same arithmetic as ui/pipeline.frag:
    flat outside the end points, a cubic between two neighbors."""
    slope = slopes(points)
    if x <= points[0][0]:
        return points[0][1]
    for ((x0, y0), (x1, y1)), (m0, m1) in zip(pairwise(points), pairwise(slope), strict=True):
        if x <= x1:
            h = x1 - x0
            t = (x - x0) / h
            return ((2 * t**3 - 3 * t**2 + 1) * y0 + (t**3 - 2 * t**2 + t) * h * m0
                    + (-2 * t**3 + 3 * t**2) * y1 + (t**3 - t**2) * h * m1)
    return points[-1][1]


LINE = 257  # heights a curve is drawn from (65 cut the corners of a steep curve: the owner saw)


def curve_line(points) -> list[float]:
    """A curve as LINE heights, left to right, for drawing it: `curve_at` at each, with the
    slopes worked out once."""
    slope, xs = slopes(points), np.linspace(0.0, 1.0, LINE)
    out = np.where(xs <= points[0][0], points[0][1], points[-1][1]).astype(float)
    for ((x0, y0), (x1, y1)), (m0, m1) in zip(pairwise(points), pairwise(slope), strict=True):
        here = (xs > x0) & (xs <= x1)
        h, t = x1 - x0, (xs[here] - x0) / (x1 - x0)
        out[here] = ((2 * t**3 - 3 * t**2 + 1) * y0 + (t**3 - 2 * t**2 + t) * h * m0
                     + (-2 * t**3 + 3 * t**2) * y1 + (t**3 - t**2) * h * m1)
    return out.tolist()


def curve_uniforms(points: list[list[float]]) -> dict:
    """The curve for the shader: POINTS x, y and slopes (the last point repeated to fill)."""
    slope = slopes(points)
    fill = POINTS - len(points)
    return {"curveOn": 0.0 if points == STRAIGHT else 1.0,
            "curveX": [p[0] for p in points] + [points[-1][0]] * fill,
            "curveY": [p[1] for p in points] + [points[-1][1]] * fill,
            "curveM": slope + [0.0] * fill}


# ---- color pins ------------------------------------------------------------------------------

def _turned(color: np.ndarray, angle: float) -> np.ndarray:
    c, s = math.cos(angle), math.sin(angle)
    return np.array([c * color[0] - s * color[1], s * color[0] + c * color[1]])


def _between(angle: float) -> float:
    """An angle as the short way round: within half a turn of zero."""
    return angle - 2 * math.pi * round(angle / (2 * math.pi))


def _step(low: float, high: float, x):
    """GLSL's smoothstep, for a number or an array."""
    t = np.clip((x - low) / (high - low), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def mask_weight(mask: dict, place, shape: float) -> float:
    """How much of a mask a place of the stored picture (0..1 both ways) is in. `shape`: the
    stored picture's width over its height, so that an ellipse is one in pixels."""
    if mask.get("off"):
        return 0.0
    if mask["kind"] == "brush":  # the raster, read between its pixels as the GPU reads it
        canvas = painted(mask["strokes"], shape).astype(float) / 255
        most = np.array(canvas.shape) - 1.001
        y, x = np.clip(np.array(place[::-1]) * canvas.shape - 0.5, 0, most)
        r, c, fy, fx = int(y), int(x), y - int(y), x - int(x)
        weight = float(np.array([1 - fy, fy]) @ canvas[r:r + 2, c:c + 2] @ np.array([1 - fx, fx]))
        return 1 - weight if mask["invert"] else weight
    wide = np.array([shape, 1.0])
    start, axis = np.array(mask["at"]) * wide, (np.array(mask["to"]) - np.array(mask["at"])) * wide
    here, long = np.array(place) * wide - start, float(np.hypot(*axis))
    along = float(here @ axis) / (long * long)
    if mask["kind"] == "linear":
        weight = 1 - _step(-1.0, 1.0, along)
    else:
        across = float(here @ np.array([-axis[1], axis[0]])) / (long * long * mask["ratio"])
        weight = 1 - _step(1 - max(mask["feather"], 1e-4), 1.0, math.hypot(along, across))
    return 1 - weight if mask["invert"] else weight


def pin_weight(pin: dict, lab) -> float:
    """How much of a pin a color (lightness, a, b) gets: all of it within the pin's core,
    none beyond its range or outside its span of lightness, smoothly in between. (Its mask,
    if it has one, comes on top: `pins_at`.)"""
    far = math.dist(lab[1:], pin["from"])
    core = min(pin["range"] * (1 - pin["feather"] / 100), pin["range"] - 1e-4)
    weight = 1 - _step(core, pin["range"], far)
    if pin["low"] > 0:
        weight *= _step(pin["low"] - BAND, pin["low"] + BAND, lab[0])
    if pin["high"] < 1:
        weight *= 1 - _step(pin["high"] - BAND, pin["high"] + BAND, lab[0])
    return weight


def pins_at(pins: list[dict], lab, masked=None) -> np.ndarray:
    """What the pins make of a color (lightness, a, b). The same arithmetic as
    ui/pipeline.frag: each pin moves the color as it was, the moves add up, and what a
    protecting pin covers is moved that much less. `masked`: for each of the photo's masks,
    how much of it the pixel is in (`mask_weight`); a pin with a mask works that much."""
    lab = np.array(lab, dtype=float)
    moved, shield = np.zeros(3), 0.0
    for pin in pins:
        weight = pin_weight(pin, lab) * _masked(pin, masked)
        if pin["mode"] == "protect":
            shield = max(shield, weight)
            continue
        source, target, color = np.array(pin["from"]), np.array(pin["to"]), lab[1:]
        hue = math.hypot(*source) >= NEUTRAL  # the source has one
        if hue and pin["variance"] and math.hypot(*color) > 1e-6:
            apart = _between(math.atan2(color[1], color[0]) - math.atan2(source[1], source[0]))
            moved[1:] += _turned(color, weight * pin["variance"] / 100 * apart) - color
        if pin["mode"] == "rotate" and hue:
            turn = _between(math.atan2(target[1], target[0]) - math.atan2(source[1], source[0]))
            grown = 1 + weight * (math.hypot(*target) / math.hypot(*source) - 1)
            moved[1:] += _turned(color, weight * turn) * grown - color
        else:
            moved[1:] += weight * (target - source)
        moved[0] += weight * pin["light"]
    return lab + (1 - shield) * moved


def _masked(pin: dict, masked) -> float:
    """How much of a pin its mask lets through at a pixel (all of it without one; none when
    its mask is gone)."""
    if not masked or not pin.get("mask"):
        return 1.0 if not pin.get("mask") or masked is None else 0.0
    return masked[pin["mask"] - 1] if pin["mask"] <= len(masked) else 0.0


def _shield(pins: list[dict], lab, masked=None) -> float:
    """How much of a color the protecting pins cover."""
    return max((pin_weight(pin, lab) * _masked(pin, masked)
                for pin in pins if pin["mode"] == "protect"), default=0.0)


def eq_at(points: list[dict], hue: float) -> float:
    """What the color EQ makes of the chroma of a color of that hue (degrees): times this."""
    gain = 1.0
    for point in points:
        apart = abs((hue - point["hue"] + 180) % 360 - 180)
        gain += (1 - _step(point["width"] / 2, point["width"], apart)) * (point["gain"] / 100 - 1)
    # (A plain number: as one of numpy's the interface could not read it, and the EQ's line
    # was not drawn once it had a point.)
    return float(max(0.0, gain))


def chroma_at(points: list[list[float]], chroma: float) -> float:
    """What the chroma curve makes of a chroma: the curve reads it as a share of VIVID, and
    carries on at the color's own pace beyond that."""
    x = chroma / VIVID
    return (curve_at(points, min(x, 1.0)) + max(x - 1.0, 0.0)) * VIVID


def vibrance_at(vibrance: float, chroma: float, hue: float) -> float:
    """What Vibrance (-100..100) makes of a chroma: times this. The muted colors gain most
    (+100 doubles a gray-ish one) and the vivid ones nothing (from a chroma of 0.25 on), so
    that nothing is pushed past what a screen can show; and colors of skin (OKLab hue 55
    degrees, fading out 15 to 35 degrees to either side) gain only three tenths of it.
    Below 0 the muted colors go toward gray and the vivid ones stay."""
    skin = 1 - 0.7 * (1 - _step(15, 35, abs((hue - 55 + 180) % 360 - 180)))
    return 1 + vibrance / 100 * skin * (1 - _step(0.0, 0.25, chroma))


def colors_at(edit: dict, lab, place=None, shape: float = 1.0) -> np.ndarray:
    """Everything that is done to a color (lightness, a, b) after the tone curve, in the
    shader's order: the pins, then saturation and vibrance (not where a pin protects), the
    chroma curve and the color EQ. The same arithmetic as ui/pipeline.frag. `place`: where in
    the stored picture the pixel is (0..1), which the masks go by; `shape`: its width over its
    height."""
    full = {**DEFAULTS, **edit}
    masked = None if place is None else [mask_weight(m, place, shape) for m in full["masks"]]
    shield = _shield(full["pins"], lab, masked)
    out = pins_at(full["pins"], lab, masked)
    chroma = math.hypot(out[1], out[2])
    if chroma > 1e-6:
        hue = math.degrees(math.atan2(out[2], out[1]))
        after = chroma * (full["saturation"] / 100 * (1 - shield) + shield)
        after *= vibrance_at(full["vibrance"] * (1 - shield), after, hue)
        after = chroma_at(full["chroma"], after)
        after *= eq_at(full["eq"], hue)
        out[1:] *= after / chroma
    return out


def look_uniforms(full: dict) -> dict:
    """Saturation, the chroma curve and the color EQ for the shader; and `look`: whether
    anything at all is done to colors after the tone curve."""
    slope = slopes(full["chroma"])
    fill = POINTS - len(full["chroma"])
    bands = []
    for point in full["eq"]:
        bands += [point["hue"], point["gain"] / 100 - 1, point["width"], 0.0]
    bands += [0.0] * (BANDS * 4 - len(bands))
    plain = (full["saturation"] == 100 and full["vibrance"] == 0
             and full["chroma"] == STRAIGHT and not full["eq"])
    return {"look": 0.0 if plain and not full["pins"] else 1.0,
            "saturation": full["saturation"] / 100, "vibrance": full["vibrance"] / 100,
            "chromaOn": 0.0 if full["chroma"] == STRAIGHT else 1.0,
            "chromaX": [p[0] for p in full["chroma"]] + [full["chroma"][-1][0]] * fill,
            "chromaY": [p[1] for p in full["chroma"]] + [full["chroma"][-1][1]] * fill,
            "chromaM": slope + [0.0] * fill,
            "eqCount": float(len(full["eq"])), "eqA0": bands[:16], "eqA1": bands[16:]}


def masks_uniforms(masks: list[dict], shape: float) -> dict:
    """The masks for the shader, in four matrices of four masks each, worked out as far as
    can be: with (u, v) a place in the stored picture, a mask's A is (x, y, z, kind) and its B
    (x, y, z, feather), and u·x + v·y + z is how far along the mask's axis the place is (A)
    and how far across it (B), 1 being its edge. Kind: 0 radial, 1 linear, 2 painted (its A
    is then the channel of the raster it is in, `painted`), 4 more when inverted. A slot
    without a mask covers nothing, and neither does a mask that is off."""
    along, across = [], []
    wide = np.array([shape or 1.0, 1.0])
    brushes = 0
    for mask in masks:
        channel, brushes = brushes, brushes + (mask["kind"] == "brush")
        if mask.get("off"):
            along += [0.0, 0.0, 2.0, 0.0]
            across += [0.0, 0.0, 0.0, 1.0]
            continue
        if mask["kind"] == "brush":
            along += [float(channel), 0.0, 0.0, 2.0 + 4 * mask["invert"]]
            across += [0.0, 0.0, 0.0, 1.0]
            continue
        start, axis = np.array(mask["at"]) * wide, (np.array(mask["to"]) - mask["at"]) * wide
        long = float(axis @ axis)
        side = np.array([-axis[1], axis[0]]) / mask["ratio"]
        kind = KINDS.index(mask["kind"]) + 4 * mask["invert"]
        along += [*(axis * wide / long), -float(start @ axis) / long, float(kind)]
        across += [*(side * wide / long), -float(start @ side) / long, max(mask["feather"], 1e-4)]
    for _ in range(MASKS - len(masks)):
        along += [0.0, 0.0, 2.0, 0.0]
        across += [0.0, 0.0, 0.0, 1.0]
    return {"masksA0": along[:16], "masksA1": along[16:],
            "masksB0": across[:16], "masksB1": across[16:]}


def without_mask(edit: dict, number: int) -> dict:
    """The edit's masks and pins once mask `number` (1, 2, …) is deleted: its pins go with
    it, and the pins of later masks follow theirs down."""
    full = {**DEFAULTS, **edit}
    pins = [{**pin, "mask": pin["mask"] - (pin.get("mask", 0) > number)}
            for pin in full["pins"] if pin.get("mask", 0) != number]
    return {"masks": full["masks"][:number - 1] + full["masks"][number:], "pins": pins}


def pins_uniforms(pins: list[dict]) -> dict:
    """The pins for the shader: three numbers-of-four per pin, in nine matrices of four pins
    each. A: from, to. B: range, core, light, variance. C: low, high, kind (0 offset,
    1 rotate, 2 protect)."""
    rows = {"A": [], "B": [], "C": []}
    for pin in pins:
        core = min(pin["range"] * (1 - pin["feather"] / 100), pin["range"] - 1e-4)
        kind = MODES.index(pin["mode"])
        if kind == 1 and math.hypot(*pin["from"]) < NEUTRAL:
            kind = 0
        rows["A"] += [*pin["from"], *pin["to"]]
        rows["B"] += [pin["range"], core, pin["light"], pin["variance"] / 100]
        rows["C"] += [pin["low"], pin["high"], float(kind), float(pin.get("mask", 0))]
    out = {"pinCount": float(len(pins))}
    for letter, numbers in rows.items():
        numbers += [0.0] * (PINS * 4 - len(numbers))
        out.update({f"pins{letter}{n}": numbers[16 * n:16 * n + 16] for n in range(3)})
    return out


def uniforms(edit: dict, camera: dict | None, raw: bool, white: float = 1.0,
             shape: float = 1.0) -> dict:
    """Everything ui/pipeline.frag takes, as plain numbers (matrices as 3 rows of 3, the
    curve as lists of 16). `white` is how bright the sensor's white may be shown, in multiples
    of the display's white: 1 in SDR, the display's peak in HDR. `shape`: the stored picture's
    width over its height, which the masks go by."""
    full = {**DEFAULTS, **edit}
    to_cam, from_cam, wb = balance(full, camera)
    c, s, k = curve(full["profile"]) if raw else (0.0, 1.0, 1.0)  # 0: no curve
    return {"gain": 2.0 ** exposure_of(full, camera), "wbGain": wb,
            "toCam": to_cam.tolist(), "fromCam": from_cam.tolist(),
            "mid": MID if raw else MID_FINISHED,
            # Contrast: stops from mid gray are stretched by this much (+100 doubles them).
            "contrast": 2.0 ** (full["contrast"] / 100) - 1,
            # Brightness: a power on the finished picture's luminance, less one (+100: 0.5).
            "brightness": 2.0 ** (-full["brightness"] / 100) - 1,
            "highlights": full["highlights"] / 100, "shadows": full["shadows"] / 100 * 1.5,
            "midtones": full["midtones"] / 100,  # a stop at mid gray
            # Whites: up to 0.6 stops at white. Blacks: light taken away at black (+100 adds
            # it: sign turned), by the square of the slider, since a display's steps near
            # black are that much finer: 0.03 of white is level 48 of 255.
            "whites": full["whites"] / 100 * 0.6,
            "blacks": -math.copysign(0.03 * (full["blacks"] / 100) ** 2, full["blacks"]),
            "curveC": c, "curveS": s, "curveK": k,
            "hdrLift": max(0.0, white - 1) if raw else 0.0,
            **curve_uniforms(full["curve"]), **pins_uniforms(full["pins"]), **look_uniforms(full),
            **masks_uniforms(full["masks"], shape)}


# ---- the frame -------------------------------------------------------------------------------

# Where a point of the picture as it stands after so many quarter turns to the right lies in
# the stored picture, both 0..1: rows of a matrix for (x, y, 1).
TURNED = (((1, 0, 0), (0, 1, 0)), ((0, 1, 0), (-1, 0, 1)),
          ((-1, 0, 1), (0, -1, 1)), ((0, -1, 1), (1, 0, 0)))


def _fits(middle, half, turn, size) -> float:
    """How much of a turned rectangle (its middle, half its size, its turn, all in pixels of
    the picture) fits in the picture about its middle: all of it (1), or the share it has to
    shrink to."""
    room = [(middle if d < 0 else size - middle)[axis] / abs(d)
            for sign in ((-1, -1), (1, -1), (1, 1), (-1, 1))
            for axis, d in enumerate(turn @ (half * sign)) if abs(d) > 1e-9]
    return min([1.0, *room]) if size.all() else 1.0


def _laid(full: dict, width: int, height: int, loose: bool) -> tuple:
    """The frame as a rectangle laid on the picture as it stands after the turns: its middle
    and half its size in pixels, the turn that takes its own directions to the picture's, and
    that picture's size. `loose`: the Crop tool's view instead, which is all of the picture
    under a level frame: the rectangle round the turned picture."""
    size = np.array([height, width] if int(full["turns"]) % 2 else [width, height], dtype=float)
    angle = math.radians(full["angle"])
    turn = np.array([[math.cos(angle), math.sin(angle)], [-math.sin(angle), math.cos(angle)]])
    if loose:
        return size / 2, np.abs(turn) @ size / 2, turn, size
    left, top, right, bottom = full["crop"]
    middle = np.array([left + right, top + bottom]) * size / 2
    half = np.array([right - left, bottom - top]) * size / 2
    return middle, half * _fits(middle, half, turn, size), turn, size


def frame(edit: dict, width: int, height: int, loose: bool = False) -> dict:
    """The photo's frame, for a stored picture of that size.

    `matrix`: 16 numbers (by columns) that take a point of the frame, (0, 0) its top left and
    (1, 1) its bottom right, to its place in the stored picture; `size`: the frame in pixels;
    `shape`: its width over its height, unrounded.
    With an angle the frame is made just small enough, about its middle, to stay inside the
    picture. `loose`: what the Crop tool shows instead: the whole picture, turned by the angle
    so that the frame lies level on it, in the rectangle that just holds it (its corners are
    outside the picture)."""
    full = {**DEFAULTS, **edit}
    middle, half, turn, size = _laid(full, width, height, loose)
    # A point of the frame -> pixels of the turned picture -> 0..1 of it -> the stored picture.
    to_pixels = np.eye(3)
    to_pixels[:2, :2] = turn * (2 * half)
    to_pixels[:2, 2] = middle - turn @ half
    to_unit = np.diag([1 / max(1, size[0]), 1 / max(1, size[1]), 1.0])
    m = (np.vstack([TURNED[int(full["turns"]) % 4], (0, 0, 1)]) @ to_unit @ to_pixels).tolist()
    return {"matrix": [m[0][0], m[1][0], 0.0, 0.0, m[0][1], m[1][1], 0.0, 0.0,
                       0.0, 0.0, 1.0, 0.0, m[0][2], m[1][2], 0.0, 1.0],
            "size": (max(1, round(2 * half[0])), max(1, round(2 * half[1]))),
            "shape": float(half[0] / half[1]) if half[1] else 1.0}


def frame_in_view(edit: dict, width: int, height: int) -> list[float]:
    """Where the photo's frame lies in the Crop tool's view: left, top, right, bottom, 0..1.
    Level, as that view is the picture turned by the frame's own angle."""
    tight, loose = (frame(edit, width, height, loose=loose)["matrix"] for loose in (False, True))
    return [*unframed(loose, *framed(tight, 0, 0)), *unframed(loose, *framed(tight, 1, 1))]


def crop_for(edit: dict, size: tuple, start, wanted, together: bool = True) -> list[float]:
    """The crop that puts the frame where the Crop tool is asked to: at `wanted` (left, top,
    right, bottom in the tool's view, 0..1: `frame(loose=True)`), or as far toward it from
    `start` as it stays inside the picture. `together`: both directions at one pace (a shape
    is being kept); otherwise across first and then down, so that a frame at the picture's
    edge still slides along it."""
    middle, half, turn, pixels = _laid({**DEFAULTS, **edit}, *size, loose=True)

    def laid(rect) -> tuple:  # that rectangle on the picture: its middle, half its size
        low, high = rect[:2], rect[2:]
        return middle + turn @ ((low + high - 1) * half), (high - low) * half

    def toward(here, there):  # as far from here to there as stays inside
        low, high = 0.0, 0.0 if _fits(*laid(here), turn, pixels) < 1 - 1e-6 else 1.0
        if _fits(*laid(there), turn, pixels) >= 1 - 1e-9:
            return there
        for _ in range(24):
            mid = (low + high) / 2
            ok = _fits(*laid(here + (there - here) * mid), turn, pixels) >= 1 - 1e-9
            low, high = (mid, high) if ok else (low, mid)
        return here + (there - here) * low

    start, wanted = np.array(start, dtype=float), np.array(wanted, dtype=float)
    if start.shape != (4,) or wanted.shape != (4,) or not np.isfinite([*start, *wanted]).all():
        raise ValueError("a frame is four numbers")
    if not together:
        start = toward(start, np.array([wanted[0], start[1], wanted[2], start[3]]))
        wanted = np.array([start[0], wanted[1], start[2], wanted[3]])
    at, reach = laid(toward(start, wanted))
    return [float(v) for v in (*((at - reach) / pixels), *((at + reach) / pixels))]


def framed(matrix: list[float], u: float, v: float) -> tuple[float, float]:
    """Where a point of the frame lies in the stored picture."""
    return (matrix[0] * u + matrix[4] * v + matrix[12], matrix[1] * u + matrix[5] * v + matrix[13])


def unframed(matrix: list[float], x: float, y: float) -> tuple[float, float]:
    """Where a point of the stored picture lies in the frame: `framed` the other way."""
    x, y = x - matrix[12], y - matrix[13]
    size = matrix[0] * matrix[5] - matrix[4] * matrix[1]
    if not size:  # no frame yet (a photo with masks whose picture is still being read):
        return (x, y)  # nothing is drawn of it, and nothing may fail (it raised here)
    return ((matrix[5] * x - matrix[4] * y) / size, (matrix[0] * y - matrix[1] * x) / size)


# ---- history -------------------------------------------------------------------------------

class History:
    """Undo and redo over whole edits. A run of changes to one setting (a slider being dragged)
    is one step: it ends at `commit`, or when another setting changes."""

    KEPT = 100  # steps that are written down with a photo's edit (`kept`)

    def __init__(self, start: dict | None = None, steps: tuple | None = None) -> None:
        """`start`: the edit as it stands. `steps`: (the states, which one it stood at) as kept
        from when the photo was last open: taken up if they end where the edit stands, so that
        undo and redo carry on; not otherwise (the edit was changed elsewhere since)."""
        self.states, self.at, self.open = [dict(start or {})], 0, None
        try:
            states, at = [clean(state) for state in steps[0]], int(steps[1])
            if 0 <= at < len(states) and states[at] == self.edit:
                self.states, self.at = states, at
        except (TypeError, ValueError, IndexError, KeyError):
            pass  # none kept, or not what was written there

    def kept(self) -> tuple[list[dict], int]:
        """(The states, which one it stands at) to write down: all of them, or the KEPT round
        where it stands."""
        first = max(0, min(self.at - self.KEPT // 2, len(self.states) - self.KEPT))
        return self.states[first:first + self.KEPT], self.at - first

    @property
    def edit(self) -> dict:
        return self.states[self.at]

    def set(self, key: str, value) -> None:
        self.put({key: value})

    def put(self, values: dict) -> None:
        """Change settings. The same ones changed again and again (a slider being dragged, a
        pad that moves two at once) stay one step until `commit`."""
        now = {**self.edit, **{key: valid(key, value) for key, value in values.items()}}
        now = {k: v for k, v in now.items() if v != DEFAULTS[k]}
        if now == self.edit:
            return
        gesture = tuple(sorted(values))
        if self.open != gesture:
            del self.states[self.at + 1:]  # a new change ends what could be redone
            self.states.append(now)
            self.at += 1
            self.open = gesture
        else:
            self.states[self.at] = now

    def replace(self, whole: dict) -> None:
        """Another edit altogether (a checkpoint gone back to), as one step of its own."""
        self.commit()
        whole = clean(whole)
        if whole != self.edit:
            del self.states[self.at + 1:]
            self.states.append(whole)
            self.at += 1

    def commit(self) -> None:
        self.open = None
        if self.at and self.states[self.at] == self.states[self.at - 1]:
            del self.states[self.at]  # dragged there and back: nothing to undo
            self.at -= 1

    def step(self, by: int) -> bool:
        self.commit()
        to = self.at + by
        if not 0 <= to < len(self.states):
            return False
        self.at = to
        return True


# ---- checkpoints ---------------------------------------------------------------------------

def clean_checkpoints(found) -> list[dict]:
    """A photo's checkpoints as read from somewhere untrusted: only those that are whole."""
    out = []
    for item in found if isinstance(found, list) else ():
        if not isinstance(item, dict):
            continue
        number, name, made = item.get("id"), item.get("name"), item.get("made")
        if (isinstance(number, int) and isinstance(name, str) and name.strip()
                and isinstance(made, (int, float)) and number not in {c["id"] for c in out}):
            out.append({"id": number, "name": name.strip()[:80], "made": float(made),
                        "edit": clean(item.get("edit"))})
    return out


def unsaved(points: list[dict], now: dict, base: int | None) -> list[str]:
    """The settings of `now` that are not as the checkpoint it came from has them: `base` (the
    one last saved or gone to) while it is there, else the newest. With no checkpoint, the
    settings not at rest; standing at a checkpoint, none. (The owner: "Unsaved modified
    parameters ... should be colored yellow".)"""
    if standing(points, now, base)[0] is not None:
        return []
    kept = {point["id"]: point["edit"] for point in points}
    was = kept.get(base, points[-1]["edit"] if points else {})
    return sorted(key for key in DEFAULTS
                  if now.get(key, DEFAULTS[key]) != was.get(key, DEFAULTS[key]))


def standing(points: list[dict], now: dict, base: int | None) -> tuple[int | None, bool]:
    """(the checkpoint the edit `now` stands at, or None; whether `now` is unsaved).

    The edit stands at a checkpoint when it is that checkpoint's edit: at `base`, the one last
    saved or gone to, if that fits, else at the first that does. Otherwise it is unsaved,
    unless nothing was ever done to the photo (no base, and every setting at rest)."""
    fitting = [c["id"] for c in points if c["edit"] == now]
    if fitting:
        return (base if base in fitting else fitting[0]), False
    return None, bool(now) or base is not None

