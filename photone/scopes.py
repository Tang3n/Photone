"""What is counted from the pipeline's own small renders: the histogram, and the photo's colors
for the wheel. The interface draws them (ui/PhotoView.qml), Qt reads them back, and they arrive
here as bytes: six tiles, three by two.

    the picture as displayed   its lightness before the curve   OKLab a (2 bytes), lightness
    OKLab b (2 bytes)          a and lightness after the pins   b after the pins

The colors before the pins are what a pin takes its source from and what the wheel shows as
"before"; those after the pins are the wheel's "after".

Counting from the picture itself is what keeps a scope from ever disagreeing with it.
"""

from __future__ import annotations

import numpy as np

# OKLab's cube-rooted cone signals from (L, a, b), and linear sRGB from the cone signals.
LAB_TO_ROOTS = np.array([[1.0, 0.3963377774, 0.2158037573], [1.0, -0.1055613458, -0.0638541728],
                         [1.0, -0.0894841775, -1.2914855480]])
LMS_TO_SRGB = np.array([[4.0767416621, -3.3077115913, 0.2309699292],
                        [-1.2684380046, 2.6097574011, -0.3413193965],
                        [-0.0041960863, -0.7034186147, 1.7076147010]])
# The spans of lightness the wheel can be limited to ("working range").
RANGES = {"full": (0.0, 1.0), "highlights": (0.7, 1.0), "midtones": (0.35, 0.75),
          "shadows": (0.0, 0.4)}
DOTS = 3000  # the most the wheel is asked to draw


def tiles(seen: np.ndarray) -> list[np.ndarray]:
    """The six renders out of one grab (rows x columns x 4 bytes)."""
    h, w = seen.shape[0] // 2, seen.shape[1] // 3
    return [seen[y:y + h, x:x + w] for y in (0, h) for x in (0, w, 2 * w)]


def histogram_of(seen: np.ndarray) -> dict:
    """r, g, b of the picture as displayed and `light` (before the tone curve): 256 heights
    each, relative to the tallest bar that is not at an end, so that a clipped spike does not
    flatten everything else; `over`, `under`: the share of pixels at white and at black."""
    picture, light = tiles(seen)[0][..., :3].reshape(-1, 3), tiles(seen)[1][..., 0].ravel()
    counts = [np.bincount(picture[:, i], minlength=256) for i in range(3)]
    tallest = max(1, *(int(c[1:255].max()) for c in counts))
    lightness = np.convolve(np.bincount(light, minlength=256), [0.25, 0.5, 0.25], "same")
    out = {"rgb"[i]: np.minimum(c / tallest, 1.0).tolist() for i, c in enumerate(counts)}
    out["light"] = np.minimum(lightness / max(1.0, lightness[1:255].max()), 1.0).tolist()
    out["over"] = float((picture.max(axis=1) == 255).mean())
    out["under"] = float((picture.max(axis=1) == 0).mean())
    return out


def spread_of(light: np.ndarray, a: np.ndarray, b: np.ndarray) -> dict:
    """What lies behind the chroma curve and the color EQ: `chroma`, how much of the photo is
    how vivid (64 heights, from gray to a chroma of 0.4), and `hue`, how much of it has which
    hue (90 heights, 4 degrees each), each pixel counting for as much as it has color."""
    vivid, angle = np.hypot(a, b).ravel(), np.degrees(np.arctan2(b, a)).ravel() % 360
    chroma = np.bincount(np.minimum((vivid / 0.4 * 64).astype(int), 63), minlength=64)[1:]
    hue = np.bincount(np.minimum((angle / 4).astype(int), 89), vivid, 90)
    # (The first bar, the grays, is left out: it would dwarf the rest.)
    return {"chroma": [0.0, *(chroma / max(1, chroma.max())).tolist()],
            "hue": (hue / max(1e-9, hue.max())).tolist()}


