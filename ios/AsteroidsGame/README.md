# Asteroids

A standalone macOS 3D asteroid shooter built with SwiftUI and SceneKit. Fly from a first-person cockpit through a fully three-dimensional asteroid field, with a mouse-steered ship, illuminated flight-deck instruments, synthesized laser and explosion sounds, and branching asteroid waves.

## Run

Requires macOS 13 or later and Xcode's Swift toolchain. From this folder, run:

```sh
swift run AsteroidsGame
```

The first build may take a little while. Close the game window to exit.

## Controls

- Move the mouse inside the game window to capture it and steer in three dimensions with the centered sight; press **Escape** to release the pointer.
- Hold the left mouse button to fire.
- Hold **W** to accelerate along the ship's facing direction and **S** to brake; the on-screen thrust buttons are also available. Mouse up/down controls pitch.
- Press **R** after losing the ship to start over.

Large asteroids split into four medium rocks when shot. Each medium rock splits into two small rocks, and small rocks disappear when hit.
