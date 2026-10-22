import Foundation
import CoreGraphics

/// Reads PS4 controller input via raw IOKit/HID reports and translates
/// gyro / touchpad input into mouse movement.
///
/// Uses IOKit/HID because macOS GameController framework does NOT expose
/// PS4 gyro, face buttons, or touchpad data.
final class ControllerManager {
    // MARK: - User settings

    /// Remap mode: which controller input drives the mouse.
    enum RemapMode {
        case off
        case gyro
        case touchpad
        case both
    }

    var mode: RemapMode = .gyro
    var sensitivity: CGFloat = 1.0
    var deadzone: CGFloat = 0.05
    var invertY: Bool = false
    var invertX: Bool = false

    // MARK: - Debug mode

    /// When true, logs every HID byte and tracks changes for mapping verification.
    var debugMode: Bool = true

    // MARK: - Activity exposure (for UI feedback)

    /// True if any gyro input was received this tick.
    private(set) var gyroActive = false
    /// True if any touchpad input was received this tick.
    private(set) var touchpadActive = false
    /// True if the mouse cursor was moved this tick.
    private(set) var mouseMoved = false
    /// Last delta applied to the mouse cursor (points).
    private(set) var lastMouseDelta: CGPoint = .zero
    /// Last gyro-derived delta (points).
    private(set) var lastGyroDelta: CGPoint = .zero
    /// Last touchpad-derived delta (points).
    private(set) var lastTouchpadDelta: CGPoint = .zero

    // MARK: - Button debug exposure

    /// True if the X (cross) button is currently pressed.
    private(set) var buttonXPressed = false
    /// True if Circle button is currently pressed.
    private(set) var buttonCirclePressed = false
    /// True if Square button is currently pressed.
    private(set) var buttonSquarePressed = false
    /// True if Triangle button is currently pressed.
    private(set) var buttonTrianglePressed = false
    /// True if L1 button is currently pressed.
    private(set) var buttonL1Pressed = false
    /// True if R1 button is currently pressed.
    private(set) var buttonR1Pressed = false
    /// True if L2 button is currently pressed.
    private(set) var buttonL2Pressed = false
    /// True if R2 button is currently pressed.
    private(set) var buttonR2Pressed = false
    /// True if D-pad up is currently pressed.
    private(set) var buttonDpadUpPressed = false
    /// True if D-pad down is currently pressed.
    private(set) var buttonDpadDownPressed = false
    /// True if D-pad left is currently pressed.
    private(set) var buttonDpadLeftPressed = false
    /// True if D-pad right is currently pressed.
    private(set) var buttonDpadRightPressed = false

    /// True if PS button is pressed.
    private(set) var buttonPSPressed = false
    /// True if Touchpad click is pressed.
    private(set) var buttonTouchpadPressed = false
    /// True if Share button is pressed.
    private(set) var buttonSharePressed = false    /// True if Options button is pressed.
    private(set) var buttonOptionsPressed = false

    /// Last gyro rotation rate (raw int16 values).
    private(set) var lastGyroRate: SIMD3<Double> = .zero
    /// Last touchpad position (normalized 0-1).
    private(set) var lastTouchpadPosition: CGPoint = .zero

    // True if a DS4 controller is currently connected via HID.
    var isControllerConnected: Bool {
        hidReader.isConnected
    }

    // MARK: - Debug: byte change tracking

    /// Last raw byte values for change detection.
    private var lastRawBytes: [UInt8] = []
    /// Whether debug mode has printed the button test instructions.
    private var debugInstructionsPrinted = false

    // MARK: - State

    private let mouseMover = MouseMover()
    private let hidReader = HidControllerReader.shared

    // Gyro integration state.
    private var lastGyroTimestamp: CFTimeInterval = 0

    // Touchpad state.
    private var touchpadActiveTracking = false
    private var previousTouchpadPosition: CGPoint = .zero

    // MARK: - Debug logging

    private func debugLog(_ message: String) {
        guard debugMode else { return }
        let timestamp = String(format: "[%010.3f]", CFAbsoluteTimeGetCurrent())
        print("\(timestamp) ControllerRemap: \(message)")
    }

    // MARK: - Initialization

