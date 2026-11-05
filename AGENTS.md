# Agent guidance

SomaFM ships as four native hosts that share no executable code:

- **Omarchy** (`omarchy/`: `BarWidget.qml` + Python helpers `somafm.py`, `mpris.py`): the **reference design and behaviour**.
- **macOS** (`macOS/`, Swift, AppKit + SwiftUI, macOS 14+): a menu bar port styled after the Omarchy widget.
- **Windows** (`windows/`, WPF, `SomaFM.Windows/`): the original Windows client, imported with its git history. It predates the shared spec and has its own design.
- **iOS** (`ios/`, SwiftUI, iOS 17+): iPhone/iPad app with a visualizer, history and notifications. It predates the shared spec and has its own design.

## Keep platforms in sync

- Omarchy defines the design. When either host changes, mirror the change to the other in the same piece of work, adapted to the host's UI.
- `docs/SPEC.md` is the cross-platform contract: layout, colours, behaviour, stored settings and per-platform status. Update it whenever behaviour or design changes.
- Do not call a platform implemented or verified because the other host passes its checks. Report which host you actually built and ran.
- Record gaps in the status table in `docs/SPEC.md` instead of leaving them implicit.

## Build and test

| Host | Command | Runs on |
|---|---|---|
| Omarchy | `cd omarchy && dbus-run-session -- python -m unittest discover -s tests -v` | Linux with the Omarchy runtime (the widget check is skipped without it) |
| Windows | `dotnet build windows/SomaFM.Windows/SomaFM.Windows.csproj` | Windows only; not built or tested since the move |
| iOS | `cd ios && xcodebuild -project SomaFMiOS.xcodeproj -scheme SomaFMiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` | macOS with Xcode |
| macOS | `sh macOS/build-app.sh` (installs to `/Applications/SomaFMMinimal.app`) | macOS with Xcode command line tools, Swift 5 language mode |

The macOS port has no automated tests. Windows and iOS were imported as they were and have no tests here.

Do not bump `omarchy/manifest.json`'s version or publish a release unless explicitly asked.
