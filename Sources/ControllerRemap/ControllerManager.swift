import Foundation
import CoreGraphics

/// Reads PS4 controller input via raw IOKit/HID reports and translates
/// gyro / touchpad input into mouse movement.
///
/// macOS's GameController framework does NOT expose PS4 gyro, face buttons,
/// or touchpad data. We bypass it entirely and read raw HID input reports
/// directly from the DualShock 4 over USB or Bluetooth.
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

    /// Last gyro rotation rate (radians/sec equivalent).
    private(set) var lastGyroRate: SIMD3<Double> = .zero
    /// Last touchpad position (0-1 range).
    private(set) var lastTouchpadPosition: CGPoint = .zero

    // MARK: - State

    private let mouseMover = MouseMover()
    private let hidReader = HidControllerReader.shared

    // Gyro integration state (per-controller).
    private var lastGyroTimestamp: CFTimeInterval = 0

    // Touchpad state.
    private var touchpadActiveTracking = false

    // MARK: - Debug logging

    private var debugEnabled = true

    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
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
    }

    deinit {
        hidReader.stop()
    }

    // MARK: - Public

    /// Called each frame (60 FPS) from the app's tick loop.
    /// Integrates accumulated gyro/touchpad deltas and moves the cursor.
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

    // MARK: - HID report handler

    private func handleDS4Report(_ report: DS4Report) {
        debugLog("DS4 report: buttons=cross=\(report.buttons.cross) circle=\(report.buttons.circle) square=\(report.buttons.square) triangle=\(report.buttons.triangle) L1=\(report.buttons.l1) R1=\(report.buttons.r1) L2=\(report.buttons.l2Button) R2=\(report.buttons.r2Button) dpad=(U:\(report.buttons.dpadUp) D:\(report.buttons.dpadDown) L:\(report.buttons.dpadLeft) R:\(report.buttons.dpadRight))")

        debugLog("DS4 motion: gyro=(x:\(String(format: "%.1f", report.motion.gyroX)) y:\(String(format: "%.1f", report.motion.gyroY)) z:\(String(format: "%.1f", report.motion.gyroZ))) accel=(x:\(String(format: "%.1f", report.motion.accelX)) y:\(String(format: "%.1f", report.motion.accelY)) z:\(String(format: "%.1f", report.motion.accelZ)))")

        debugLog("DS4 touchpad: x=\(report.touchpad.finger0X) y=\(report.touchpad.finger0Y) active=\(report.touchpad.finger0Active)")

        // ---- Update button states ----
        updateButtonState(name: "Cross(X)", pressed: report.buttons.cross, state: &buttonXPressed)
        updateButtonState(name: "Circle(O)", pressed: report.buttons.circle, state: &buttonCirclePressed)
        updateButtonState(name: "Square(□)", pressed: report.buttons.square, state: &buttonSquarePressed)
        updateButtonState(name: "Triangle(△)", pressed: report.buttons.triangle, state: &buttonTrianglePressed)
        updateButtonState(name: "L1", pressed: report.buttons.l1, state: &buttonL1Pressed)
        updateButtonState(name: "R1", pressed: report.buttons.r1, state: &buttonR1Pressed)
        updateButtonState(name: "L2", pressed: report.buttons.l2Button, state: &buttonL2Pressed)
        updateButtonState(name: "R2", pressed: report.buttons.r2Button, state: &buttonR2Pressed)
        updateButtonState(name: "D-pad Up", pressed: report.buttons.dpadUp, state: &buttonDpadUpPressed)
        updateButtonState(name: "D-pad Down", pressed: report.buttons.dpadDown, state: &buttonDpadDownPressed)
        updateButtonState(name: "D-pad Left", pressed: report.buttons.dpadLeft, state: &buttonDpadLeftPressed)
        updateButtonState(name: "D-pad Right", pressed: report.buttons.dpadRight, state: &buttonDpadRightPressed)

        // ---- Store latest gyro rate ----
        lastGyroRate = SIMD3<Double>(report.motion.gyroX, report.motion.gyroY, report.motion.gyroZ)

        // ---- Store latest touchpad position ----
        lastTouchpadPosition = CGPoint(x: CGFloat(report.touchpad.finger0X), y: CGFloat(report.touchpad.finger0Y))

        // ---- Accumulate gyro delta ----
        if mode == .gyro || mode == .both {
            accumulateGyro(report: report)
        }

        // ---- Accumulate touchpad delta ----
        if mode == .touchpad || mode == .both {
            accumulateTouchpad(report: report)
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
        let rateZ = report.motion.gyroZ

        debugLog("    gyro: raw rate=(x:\(String(format: "%.1f", rateX)) y:\(String(format: "%.1f", rateY)) z:\(String(format: "%.1f", rateZ)))")

        // Apply deadzone to raw gyro values.
        var x = rateX
        var y = rateY
        if abs(x) < Double(deadzone) { x = 0 }
        if abs(y) < Double(deadzone) { y = 0 }

        if x == 0 && y == 0 {
            // No meaningful motion; just update timestamp.
            if lastGyroTimestamp == 0 {
                lastGyroTimestamp = now
            }
            return
        }

        let dt = now - lastGyroTimestamp
        guard dt > 0 else {
            if lastGyroTimestamp == 0 {
                lastGyroTimestamp = now
            }
            return
        }
        lastGyroTimestamp = now

        // Convert gyro rate (degrees/sec) to pixels.
        // DS4 gyro is typically in degrees/sec * 1000 (raw int16).
        // Scale factor: divide raw by 1000 to get degrees/sec, then to pixels.
        let degreesPerSecX = x / 1000.0
        let degreesPerSecY = y / 1000.0

        let pixelsPerDegree: CGFloat = 15.0
        let dx = CGFloat(degreesPerSecY) * CGFloat(dt) * pixelsPerDegree * sensitivity
        var dy = CGFloat(degreesPerSecX) * CGFloat(dt) * pixelsPerDegree * sensitivity

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
            // Touchpad released; reset tracking.
            if touchpadActiveTracking {
                touchpadActiveTracking = false
                lastTouchpadPosition = .zero
                debugLog("    touchpad: released")
            }
            return
        }

        if !touchpadActiveTracking {
            // First touch: initialize position, wait for next frame.
            touchpadActiveTracking = true
            lastTouchpadPosition = CGPoint(x: CGFloat(x), y: CGFloat(y))
            debugLog("    touchpad: first touch, initializing")
            return
        }

        let currentPos = CGPoint(x: CGFloat(x), y: CGFloat(y))
        var deltaX = currentPos.x - lastTouchpadPosition.x
        var deltaY = currentPos.y - lastTouchpadPosition.y
        lastTouchpadPosition = currentPos

        // Apply deadzone.
        if abs(deltaX) < deadzone { deltaX = 0 }
        if abs(deltaY) < deadzone { deltaY = 0 }

        let pixelsPerUnit: CGFloat = 5.0
        let dx = deltaX * pixelsPerUnit * sensitivity
        var dy = deltaY * pixelsPerUnit * sensitivity

        if invertY { dy = -dy }

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
