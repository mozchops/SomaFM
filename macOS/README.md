# SomaFM for macOS

A menu bar port of the Omarchy widget in `../omarchy/`. Shared behaviour and design are defined in [../docs/SPEC.md](../docs/SPEC.md).

Requires macOS 14+ and the Xcode command line tools.

```bash
sh build-app.sh
open /Applications/SomaFM.app
```

The app is ad-hoc signed for local use. The bar item shows an outlined box with a level meter and the station name; hover it for the track, bitrate and codec. The popup is always dark. Settings and the station cache are stored in `~/Library/Application Support/SomaFMMinimal/`.

It has no automated tests, and several features are not built yet; the status table in the spec lists them.
