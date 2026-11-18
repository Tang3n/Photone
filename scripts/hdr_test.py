"""Does HDR reach this screen from a native window? A test picture to look at.

    ./run.sh hdr-test            an HDR (scRGB) surface, written sRGB-encoded as the app does
    ./run.sh hdr-test --linear   the same, written as linear light (if the gray check fails)
    ./run.sh hdr-test --sdr      an ordinary 8-bit window, for comparison
    ./run.sh hdr-test --seconds 3 --grab out.png     for the checks: open, grab, close

Chrome cannot do this on Linux (it reports this display as SDR; measured 2026-11-17), so this
window is drawn by Qt Quick through Vulkan, which can be given an HDR surface. What nothing but
eyes can tell: whether the patches right of "1x" are really brighter. See docs/PLAN.md, 4.10.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILD = HERE.parent / ".dev" / "hdr"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sdr", action="store_true", help="an ordinary SDR window")
    parser.add_argument("--linear", action="store_true", help="write linear light")
    parser.add_argument("--seconds", type=float, help="close by itself after this long")
    parser.add_argument("--grab", type=Path, help="save what was drawn (8-bit) before closing")
    args = parser.parse_args()

    # The environment decides the swapchain, and Qt reads it when the first window is made.
    os.environ.setdefault("QSG_RHI_BACKEND", "vulkan")
    os.environ.setdefault("QSG_INFO", "1")
    if not args.sdr:
        os.environ["QSG_RHI_HDR"] = "scrgb"

    BUILD.mkdir(parents=True, exist_ok=True)
    qsb = BUILD / "hdr_test.frag.qsb"
    subprocess.run(["pyside6-qsb", "--glsl", "100 es,120,150", "-o", str(qsb), str(HERE / "hdr_test.frag")],
                   check=True)

    from PySide6.QtCore import QTimer, QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQuick import QQuickView

    app = QGuiApplication(sys.argv[:1])
    view = QQuickView()
    view.setTitle("Photone HDR test")
    view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
    view.resize(1180, 540)
    view.rootContext().setContextProperty("shaderFile", QUrl.fromLocalFile(str(qsb)).toString())
    view.setSource(QUrl.fromLocalFile(str(HERE / "hdr_test.qml")))
    if view.status() != QQuickView.Status.Ready:
        print("hdr-test: the test page did not load:", [e.toString() for e in view.errors()], file=sys.stderr)
        return 1
    root = view.rootObject()
    root.setProperty("linear", args.linear)
    root.setProperty("hdr", not args.sdr)
    root.setProperty("swapchain", "SDR (8-bit)" if args.sdr else "HDR requested (scRGB)")
    view.show()

    def finish() -> None:
        if args.grab:
            view.grabWindow().save(str(args.grab))
        app.quit()

    if args.seconds:
        QTimer.singleShot(int(args.seconds * 1000), finish)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
