import sys

__version__ = "0.1.0"
HOMEPAGE = "https://github.com/TominoCZ/Photone"  # where "View on GitHub" goes
# For subprocess: on Windows a console program started from a window opens a console of its
# own, which flashed up at every shader compiled and every reading of the GPU's memory (seen
# by the first user there). CREATE_NO_WINDOW; nothing elsewhere.
QUIET = {"creationflags": 0x08000000} if sys.platform == "win32" else {}
