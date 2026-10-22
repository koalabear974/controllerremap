import GameController
import CoreFoundation
import CoreGraphics

/// Reads controller state and translates gyro / touchpad input into mouse movement.
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

    /// Last gyro rotation rate (radians/sec).
    private(set) var lastGyroRate: SIMD3<Double> = .zero
    /// Last touchpad position (0-1 range).
    private(set) var lastTouchpadPosition: CGPoint = .zero

    // MARK: - Debug logging

    private var debugEnabled = true

    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
        let timestamp = String(format: "[%010.3f]", CACurrentMediaTime())
        print("\(timestamp) ControllerRemap: \(message)")
    }

    // MARK: - State

    private let mouseMover = MouseMover()
    private var gyroStates: [ObjectIdentifier: GyroState] = [:]
    private var touchpadStates: [ObjectIdentifier: [String: TouchpadState]] = [:]

    private struct GyroState {
        var lastTime: CFTimeInterval = 0
    }

    private struct TouchpadState {
        var lastX: CGFloat = 0
        var lastY: CGFloat = 0
    }

    // MARK: - Public

    /// Polls all connected controllers and translates input to mouse movement.
    func tick() {
        // Reset activity flags each frame.
        gyroActive = false
        touchpadActive = false
        mouseMoved = false
        lastMouseDelta = .zero
        lastGyroDelta = .zero
        lastTouchpadDelta = .zero

        // Reset button states.
        buttonXPressed = false
        buttonCirclePressed = false
        buttonSquarePressed = false
        buttonTrianglePressed = false

        let now = CACurrentMediaTime()
        let controllers = GCController.controllers()
        debugLog("tick: \(controllers.count) controller(s) connected")

        for controller in controllers {
            let id = ObjectIdentifier(controller)
            debugLog("  controller: \(controller.vendorName ?? "Unknown")")

            // Read buttons for debug (always, regardless of mode).
            readButtons(controller)

            switch mode {
            case .off:
                break
            case .gyro:
                updateGyro(controller, stateKey: id, at: now)
            case .touchpad:
                updateTouchpad(controller, stateKey: id)
            case .both:
                updateGyro(controller, stateKey: id, at: now)
                updateTouchpad(controller, stateKey: id)
            }
        }
    }

    /// Reads face buttons for debug display.
    /// PS4 mapping: Cross=A, Circle=B, Square=X, Triangle=Y
    private func readButtons(_ controller: GCController) {
        guard let extendedGamepad = controller.extendedGamepad else { return }

        // Cross / X button -> buttonA.
        if extendedGamepad.buttonA.isPressed {
            buttonXPressed = true
            debugLog("    buttonCross(A) PRESSED")
        }
        // Circle / O button -> buttonB.
        if extendedGamepad.buttonB.isPressed {
            buttonCirclePressed = true
            debugLog("    buttonCircle(B) PRESSED")
        }
        // Square / □ button -> buttonX.
        if extendedGamepad.buttonX.isPressed {
            buttonSquarePressed = true
            debugLog("    buttonSquare(X) PRESSED")
        }
        // Triangle / △ button -> buttonY.
        if extendedGamepad.buttonY.isPressed {
            buttonTrianglePressed = true
            debugLog("    buttonTriangle(Y) PRESSED")
        }
    }

    // MARK: - Gyro -> mouse

    private func updateGyro(_ controller: GCController, stateKey: ObjectIdentifier, at now: CFTimeInterval) {
        guard let motion = controller.motion else {
            debugLog("    gyro: no motion available")
            return
        }
        motion.sensorsActive = true
        guard motion.hasRotationRate else {
            debugLog("    gyro: hasRotationRate = false")
            return
        }

        let rate = motion.rotationRate
        lastGyroRate = SIMD3<Double>(rate.x, rate.y, rate.z)

        var state = gyroStates[stateKey] ?? GyroState()
        let dt = now - state.lastTime

        // First tick: initialize state and wait for next frame.
        if state.lastTime == 0 {
            state.lastTime = now
            gyroStates[stateKey] = state
            debugLog("    gyro: first tick, initializing state")
            return
        }
        guard dt > 0 else {
            debugLog("    gyro: dt <= 0 (\(dt))")
            return
        }

        debugLog("    gyro: rate=(x:\(String(format: "%.3f", rate.x)), y:\(String(format: "%.3f", rate.y)), z:\(String(format: "%.3f", rate.z))) dt=\(String(format: "%.4f", dt))")

        // Apply deadzone to rotation rate (radians/sec).
        var pitch = rate.x
        var yaw = rate.y
        if abs(pitch) < Double(deadzone) { pitch = 0 }
        if abs(yaw) < Double(deadzone) { yaw = 0 }

        // Convert angle delta (radians) to pixels.
        let pixelsPerRadian = 300.0
        let dx = CGFloat(yaw) * CGFloat(dt) * pixelsPerRadian * sensitivity
        var dy = CGFloat(pitch) * CGFloat(dt) * pixelsPerRadian * sensitivity

        if invertY { dy = -dy }

        let delta = CGPoint(x: dx, y: dy)
        lastGyroDelta = delta

        // Only count as active if the delta is meaningful.
        if abs(dx) > 0.5 || abs(dy) > 0.5 {
            gyroActive = true
            mouseMoved = true
            lastMouseDelta.x += dx
            lastMouseDelta.y += dy
            debugLog("    gyro: MOVING dx=\(String(format: "%.2f", dx)) dy=\(String(format: "%.2f", dy))")
            mouseMover.moveBy(delta: delta)
        }

        // Store last time for next frame.
        state.lastTime = now
        gyroStates[stateKey] = state
    }

    // MARK: - Touchpad -> mouse

    private func updateTouchpad(_ controller: GCController, stateKey: ObjectIdentifier) {
        guard let extendedGamepad = controller.extendedGamepad else {
            debugLog("    touchpad: no extendedGamepad")
            return
        }

        let touchpads = extendedGamepad.touchpads
        for (alias, touchpad) in touchpads {
            let axis = touchpad.touchSurface
            let x = axis.xAxis.value
            let y = axis.yAxis.value
            lastTouchpadPosition = CGPoint(x: CGFloat(x), y: CGFloat(y))
            let touchState = touchpad.touchState

            debugLog("    touchpad[\(alias)]: state=\(touchState) x=\(String(format: "%.3f", x)) y=\(String(format: "%.3f", y))")

            if touchState == .moving || touchState == .down {
                var state = touchpadStates[stateKey]?[alias] ?? TouchpadState()
                var deltaX = CGFloat(x) - state.lastX
                var deltaY = CGFloat(y) - state.lastY
                state.lastX = CGFloat(x)
                state.lastY = CGFloat(y)

                // Apply deadzone.
                if abs(deltaX) < deadzone { deltaX = 0 }
                if abs(deltaY) < deadzone { deltaY = 0 }

                let pixelsPerUnit = 200.0
                let dx = deltaX * pixelsPerUnit * sensitivity
                var dy = deltaY * pixelsPerUnit * sensitivity

                if invertY { dy = -dy }

                let delta = CGPoint(x: dx, y: dy)
                lastTouchpadDelta = delta

                if abs(dx) > 0.5 || abs(dy) > 0.5 {
                    touchpadActive = true
                    mouseMoved = true
                    lastMouseDelta.x += dx
                    lastMouseDelta.y += dy
                    debugLog("    touchpad: MOVING dx=\(String(format: "%.2f", dx)) dy=\(String(format: "%.2f", dy))")
                    mouseMover.moveBy(delta: delta)
                }

                if var states = touchpadStates[stateKey] {
                    states[alias] = state
                    touchpadStates[stateKey] = states
                } else {
                    touchpadStates[stateKey] = [alias: state]
                }
            } else {
                if var states = touchpadStates[stateKey] {
                    states[alias] = TouchpadState()
                    touchpadStates[stateKey] = states
                } else {
                    touchpadStates[stateKey] = [alias: TouchpadState()]
                }
            }
        }
    }
}