    init() {
        hidReader.onReport = { [weak self] report in
            self?.handleDS4Report(report)
        }
        hidReader.start()
        debugLog("ControllerManager initialized, HID reader started")
        debugLog("DEBUG MODE: Press each button when prompted to verify mapping")
    }

    deinit {
        hidReader.stop()
    }

    // MARK: - Public

    /// Called each frame (60 FPS) from the app's tick loop.
    func tick() {
        // Reset per-frame activity flags.
        gyroActive = false
        touchpadActive = false
        mouseMoved = false
        lastMouseDelta = .zero
        lastGyroDelta = .zero
        lastTouchpadDelta = .zero

        let now = CFAbsoluteTimeGetCurrent()

        // ---- Gyro integration ----
        if mode == .gyro || mode == .both {
            applyGyroIntegration(now: now)
        }

        // ---- Touchpad integration ----
        if mode == .touchpad || mode == .both {
            applyTouchpadIntegration(now: now)
        }
    }

    /// Set callback for controller connection/disconnection events.
    func onControllerConnectedChanged(_ callback: @escaping (Bool) -> Void) {
        hidReader.onControllerConnected = callback
    }

    // MARK: - HID report handler

    private func handleDS4Report(_ report: DS4Report) {
        // ---- Debug: log raw bytes on first few reports ----
        if debugMode && lastRawBytes.isEmpty {
            debugLog("=== FIRST REPORT RAW BYTES ===")
            for (i, byte) in report.rawBytes.enumerated() {
                debugLog("  byte[\(i)] = 0x\(String(byte, radix: 16).uppercased()) (\(byte))")
            }
            debugLog("=== END FIRST REPORT ===")
            printDebugInstructions()
        }

        // ---- Debug: detect byte changes ----
        if debugMode {
            detectByteChanges(report.rawBytes)
        }
        lastRawBytes = report.rawBytes

        debugLog("DS4 report: buttons=cross=\(report.buttons.cross) circle=\(report.buttons.circle) square=\(report.buttons.square) triangle=\(report.buttons.triangle) L1=\(report.buttons.l1) R1=\(report.buttons.r1) L2=\(report.buttons.l2Button) R2=\(report.buttons.r2Button) dpad=(U:\(report.buttons.dpadUp) D:\(report.buttons.dpadDown) L:\(report.buttons.dpadLeft) R:\(report.buttons.dpadRight))")

        debugLog("DS4 motion: gyro=(x:\(String(format: "%.1f", report.motion.gyroX)) y:\(String(format: "%.1f", report.motion.gyroY)) z:\(String(format: "%.1f", report.motion.gyroZ))) accel=(x:\(String(format: "%.1f", report.motion.accelX)) y:\(String(format: "%.1f", report.motion.accelY)) z:\(String(format: "%.1f", report.motion.accelZ)))")

        debugLog("DS4 touchpad: finger0 x=\(report.touchpad.finger0X) y=\(report.touchpad.finger0Y) active=\(report.touchpad.finger0Active)")

        // ---- Update button states on main thread (UI updates) ----
        DispatchQueue.main.async {
            self.updateButtonState(name: "Cross(X)", pressed: report.buttons.cross, state: &self.buttonXPressed)
            self.updateButtonState(name: "Circle(O)", pressed: report.buttons.circle, state: &self.buttonCirclePressed)
            self.updateButtonState(name: "Square(□)", pressed: report.buttons.square, state: &self.buttonSquarePressed)
            self.updateButtonState(name: "Triangle(△)", pressed: report.buttons.triangle, state: &self.buttonTrianglePressed)
            self.updateButtonState(name: "L1", pressed: report.buttons.l1, state: &self.buttonL1Pressed)
            self.updateButtonState(name: "R1", pressed: report.buttons.r1, state: &self.buttonR1Pressed)
            self.updateButtonState(name: "L2", pressed: report.buttons.l2Button, state: &self.buttonL2Pressed)
            self.updateButtonState(name: "R2", pressed: report.buttons.r2Button, state: &self.buttonR2Pressed)
            self.updateButtonState(name: "PS", pressed: report.buttons.ps, state: &self.buttonPSPressed)
            self.updateButtonState(name: "Touchpad Click", pressed: report.buttons.touchpadButton, state: &self.buttonTouchpadPressed)
            self.updateButtonState(name: "Share", pressed: report.buttons.share, state: &self.buttonSharePressed)
            self.updateButtonState(name: "Options", pressed: report.buttons.options, state: &self.buttonOptionsPressed)
            self.updateButtonState(name: "D-pad Up", pressed: report.buttons.dpadUp, state: &self.buttonDpadUpPressed)
            self.updateButtonState(name: "D-pad Down", pressed: report.buttons.dpadDown, state: &self.buttonDpadDownPressed)
            self.updateButtonState(name: "D-pad Left", pressed: report.buttons.dpadLeft, state: &self.buttonDpadLeftPressed)
            self.updateButtonState(name: "D-pad Right", pressed: report.buttons.dpadRight, state: &self.buttonDpadRightPressed)

            // ---- Store latest gyro rate ----
            self.lastGyroRate = SIMD3<Double>(report.motion.gyroX, report.motion.gyroY, report.motion.gyroZ)

            // ---- Store latest touchpad position (normalize 0-1919, 0-942 to 0-1) ----
            let tx = CGFloat(report.touchpad.finger0X) / 1919.0
            let ty = CGFloat(report.touchpad.finger0Y) / 942.0
            self.lastTouchpadPosition = CGPoint(x: tx, y: ty)

            // ---- Accumulate gyro delta ----
            if self.mode == .gyro || self.mode == .both {
                self.accumulateGyro(report: report)
            }

            // ---- Accumulate touchpad delta ----
            if self.mode == .touchpad || self.mode == .both {
                self.accumulateTouchpad(report: report)
            }
        }
    }

