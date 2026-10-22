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

        let now = CACurrentMediaTime()
        let controllers = GCController.controllers()
        for controller in controllers {
            let id = ObjectIdentifier(controller)

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

    // MARK: - Gyro -> mouse

    private func updateGyro(_ controller: GCController, stateKey: ObjectIdentifier, at now: CFTimeInterval) {
        guard let motion = controller.motion else { return }
        motion.sensorsActive = true
        guard motion.hasRotationRate else { return }

        let rate = motion.rotationRate
        let dt = now - (gyroStates[stateKey]?.lastTime ?? now)
        guard dt > 0 else { return }

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
            mouseMover.moveBy(delta: delta)
        }

        // Store last time for next frame.
        var state = gyroStates[stateKey] ?? GyroState()
        state.lastTime = now
        gyroStates[stateKey] = state
    }

    // MARK: - Touchpad -> mouse

    private func updateTouchpad(_ controller: GCController, stateKey: ObjectIdentifier) {
        guard let extendedGamepad = controller.extendedGamepad else { return }

        let touchpads = extendedGamepad.touchpads
        for (alias, touchpad) in touchpads {
            let axis = touchpad.touchSurface
            let x = axis.xAxis.value
            let y = axis.yAxis.value

            var state = touchpadStates[stateKey]?[alias] ?? TouchpadState()
            let touchState = touchpad.touchState

            if touchState == .moving || touchState == .down {
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
