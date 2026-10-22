import AppKit
import CoreGraphics

/// Converts controller input deltas into mouse movement by warping the
/// system cursor. Uses absolute positioning (cursor position + delta).
final class MouseMover {
    private var position: CGPoint

    init() {
        position = Self.readCurrentPosition()
    }

    private static func readCurrentPosition() -> CGPoint {
        // NSEvent.mouseLocation returns the current cursor position in screen coordinates.
        let location = NSEvent.mouseLocation
        return CGPoint(x: location.x, y: location.y)
    }

    /// Queues a mouse movement by the given delta (in points).
    func moveBy(delta: CGPoint) {
        var newPosition = position
        newPosition.x += delta.x
        newPosition.y += delta.y

        // Clamp to the main screen.
        if let screenFrame = NSScreen.main?.frame {
            newPosition.x = min(max(newPosition.x, 0), screenFrame.width)
            newPosition.y = min(max(newPosition.y, 0), screenFrame.height)
        }

        position = newPosition
        CGWarpMouseCursorPosition(newPosition)
    }
}
