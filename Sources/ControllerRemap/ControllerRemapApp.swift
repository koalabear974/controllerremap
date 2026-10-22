import AppKit
import GameController
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    private let manager = ControllerManager()

    // MARK: - UI

    private var statusDot: NSView!
    private var statusLabel: NSTextField!

    // System / security
    private var a11yDot: NSView!
    private var a11yLabel: NSTextField!
    private var a11yButton: NSButton!

    // Input activity
    private var gyroDotView: NSStackView!
    private var touchpadDotView: NSStackView!
    private var mouseDotView: NSStackView!
    private var deltaLabel: NSTextField!

    // Button debug
    private var buttonXDotView: NSStackView!
    private var buttonCircleDotView: NSStackView!
    private var buttonSquareDotView: NSStackView!
    private var buttonTriangleDotView: NSStackView!

    // Big X button press indicator
    private var xPressedLabel: NSTextField!

    // Gyro X-Y visualizer
    private var gyroVisualizerView: GyroVisualizerView!

    // Raw value readouts
    private var gyroRateLabel: NSTextField!
    private var touchpadLabel: NSTextField!

    // Controls
    private var modeSegment: NSSegmentedControl!
    private var sensitivitySlider: NSSlider!
    private var deadzoneSlider: NSSlider!
    private var invertYCheckbox: NSButton!

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("ControllerRemap: applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.regular)

        buildUI()
        print("ControllerRemap: buildUI done")

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GCControllerDidConnectNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatus()
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("GCControllerDidDisconnectNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatus()
        }

        refreshStatus()
    }

    // MARK: - UI building

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading

        // ---- Connection status row ----
        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY

        statusDot = NSView()
        statusDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 10).isActive = true
        statusDot.layer = CALayer()
        statusDot.layer?.cornerRadius = 5
        statusDot.wantsLayer = true
        updateStatusDot(connected: false)

        statusLabel = NSTextField(labelWithString: "No controller connected")
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        statusRow.addArrangedSubview(statusDot)
        statusRow.addArrangedSubview(statusLabel)

        // ---- Accessibility / security row ----
        let a11yRow = NSStackView()
        a11yRow.orientation = .horizontal
        a11yRow.spacing = 8
        a11yRow.alignment = .centerY

        a11yDot = NSView()
        a11yDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        a11yDot.heightAnchor.constraint(equalToConstant: 10).isActive = true
        a11yDot.layer = CALayer()
        a11yDot.layer?.cornerRadius = 5
        a11yDot.wantsLayer = true

        a11yLabel = NSTextField(labelWithString: "Checking Accessibility…")
        a11yLabel.font = NSFont.systemFont(ofSize: 12)
        a11yLabel.textColor = .secondaryLabelColor

        a11yButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibilitySettings))
        a11yButton.bezelStyle = .rounded
        a11yButton.controlSize = .small

        updateAccessibilityDot()

        a11yRow.addArrangedSubview(a11yDot)
        a11yRow.addArrangedSubview(a11yLabel)
        a11yRow.addArrangedSubview(NSView()) // spacer
        a11yRow.addArrangedSubview(a11yButton)

        // ---- Input activity row ----
        let activityRow = NSStackView()
        activityRow.orientation = .horizontal
        activityRow.spacing = 12
        activityRow.alignment = .centerY

        let activityLabel = NSTextField(labelWithString: "Activity")
        activityLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        activityLabel.textColor = .secondaryLabelColor

        gyroDotView = activityDotView(label: "Gyro")
        touchpadDotView = activityDotView(label: "Touchpad")
        mouseDotView = activityDotView(label: "Mouse")

        activityRow.addArrangedSubview(activityLabel)
        activityRow.addArrangedSubview(gyroDotView)
        activityRow.addArrangedSubview(touchpadDotView)
        activityRow.addArrangedSubview(mouseDotView)
        activityRow.addArrangedSubview(NSView()) // spacer

        // ---- Button debug row ----
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .centerY

        let buttonLabel = NSTextField(labelWithString: "Buttons")
        buttonLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        buttonLabel.textColor = .secondaryLabelColor

        buttonXDotView = activityDotView(label: "X")
        buttonCircleDotView = activityDotView(label: "O")
        buttonSquareDotView = activityDotView(label: "□")
        buttonTriangleDotView = activityDotView(label: "△")

        buttonRow.addArrangedSubview(buttonLabel)
        buttonRow.addArrangedSubview(buttonXDotView)
        buttonRow.addArrangedSubview(buttonCircleDotView)
        buttonRow.addArrangedSubview(buttonSquareDotView)
        buttonRow.addArrangedSubview(buttonTriangleDotView)
        buttonRow.addArrangedSubview(NSView()) // spacer

        // ---- Big X button press indicator ----
        let xRow = NSStackView()
        xRow.orientation = .horizontal
        xRow.spacing = 8
        xRow.alignment = .centerY

        let xLabel = NSTextField(labelWithString: "X button:")
        xLabel.font = NSFont.systemFont(ofSize: 11)
        xLabel.textColor = .secondaryLabelColor

        xPressedLabel = NSTextField(labelWithString: "X PRESSED")
        xPressedLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        xPressedLabel.textColor = .systemGray
        xPressedLabel.alignment = .center

        xRow.addArrangedSubview(xLabel)
        xRow.addArrangedSubview(xPressedLabel)
        xRow.addArrangedSubview(NSView()) // spacer

        // ---- Gyro X-Y visualizer ----
        gyroVisualizerView = GyroVisualizerView()
        gyroVisualizerView.translatesAutoresizingMaskIntoConstraints = false
        gyroVisualizerView.heightAnchor.constraint(equalToConstant: 120).isActive = true
        gyroVisualizerView.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let modeLabel = NSTextField(labelWithString: "Mode")
        modeLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        modeLabel.textColor = .secondaryLabelColor

        modeSegment = NSSegmentedControl(labels: ["Off", "Gyro", "Touchpad", "Both"],
                                         trackingMode: .selectOne,
                                         target: self,
                                         action: #selector(modeChanged))
        modeSegment.setSelected(true, forSegment: 1) // Gyro by default

        // ---- Sensitivity ----
        let sensLabel = NSTextField(labelWithString: "Sensitivity")
        sensLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        sensLabel.textColor = .secondaryLabelColor

        sensitivitySlider = NSSlider()
        sensitivitySlider.doubleValue = 1.0
        sensitivitySlider.minValue = 0.1
        sensitivitySlider.maxValue = 3.0

        // ---- Deadzone ----
        let deadzoneLabel = NSTextField(labelWithString: "Deadzone")
        deadzoneLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        deadzoneLabel.textColor = .secondaryLabelColor

        deadzoneSlider = NSSlider()
        deadzoneSlider.doubleValue = 0.05
        deadzoneSlider.minValue = 0.0
        deadzoneSlider.maxValue = 0.3

        // ---- Invert Y ----
        invertYCheckbox = NSButton(checkboxWithTitle: "Invert Y axis", target: nil, action: nil)
        invertYCheckbox.state = .off

        // ---- Live delta readout ----
        deltaLabel = NSTextField(labelWithString: "ΔX: 0.0   ΔY: 0.0")
        deltaLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        deltaLabel.textColor = .tertiaryLabelColor

        // ---- Raw value readouts ----
        gyroRateLabel = NSTextField(labelWithString: "Gyro: x:0.00 y:0.00 z:0.00")
        gyroRateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        gyroRateLabel.textColor = .tertiaryLabelColor

        touchpadLabel = NSTextField(labelWithString: "Touchpad: x:0.00 y:0.00")
        touchpadLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        touchpadLabel.textColor = .tertiaryLabelColor

        // ---- Assemble ----
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 380),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])

        stack.addArrangedSubview(statusRow)
        stack.addArrangedSubview(a11yRow)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(activityRow)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(buttonRow)
        stack.addArrangedSubview(xRow)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(gyroVisualizerView)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(modeLabel)
        stack.addArrangedSubview(modeSegment)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(sensLabel)
        stack.addArrangedSubview(sensitivitySlider)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(deadzoneLabel)
        stack.addArrangedSubview(deadzoneSlider)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(invertYCheckbox)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(deltaLabel)
        stack.addArrangedSubview(gyroRateLabel)
        stack.addArrangedSubview(touchpadLabel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Controller Remap"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.contentView = container
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
        print("Window created: \(String(describing: window)), isVisible: \(window.isVisible)")
    }

    /// Builds an activity indicator stack: [dot][label]. Returns the stack; the caller keeps a reference to `dot`.
    private func activityDotView(label: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .centerY

        let dot = NSView()
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        dot.layer = CALayer()
        dot.layer?.cornerRadius = 4
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemGray.cgColor

        let text = NSTextField(labelWithString: label)
        text.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        text.textColor = .secondaryLabelColor

        row.addArrangedSubview(dot)
        row.addArrangedSubview(text)
        return row
    }

    // MARK: - Status

    private func refreshStatus() {
        let controllers = GCController.controllers()
        let connected = !controllers.isEmpty
        updateStatusDot(connected: connected)

        if connected {
            let names = controllers.map { $0.vendorName ?? "Controller" }
            statusLabel.stringValue = names.joined(separator: ", ")
            statusLabel.textColor = .labelColor
        } else {
            statusLabel.stringValue = "No controller connected"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    private func updateStatusDot(connected: Bool) {
        statusDot.layer?.backgroundColor = connected
            ? NSColor.systemGreen.cgColor
            : NSColor.systemRed.cgColor
    }

    // MARK: - Accessibility

    private func updateAccessibilityDot() {
        guard let a11yDot = a11yDot, let a11yLabel = a11yLabel else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options: NSDictionary = [promptKey: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        a11yDot.layer?.backgroundColor = trusted
            ? NSColor.systemGreen.cgColor
            : NSColor.systemRed.cgColor
        a11yLabel.stringValue = trusted
            ? "Accessibility: granted"
            : "Accessibility: not granted"
        a11yLabel.textColor = trusted
            ? NSColor.labelColor
            : NSColor.systemRed
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        let selected = modeSegment.selectedSegment
        let mode: ControllerManager.RemapMode
        switch selected {
        case 0: mode = .off
        case 1: mode = .gyro
        case 2: mode = .touchpad
        case 3: mode = .both
        default: mode = .off
        }
        manager.mode = mode
    }

    // MARK: - Tick

    private func tick() {
        manager.tick()

        manager.sensitivity = CGFloat(sensitivitySlider.doubleValue)
        manager.deadzone = CGFloat(deadzoneSlider.doubleValue)
        manager.invertY = invertYCheckbox.state == .on

        // Refresh activity indicators.
        updateActivityIndicators()
        updateButtonIndicators()
        updateRawValueReadouts()
        updateAccessibilityDot()
        refreshStatus()
    }

    private func updateActivityIndicators() {
        setDotColor(gyroDotView, active: manager.gyroActive)
        setDotColor(touchpadDotView, active: manager.touchpadActive)
        setDotColor(mouseDotView, active: manager.mouseMoved, activeColor: NSColor.systemBlue.cgColor)

        // Live delta readout.
        let d = manager.lastMouseDelta
        deltaLabel.stringValue = String(format: "ΔX: %+.2f   ΔY: %+.2f", d.x, d.y)
    }

    private func updateButtonIndicators() {
        setDotColor(buttonXDotView, active: manager.buttonXPressed)
        setDotColor(buttonCircleDotView, active: manager.buttonCirclePressed)
        setDotColor(buttonSquareDotView, active: manager.buttonSquarePressed)
        setDotColor(buttonTriangleDotView, active: manager.buttonTrianglePressed)

        // Big X button press indicator.
        xPressedLabel.textColor = manager.buttonXPressed
            ? NSColor.systemGreen
            : NSColor.systemGray
        xPressedLabel.stringValue = manager.buttonXPressed
            ? "X PRESSED"
            : "X released"
    }

    private func updateRawValueReadouts() {
        let g = manager.lastGyroRate
        gyroRateLabel.stringValue = String(format: "Gyro: x:%+.3f y:%+.3f z:%+.3f", g.x, g.y, g.z)

        let t = manager.lastTouchpadPosition
        touchpadLabel.stringValue = String(format: "Touchpad: x:%+.2f y:%+.2f", t.x, t.y)

        // Update gyro X-Y visualizer.
        gyroVisualizerView.gyroX = g.x
        gyroVisualizerView.gyroY = g.y
    }

    private func setDotColor(_ stack: NSStackView, active: Bool, activeColor: CGColor = NSColor.systemGreen.cgColor) {
        guard let dot = stack.arrangedSubviews.first else { return }
        dot.layer?.backgroundColor = active ? activeColor : NSColor.systemGray.cgColor
    }
}

/// Visualizer showing gyro X-Y as a moving dot on a crosshair.
/// Gyro values (int16 range) are normalized to fit within the view bounds.
final class GyroVisualizerView: NSView {
    var gyroX: Double = 0 {
        didSet { needsDisplay = true }
    }
    var gyroY: Double = 0 {
        didSet { needsDisplay = true }
    }

    // Normalization: typical DS4 gyro range is roughly ±1000 deg/sec * 1000 raw units.
    // We'll normalize to ±2000 for comfortable display.
    private let normalizeRange: Double = 2000

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 6
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let width = bounds.width
        let height = bounds.height
        let centerX = width / 2
        let centerY = height / 2

        // Draw crosshair.
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: centerX, y: 4))
        context.addLine(to: CGPoint(x: centerX, y: height - 4))
        context.move(to: CGPoint(x: 4, y: centerY))
        context.addLine(to: CGPoint(x: width - 4, y: centerY))
        context.strokePath()

        // Normalize gyro values to view coordinates.
        let normX = max(-1, min(1, gyroX / normalizeRange))
        let normY = max(-1, min(1, gyroY / normalizeRange))

        let dotX = centerX + CGFloat(normX) * (width / 2 - 8)
        let dotY = centerY - CGFloat(normY) * (height / 2 - 8) // Y inverted for screen coords

        // Draw dot.
        let dotSize: CGFloat = 10
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fillEllipse(in: CGRect(
            x: dotX - dotSize / 2,
            y: dotY - dotSize / 2,
            width: dotSize,
            height: dotSize
        ))
    }
}
