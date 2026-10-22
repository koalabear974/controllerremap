# Next Steps — ControllerRemap

## What's done so far

A Swift Package Manager macOS app (Swift 5.9, macOS 11+) with four source files:

| File | Purpose |
|------|---------|
| `Package.swift` | SPM manifest, single executable target `ControllerRemap` |
| `ControllerRemapApp.swift` | AppKit UI: status label, "Gyro → Mouse" toggle (on by default), "Touchpad → Mouse" toggle (off), sensitivity slider 0.1–3.0; 60 FPS tick loop; `GCController` connect/disconnect observers |
| `MouseMover.swift` | Warps the system cursor via `CGWarpMouseCursorPosition`, clamped to the main screen |
| `ControllerManager.swift` | Polls `GCController.motion.rotationRate` (gyro → mouse delta) and `extendedGamepad.touchpads` (touchpad → mouse delta), with per-controller state tracking |

**Status: compiles cleanly** in debug (`.build/arm64-apple-macosx/debug`). All other controller input (buttons, sticks, triggers) is left untouched — only gyro and/or touchpad drive the cursor. No `.app` bundle, executable product, app icon, or entitlements beyond `get-task-allow` exist yet.

## How to build & run

```bash
cd /Users/adrienrobert/gitrepo/controllerremap
swift build
swift run
```

The app opens a small window. With a PS4 controller connected, gyro is on by default and should move the mouse.

## Immediate next steps (in order)

### 1. Verify cursor movement with your PS4 controller (Accessibility permission)

`CGWarpMouseCursorPosition` on macOS usually requires the app to be granted **Accessibility access**. If the cursor doesn't move:

- Grant the app Accessibility access in **System Settings → Privacy & Security → Accessibility**.
- Test with the PS4 controller over **USB and Bluetooth** — the GameController framework exposes motion sensors differently depending on connection type, and PS4 gyro may not show up on all connection paths.
- There is no third-party entitlement that bypasses Accessibility for cursor control, so runtime permission is the practical path.

### 2. Fix the gyro integration math (high priority)

`ControllerManager.updateGyro` currently computes:

```swift
let deltaPitch = (rate.x - state.lastPitch) * Double(dt)
```

That's a *delta-of-rotation-rate × dt*, which is drift-prone and won't feel like natural gyro aiming. Better approaches:

- Use `rotationRate` directly scaled by `dt` (radians/sec × sec = radians) to get an angle delta each tick.
- Or read `motion.attitude` (quaternion/euler angles) and track delta-attitude for drift-free aiming.
- Add a **deadzone** so small hand tremors don't drift the cursor.
- Confirm axis mapping (yaw → X, pitch → Y) and whether Y should be inverted.

### 3. Package as a proper `.app` bundle

`swift build` only produces an executable, not a `.app`. To make a distributable Mac app:

- Add `ControllerRemap/Info.plist` with `CFBundleIdentifier`, `CFBundleName`, `CFBundleVersion`, `NSHumanReadableCopyright`.
- Decide Dock vs menu-bar: add `LSUIElement = true` to `Info.plist` to hide from the Dock and run in the background (good for a utility like this).
- Add an app icon (`.icns` or `Assets.xcassets`).
- Either use `swift package generate-xcodeproj` and build/archive in Xcode, or write a script that assembles `ControllerRemap.app/Contents/MacOS`, `Contents/Info.plist`, and `Contents/Resources`.

### 4. Signing & entitlements

- Create `ControllerRemap/ControllerRemap.entitlements` (start minimal; Accessibility is requested at runtime, not via entitlement).
- Sign the bundle (ad-hoc for personal use; Developer ID for distribution).
- Notarization is required for distribution outside the App Store on modern macOS.

### 5. UX polish

- Reflect gyro/touchpad active state in the status label.
- Persist sensitivity and toggles with `UserDefaults`.
- Add a Quit menu item (the window currently has no menu bar).
- Consider a menu-bar-only interface (`LSUIElement`) so it stays out of the way.

### 6. Test matrix

- PS4 controller over USB vs Bluetooth
- Gyro on / Touchpad on / both on
- Sensitivity low vs high
- Cursor at screen edges (clamping already exists)
- Multiple controllers connected (confirm intended behavior)

## Files to create next

1. `NEXT_STEPS.md` — this file
2. `ControllerRemap/Info.plist` — bundle metadata (`LSUIElement`, bundle ID, version, icon)
3. `ControllerRemap/ControllerRemap.entitlements` — app entitlements
4. `ControllerRemap/Assets.xcassets` or `ControllerRemap.icns` — app icon

## Build commands to remember

```bash
swift build                  # debug build
swift build -c release       # release build
swift run                    # build + run
swift package generate-xcodeproj   # Xcode project for signing/entitlements/UI editing
```