def hues(count: int = 37) -> list[str]:
    """The hues round the wheel as colors, from 0 degrees to 360: the color EQ's strip."""
    angle = np.radians(np.linspace(0, 360, count))
    shown = srgb_of(np.full(count, 0.72), 0.13 * np.cos(angle), 0.13 * np.sin(angle)).tolist()
    return [f"#{red:02x}{green:02x}{blue:02x}" for red, green, blue in shown]


def lab_of(seen: np.ndarray, pinned: bool = False) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """(lightness, a, b) of the picture after the tone curve, before the pins or after them
    (`pinned`), one value per pixel of a tile."""
    third, fourth = (t.astype(np.float32) for t in tiles(seen)[4 if pinned else 2:][:2])
    a = (third[..., 0] * 256 + third[..., 1]) / 65535 - 0.5
    b = (fourth[..., 0] * 256 + fourth[..., 1]) / 65535 - 0.5
    return third[..., 2] / 255, a, b


def srgb_of(light: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """OKLab colors as sRGB bytes, cut to what sRGB can show."""
    roots = np.stack([light, a, b], axis=-1) @ LAB_TO_ROOTS.T
    linear = np.clip(roots ** 3 @ LMS_TO_SRGB.T, 0, 1)
    coded = np.where(linear <= 0.0031308, 12.92 * linear, 1.055 * linear ** (1 / 2.4) - 0.055)
    return np.round(coded * 255).astype(np.uint8)


def cloud_of(light: np.ndarray, a: np.ndarray, b: np.ndarray, tones: tuple = (0.0, 1.0)) -> dict:
    """The photo's colors, counted for the wheel: what Fit frames and what the checks look at.
    (The wheel's dots themselves are drawn by the GPU from the photo: ui/dots.vert.)

    Returns `points` (one a, b per dot), `colors` (one red, green, blue byte triple per dot),
    both as arrays, `box` (the least and most a, then b, of the colors: what Fit frames) and
    `light` (64 heights: how much of the photo is how light, whatever the range). `listed`
    gives the same as plain lists.

    Only pixels whose lightness is within `tones` (least, most) count. Colors are gathered
    into cells of a grid, in three bands of lightness, so that a common color is one dot and
    not thousands; the grid gets coarser until there are few enough to draw. A dot is one real
    color out of its cell, not the cell's average: drawn at the averages, a crowd of colors
    shows as the grid it was counted on."""
    bars = np.bincount(np.minimum((light.ravel() * 64).astype(int), 63), minlength=64)
    out = {"points": np.zeros((0, 2), np.float32), "colors": np.zeros((0, 3), np.uint8),
           "box": [], "light": (bars / max(1, bars.max())).tolist()}
    keep = (light >= tones[0]) & (light <= tones[1])
    light, a, b = light[keep], a[keep], b[keep]
    if light.size:
        out["box"] = [float(a.min()), float(a.max()), float(b.min()), float(b.max())]
    step = 0.004
    while light.size:
        across, up = (np.round(v / step).astype(np.int64) + 4096 for v in (a, b))
        cell = (across * 8192 + up) * 3 + np.minimum((light * 3).astype(np.int64), 2)
        cells, first, count = np.unique(cell, return_index=True, return_counts=True)
        if cells.size <= DOTS:
            break
        step *= 1.5
    else:
        return out
    order = first[np.argsort(count, kind="stable")]  # the commonest colors last: drawn on top
    lit, x, y = light[order], a[order], b[order]
    out["points"], out["colors"] = np.stack([x, y], axis=-1).astype(np.float32), srgb_of(lit, x, y)
    return out


def listed(cloud: dict) -> dict:
    """A cloud with its dots as plain lists: `points` a, b, a, b, …; `colors` "#rrggbb" each."""
    colors = [f"#{red:02x}{green:02x}{blue:02x}" for red, green, blue in cloud["colors"].tolist()]
    return {**cloud, "points": cloud["points"].ravel().tolist(), "colors": colors}


def heights(values) -> bytes:
    """Heights from 0 to 1 as one byte each: how the interface is handed a row of bars."""
    return np.round(np.clip(np.asarray(values, dtype=float), 0, 1) * 255).astype(np.uint8).tobytes()
