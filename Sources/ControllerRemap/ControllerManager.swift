import Foundation
import CoreGraphics

/// Reads PS4 controller input via raw IOKit/HID reports and translates
/// gyro / touchpad input into mouse movement.
final class ControllerManager {
    // MARK: - User settings

    enum RemapMode {
        case off
        case gyro
        case touchpad
        case both
    }

    var mode: RemapMode = .gyro
    var sensitivity: CGFloat = 1.0
    var deadzone: CGFloat = 0.1
    var invertY: Bool = false
    var invertX: Bool = false

    /// When true, gyro only moves mouse while touchpad is touched.
    var gyroRequiresTouchpad: Bool = true

    // MARK: - Activity exposure

    private(set) var gyroActive = false
    private(set) var touchpadActive = false
    private(set) var mouseMoved = false
    private(set) var lastMouseDelta: CGPoint = .zero
    private(set) var lastGyroDelta: CGPoint = .zero
    private(set) var lastTouchpadDelta: CGPoint = .zero

    // MARK: - Button debug exposure

    private(set) var buttonXPressed = false
    private(set) var buttonCirclePressed = false
    private(set) var buttonSquarePressed = false
    private(set) var buttonTrianglePressed = false
    private(set) var buttonL1Pressed = false
    private(set) var buttonR1Pressed = false
    private(set) var buttonL2Pressed = false
    private(set) var buttonR2Pressed = false
    private(set) var buttonDpadUpPressed = false
    private(set) var buttonDpadDownPressed = false
    private(set) var buttonDpadLeftPressed = false
    private(set) var buttonDpadRightPressed = false
    private(set) var buttonPSPressed = false
    private(set) var buttonTouchpadPressed = false  // Touchpad click (right mouse click)
    private(set) var buttonSharePressed = false
    private(set) var buttonOptionsPressed = false

    private(set) var lastGyroRate: SIMD3<Double> = .zero
    private(set) var lastTouchpadPosition: CGPoint = .zero

    var isControllerConnected: Bool {
        hidReader.isConnected
    }

    private(set) var gyroActivelyRemapping: Bool = false

    var debugMode: Bool = true

    private var lastRawBytes: [UInt8] = []
    private var debugInstructionsPrinted = false

    // MARK: - State

    private let mouseMover = MouseMover()
    private let hidReader = HidControllerReader.shared

    // Gyro integration state.
    private var lastGyroTimestamp: CFTimeInterval = 0
    /// Center gyro reading captured when touchpad is first touched.
    private var gyroCenterX: Double = 0
    private var gyroCenterY: Double = 0
    /// Whether we have a valid center reading.
    private var hasGyroCenter: Bool = false
    /// Drift compensation running average.
    private var driftCompX: Double = 0
    private var driftCompY: Double = 0
    private var stableFrameCount: Int = 0

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

    func tick() {
        gyroActive = false
        touchpadActive = false
        mouseMoved = false
        lastMouseDelta = .zero
        lastGyroDelta = .zero
        lastTouchpadDelta = .zero

        gyroActivelyRemapping = gyroRequiresTouchpad ? buttonTouchpadPressed : true
    }

    func onControllerConnectedChanged(_ callback: @escaping (Bool) -> Void) {
        hidReader.onControllerConnected = callback
    }

    // MARK: - HID report handler