    /// Prints instructions for the user to press each button to verify mapping.
    private func printDebugInstructions() {
        guard debugMode && !debugInstructionsPrinted else { return }
        debugInstructionsPrinted = true

        print("")
        print("╔═══════════════════════════════════════════════════════════════╗")
        print("║  DEBUG MODE: Button Mapping Verification                      ║")
        print("╠═══════════════════════════════════════════════════════════════╣")
        print("║  Press each button ONE AT A TIME when prompted.               ║")
        print("║  Watch the console for byte changes.                          ║")
        print("║                                                               ║")
        print("║  1. Press Cross (X) button                                    ║")
        print("║  2. Press Circle (O) button                                   ║")
        print("║  3. Press Square (□) button                                   ║")
        print("║  4. Press Triangle (△) button                                 ║")
        print("║  5. Press L1 button                                           ║")
        print("║  6. Press R1 button                                           ║")
        print("║  7. Press Share button                                        ║")
        print("║  8. Press Options button                                      ║")
        print("║  9. Press D-pad Up                                            ║")
        print("║  10. Touch the touchpad                                       ║")
        print("║  11. Tilt the controller (gyro)                               ║")
        print("║                                                               ║")
        print("║  After each action, note which byte offset changed.           ║")
        print("╚═══════════════════════════════════════════════════════════════╝")
        print("")
    }

    /// Detects which bytes changed between reports and logs them.
    private func detectByteChanges(_ newBytes: [UInt8]) {
        guard lastRawBytes.count == newBytes.count else { return }

        var changedBytes: [(offset: Int, old: UInt8, new: UInt8)] = []
        for i in 0..<newBytes.count {
            if newBytes[i] != lastRawBytes[i] {
                changedBytes.append((i, lastRawBytes[i], newBytes[i]))
            }
        }

        if !changedBytes.isEmpty {
            let changes = changedBytes.map { "byte[\($0.offset)]: 0x\(String($0.old, radix: 16).uppercased()) → 0x\(String($0.new, radix: 16).uppercased())" }
                .joined(separator: ", ")
            debugLog("BYTE CHANGES: \(changes)")
        }
    }

    /// Logs a button press/release only when state changes.
    private func updateButtonState(name: String, pressed: Bool, state: inout Bool) {
        if pressed && !state {
            state = true
            debugLog("    button \(name) PRESSED")
        } else if !pressed && state {
            state = false
            debugLog("    button \(name) RELEASED")
        }
    }

    // MARK: - Gyro accumulation (called from HID callback)

