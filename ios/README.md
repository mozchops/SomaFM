# SomaFM for iOS

A native SwiftUI iOS app for SomaFM internet radio, supporting iPhone and iPad. It is built separately from the macOS menu-bar app in `../macOS/`.

## Features

- Adaptive iPhone and iPad station browser with search and favorites.
- Live SomaFM stream playback, volume, and track metadata.
- Live spectrum or waveform visualization with selectable color palettes.
- Background audio playback and iOS lock-screen/media controls.
- Per-station listening time, recent track history, and optional track-change notifications.
- AirPlay and external audio output selection.
- Choose System, Light, or Dark appearance in Settings.

The macOS menu-bar display options do not apply on iOS. The visualizer is presented in the Now Playing view instead.

## Requirements

- Xcode 15 or later with the iOS/iPadOS SDK.
- iOS 17 or later on a device or simulator.
- An Apple ID configured for Xcode signing to install on a physical device.

## Open and run in Xcode

1. Open `SomaFMiOS.xcodeproj`.
2. Select the **SomaFMiOS** app scheme and an iPhone or iPad simulator or connected device.
3. For a physical device, select the app target's **Signing & Capabilities** tab and choose your Apple Developer team. Change the bundle identifier if Xcode reports it is already in use.
4. Connect the device over USB, unlock it, and trust the computer if prompted. Enable Developer Mode if prompted.
5. Press **Run** in Xcode. Xcode builds, signs, installs, and launches the app.

For personal testing, a free Apple ID can be selected as the signing team. Free provisioning has limits and expires periodically, so Xcode may need to reinstall or re-sign the app. A paid Apple Developer Program account is needed for TestFlight and App Store distribution.

## Build from Terminal

With full Xcode installed and selected as the active developer directory:

```sh
xcodebuild -project SomaFMiOS.xcodeproj \
  -scheme SomaFMiOS \
  -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)' \
  build
```

Use a simulator name available in your Xcode installation. For a connected iPad, select its device destination in Xcode and run the app so Xcode can apply your signing settings.

## Data and audio

Station cache, favorites, listening time, and recent track history are stored in the app's application-support directory. The app requests SomaFM's public channel and track metadata endpoints and streams audio directly from SomaFM. Background audio is enabled for playback while the app is backgrounded or the screen is locked.

Before public distribution, confirm with SomaFM that your intended use of its streams, metadata, and branding is permitted.