    private func handleDS4Report(_ report: DS4Report) {
        if debugMode && lastRawBytes.isEmpty {
            debugLog("=== FIRST REPORT RAW BYTES ===")
            for (i, byte) in report.rawBytes.enumerated() {
                debugLog("  byte[\(i)] = 0x\(String(byte, radix: 16).uppercased()) (\(byte))")
            }
            debugLog("=== END FIRST REPORT ===")
            printDebugInstructions()
        }

        if debugMode {
            detectByteChanges(report.rawBytes)
        }
        lastRawBytes = report.rawBytes

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

            self.lastGyroRate = SIMD3<Double>(report.motion.gyroX, report.motion.gyroY, report.motion.gyroZ)
            let tx = CGFloat(report.touchpad.finger0X) / 1919.0
            let ty = CGFloat(report.touchpad.finger0Y) / 942.0
            self.lastTouchpadPosition = CGPoint(x: tx, y: ty)

            if self.mode == .gyro || self.mode == .both {
                self.accumulateGyro(report: report)
            }
            if self.mode == .touchpad || self.mode == .both {
                self.accumulateTouchpad(report: report)
            }
        }
    }

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

    private func updateButtonState(name: String, pressed: Bool, state: inout Bool) {
        if pressed && !state {
            state = true
            debugLog("    button \(name) PRESSED")
        } else if !pressed && state {
            state = false
            debugLog("    button \(name) RELEASED")
        }
    }

    // MARK: - Gyro accumulation

    private func accumulateGyro(report: DS4Report) {
        // If gyro requires touchpad touch and touchpad is not touched, do not move mouse.
        if gyroRequiresTouchpad && !buttonTouchpadPressed {
            hasGyroCenter = false
            lastGyroTimestamp = 0
            gyroActivelyRemapping = false
            return
        }

        gyroActivelyRemapping = true

        let now = CFAbsoluteTimeGetCurrent()
        let rateX = report.motion.gyroX
        let rateY = report.motion.gyroY

        debugLog("    gyro: raw rate=(x:\(String(format: "%.1f", rateX)) y:\(String(format: "%.1f", rateY)) z:\(String(format: "%.1f", report.motion.gyroZ)))")

        // Capture center gyro reading on first touchpad touch.
        if !hasGyroCenter {
            gyroCenterX = rateX
            gyroCenterY = rateY
            lastGyroTimestamp = now
            hasGyroCenter = true
            driftCompX = rateX
            driftCompY = rateY
            driftSampleCount = 1
            stableFrameCount = 0
            debugLog("    gyro: center captured at X=\(rateX) Y=\(rateY)")
            return
        }

        // Calculate delta from center gyro reading.
        let deltaX = rateX - gyroCenterX
        let deltaY = rateY - gyroCenterY

        // Apply deadzone to raw gyro deltas.
        // Raw gyro values are in range ±4000+, so deadzone needs to be substantial.
        let gyroDeadzone = Double(deadzone) * 80.0
        var x = deltaX
        var y = deltaY
        if abs(x) < gyroDeadzone { x = 0 }
        if abs(y) < gyroDeadzone { y = 0 }

        // Drift compensation: if gyro is stable (small changes over several frames),
        // slowly update the center to absorb drift.
        let isStable = abs(deltaX) < gyroDeadzone * 0.5 && abs(deltaY) < gyroDeadzone * 0.5
        if isStable {
            stableFrameCount += 1
            // Slowly drift the center toward current reading (exponential moving average)
            driftCompX = driftCompX * 0.98 + rateX * 0.02
            driftCompY = driftCompY * 0.98 + rateY * 0.02
            driftSampleCount += 1
            // Re-center every 60 stable frames (~1 second at 60Hz)
            if stableFrameCount >= 60 {
                gyroCenterX = driftCompX
                gyroCenterY = driftCompY
                stableFrameCount = 0
                debugLog("    gyro: auto-recentered at X=\(String(format: "%.1f", gyroCenterX)) Y=\(String(format: "%.1f", gyroCenterY))")
            }
        } else {
            stableFrameCount = 0
        }

        if x == 0 && y == 0 {
            return
        }

        let dt = now - lastGyroTimestamp
        guard dt > 0 else { return }
        lastGyroTimestamp = now

        // Convert gyro rate delta (raw int16 units) to pixels.
        // DS4 gyro raw values are typically in range ±4000+ per degree/sec.
        let pixelsPerUnit: CGFloat = 0.1
        var dx = CGFloat(y) * CGFloat(dt) * pixelsPerUnit * sensitivity
        var dy = CGFloat(x) * CGFloat(dt) * pixelsPerUnit * sensitivity

        // Apply axis inversion (gyro only).
        if invertX { dx = -dx }
        if invertY { dy = -dy }

        lastGyroDelta = CGPoint(x: dx, y: dy)

        if abs(dx) > 0.5 || abs(dy) > 0.5 {
            gyroActive = true
            mouseMoved = true
            lastMouseDelta.x += dx
            lastMouseDelta.y += dy
            debugLog("    gyro: MOVING dx=\(String(format: "%.2f", dx)) dy=\(String(format: "%.2f", dy)) dt=\(String(format: "%.4f", dt)) centerX=\(gyroCenterX) centerY=\(gyroCenterY)")

            // Move mouse cursor immediately.
            mouseMover.moveBy(delta: CGPoint(x: dx, y: dy))
        }
    }

    private func applyGyroIntegration(now: CFTimeInterval) {
        // No-op: gyro movement applied directly in accumulateGyro(report:).
        // Kept for API compatibility.
    }

    // MARK: - Touchpad accumulation

    private func accumulateTouchpad(report: DS4Report) {
        let x = report.touchpad.finger0X
        let y = report.touchpad.finger0Y
        let active = report.touchpad.finger0Active

        debugLog("    touchpad: raw x=\(x) y=\(y) active=\(active)")

        guard active else {
            if touchpadActiveTracking {
                touchpadActiveTracking = false
                previousTouchpadPosition = .zero
            }
            return
        }

        let currentPos = CGPoint(
            x: CGFloat(x) / 1919.0,
            y: CGFloat(y) / 942.0
        )

        if !touchpadActiveTracking {
            touchpadActiveTracking = true
            previousTouchpadPosition = currentPos
            return
        }

        var deltaX = currentPos.x - previousTouchpadPosition.x
        var deltaY = currentPos.y - previousTouchpadPosition.y
        previousTouchpadPosition = currentPos

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

            // Move mouse cursor immediately.
            mouseMover.moveBy(delta: CGPoint(x: dx, y: dy))
        }
    }

    private func applyTouchpadIntegration(now: CFTimeInterval) {
        // No-op: touchpad movement applied directly in accumulateTouchpad(report:).
        // Kept for API compatibility.
    }
}