    private func accumulateGyro(report: DS4Report) {
        let now = CFAbsoluteTimeGetCurrent()
        let rateX = report.motion.gyroX
        let rateY = report.motion.gyroY

        debugLog("    gyro: raw rate=(x:\(String(format: "%.1f", rateX)) y:\(String(format: "%.1f", rateY)) z:\(String(format: "%.1f", report.motion.gyroZ)))")

        // Apply deadzone to raw gyro values.
        var x = rateX
        var y = rateY
        if abs(x) < Double(deadzone) { x = 0 }
        if abs(y) < Double(deadzone) { y = 0 }

        if x == 0 && y == 0 {
            if lastGyroTimestamp == 0 {
                lastGyroTimestamp = now
            }
            return
        }

        let dt = now - lastGyroTimestamp

        // First report: initialize timestamp and wait for next frame.
        if lastGyroTimestamp == 0 {
            lastGyroTimestamp = now
            return
        }
        guard dt > 0 else { return }
        lastGyroTimestamp = now

        // Convert gyro rate (raw int16) to pixels.
        // DS4 gyro raw values are typically in range ±4000+ per degree/sec.
        let pixelsPerUnit: CGFloat = 0.1
        var dx = CGFloat(rateY) * CGFloat(dt) * pixelsPerUnit * sensitivity
        var dy = CGFloat(rateX) * CGFloat(dt) * pixelsPerUnit * sensitivity

        // Apply axis inversion (gyro only).
        if invertX { dx = -dx }
        if invertY { dy = -dy }

        lastGyroDelta = CGPoint(x: dx, y: dy)

        if abs(dx) > 0.5 || abs(dy) > 0.5 {
            gyroActive = true
            mouseMoved = true
            lastMouseDelta.x += dx
            lastMouseDelta.y += dy
            debugLog("    gyro: MOVING dx=\(String(format: "%.2f", dx)) dy=\(String(format: "%.2f", dy)) dt=\(String(format: "%.4f", dt))")
        }
    }

    /// Integrates accumulated gyro delta and moves the cursor.
    private func applyGyroIntegration(now: CFTimeInterval) {
        let delta = lastGyroDelta
        if abs(delta.x) > 0.5 || abs(delta.y) > 0.5 {
            mouseMover.moveBy(delta: delta)
        }
    }

    // MARK: - Touchpad accumulation (called from HID callback)

    private func accumulateTouchpad(report: DS4Report) {
        let x = report.touchpad.finger0X
        let y = report.touchpad.finger0Y
        let active = report.touchpad.finger0Active

        debugLog("    touchpad: raw x=\(x) y=\(y) active=\(active)")

        guard active else {
            if touchpadActiveTracking {
                touchpadActiveTracking = false
                previousTouchpadPosition = .zero
                debugLog("    touchpad: released")
            }
            return
        }

        // Normalize to 0-1 range.
        let currentPos = CGPoint(
            x: CGFloat(x) / 1919.0,
            y: CGFloat(y) / 942.0
        )

        if !touchpadActiveTracking {
            touchpadActiveTracking = true
            previousTouchpadPosition = currentPos
            debugLog("    touchpad: first touch, initializing")
            return
        }

        var deltaX = currentPos.x - previousTouchpadPosition.x
        var deltaY = currentPos.y - previousTouchpadPosition.y
        previousTouchpadPosition = currentPos

        // Apply deadzone.
        if abs(deltaX) < deadzone { deltaX = 0 }
        if abs(deltaY) < deadzone { deltaY = 0 }

        let pixelsPerUnit: CGFloat = 500.0
        let dx = deltaX * pixelsPerUnit * sensitivity
        var dy = deltaY * pixelsPerUnit * sensitivity

        lastTouchpadDelta = CGPoint(x: dx, y: dy)

        if abs(dx) > 0.5 || abs(dy) > 0.5 {
            touchpadActive = true
            mouseMoved = true
            lastMouseDelta.x += dx
            lastMouseDelta.y += dy
            debugLog("    touchpad: MOVING dx=\(String(format: "%.2f", dx)) dy=\(String(format: "%.2f", dy))")
        }
    }

    /// Integrates accumulated touchpad delta and moves the cursor.
    private func applyTouchpadIntegration(now: CFTimeInterval) {
        let delta = lastTouchpadDelta
        if abs(delta.x) > 0.5 || abs(delta.y) > 0.5 {
            mouseMover.moveBy(delta: delta)
        }
    }
}
