# ControllerRemap

A simple macOS app that remaps PS4 controller input — specifically turning the **gyro** and/or **touchpad** into mouse movement — while leaving all other controller input (buttons, sticks, triggers) untouched.

## Features

- **Gyro → Mouse**: Tilt the controller to move the cursor
- **Touchpad → Mouse**: Slide your finger on the PS4 touchpad to move the cursor
- **Both**: Use gyro and touchpad simultaneously
- **Mode selector**: Off / Gyro / Touchpad / Both
- **Sensitivity slider**: Adjust mouse speed (0.1 – 3.0)
- **Deadzone slider**: Filter out controller drift / small tremors (0.0 – 0.3)
- **Invert Y axis**: Flip vertical mouse direction
- **Visual feedback**: Activity dots show when gyro, touchpad, or mouse movement is detected
- **Live delta readout**: See the exact pixel delta sent to the cursor each frame
- **Controller status**: Green/red dot shows whether a controller is connected
- **Accessibility check**: Shows whether cursor-control permission is granted

## Requirements

- macOS 11+
- A PS4 (DualShock 4) controller connected via USB or Bluetooth

## Building

```bash
git clone <this-repo>
cd controllerremap
swift build -c release
```

Or build the double-clickable `.app` bundle:

```bash
./build_app.sh
open ControllerRemap.app
```

## First launch (Accessibility permission)

The app moves the system cursor via `CGWarpMouseCursorPosition`, which macOS restricts. On first launch:

1. If the **Accessibility dot is red**, click **"Open Accessibility Settings"**
2. Add `ControllerRemap.app` in **System Settings → Privacy & Security → Accessibility**
3. Enable it and restart the app

## Project structure

```
Package.swift          # Swift Package Manager manifest
Sources/ControllerRemap/
  main.swift           # App entry point
  ControllerRemapApp.swift   # UI (status dots, mode selector, sliders, live deltas)
  ControllerManager.swift    # Gyro/touchpad → mouse logic
  MouseMover.swift           # Cursor warping via CGWarpMouseCursorPosition
  Info.plist             # App bundle metadata
build_app.sh             # Builds release + assembles .app bundle
NEXT_STEPS.md            # Remaining work items
```

## License

MIT