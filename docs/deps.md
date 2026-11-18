# deps.md — what a machine needs to run Photone

Everything that has to be installed on the system, outside the Python packages `uv` fetches from
`pyproject.toml` (PySide6 with Qt inside it, rawpy with LibRaw inside it, numpy). Package names
are Ubuntu/Debian. **Keep this file current:** a change that calls a new program, loads a new
library or relies on a new service adds a row here in the same change.

## Required

| Dependency | Package | Used for | Without it |
|---|---|---|---|
| `uv` | astral.sh installer (`curl -LsSf https://astral.sh/uv/install.sh \| sh`) | Running the app; it fetches Python 3.13 and the packages itself | `run.sh` stops and says so |
| A desktop session, X11 or Wayland | any (`plasma-desktop`, `gnome-shell`, …) | The window | Does not start |
| What Qt's X11 plugin loads | `libxcb-cursor0`, `libxkbcommon-x11-0` | The window on X11 | On X11: "could not load the Qt platform plugin xcb" |
| OpenGL 3.3 / OpenGL ES 3.0 or Vulkan | the GPU vendor's driver (`nvidia-driver-*`, Mesa) | The picture pipeline (a shader) | Qt falls back to software drawing, which has no shaders: the photo is not shown |

## Optional

| Dependency | Package | Used for | Without it |
|---|---|---|---|
| Vulkan with an HDR surface (`VK_EXT_swapchain_colorspace`) on a Wayland desktop with HDR turned on for the display | the GPU driver (`nvidia-driver-*`, `mesa-vulkan-drivers`); Plasma 6 or a recent GNOME | The HDR side of the SDR/HDR switch | The switch says HDR is not available and Photone stays in SDR |
| `kscreen-doctor` | `libkscreen-bin` (part of Plasma) | Reading the display's HDR headroom, for the brightest the photo may get | A headroom of 2× white is assumed |

## Development only (not shipped)
| `update-desktop-database` | `desktop-file-utils` | `./install.sh`: telling the desktop about the new menu entry at once | The entry shows up when the desktop next reads its menu |

| Dependency | Package | Used for |
|---|---|---|
| A running desktop session (Wayland or X11) with a GPU | — | `./run.sh shots`: it renders the real window without showing it, and that needs the graphics driver |
| `ruff` | fetched by `uv run --with ruff` | `./run.sh lint` |
