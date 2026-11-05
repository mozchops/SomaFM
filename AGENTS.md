# Agent guidance

SomaFM ships as two native hosts that share no executable code:

- **Omarchy** (`omarchy/`: `BarWidget.qml` + Python helpers `somafm.py`, `mpris.py`): the **reference design and behaviour**.
- **macOS** (`macOS/`, Swift, AppKit + SwiftUI, macOS 14+): a menu bar port styled after the Omarchy widget.

## Keep platforms in sync

- Omarchy defines the design. When either host changes, mirror the change to the other in the same piece of work, adapted to the host's UI.
- `docs/SPEC.md` is the cross-platform contract: layout, colours, behaviour, stored settings and per-platform status. Update it whenever behaviour or design changes.
- Do not call a platform implemented or verified because the other host passes its checks. Report which host you actually built and ran.
- Record gaps in the status table in `docs/SPEC.md` instead of leaving them implicit.

## Build and test

| Host | Command | Runs on |
|---|---|---|
| Omarchy | `cd omarchy && dbus-run-session -- python -m unittest discover -s tests -v` | Linux with the Omarchy runtime (the widget check is skipped without it) |
| macOS | `sh macOS/build-app.sh` (output `macOS/build/SomaFMMinimal.app`) | macOS with Xcode command line tools, Swift 5 language mode |

The macOS port has no automated tests.

Do not bump `omarchy/manifest.json`'s version or publish a release unless explicitly asked.
