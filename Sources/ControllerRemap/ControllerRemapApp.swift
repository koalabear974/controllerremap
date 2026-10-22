import AppKit
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
    private var gyroActivityDotView: NSStackView!
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

    // Gyro X-Y visualizer (simple subviews, no custom draw)
    private var gyroVisualizerContainer: NSView!
    private var gyroDotView: NSView!
    private var gyroHLine: NSView!
    private var gyroVLine: NSView!

    // Touchpad X-Y visualizer
    private var touchpadVisualizerContainer: NSView!
    private var tpDotView: NSView!
    private var touchpadHLine: NSView!
    private var touchpadVLine: NSView!
    private var touchpadClickLabel: NSTextField!

    // Raw value readouts
    private var gyroRateLabel: NSTextField!
    private var touchpadLabel: NSTextField!

    // Controls
    private var modeSegment: NSSegmentedControl!
    private var sensitivitySlider: NSSlider!
    private var sensLabel: NSTextField!
    private var sensValueLabel: NSTextField!
    private var deadzoneLabel: NSTextField!
    private var deadzoneSlider: NSSlider!
    private var invertYCheckbox: NSButton!
    private var invertXCheckbox: NSButton!
    private var gyroRequiresXCheckbox: NSButton!

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("ControllerRemap: applicationDidFinishLaunching")
        NSApplication.shared.setActivationPolicy(.regular)

        buildUI()
        print("ControllerRemap: buildUI done")

        // Set up HID controller connection callback
        manager.onControllerConnectedChanged { [weak self] connected in
            self?.updateStatusDot(connected: connected)
        }

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
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

        gyroActivityDotView = activityDotView(label: "Gyro")
        touchpadDotView = activityDotView(label: "Touchpad")
        mouseDotView = activityDotView(label: "Mouse")

        activityRow.addArrangedSubview(activityLabel)
        activityRow.addArrangedSubview(gyroActivityDotView)
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
        gyroVisualizerContainer = NSView()
        gyroVisualizerContainer.wantsLayer = true
        gyroVisualizerContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        gyroVisualizerContainer.layer?.cornerRadius = 6
        gyroVisualizerContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        gyroVisualizerContainer.layer?.borderWidth = 1
        gyroVisualizerContainer.translatesAutoresizingMaskIntoConstraints = false
        gyroVisualizerContainer.heightAnchor.constraint(equalToConstant: 120).isActive = true
        gyroVisualizerContainer.widthAnchor.constraint(equalToConstant: 120).isActive = true

        // Crosshair lines
        gyroHLine = NSView()
        gyroHLine.wantsLayer = true
        gyroHLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        gyroHLine.translatesAutoresizingMaskIntoConstraints = false
        gyroHLine.heightAnchor.constraint(equalToConstant: 2).isActive = true
        gyroHLine.widthAnchor.constraint(equalToConstant: 120).isActive = true

        gyroVLine = NSView()
        gyroVLine.wantsLayer = true
        gyroVLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        gyroVLine.translatesAutoresizingMaskIntoConstraints = false
        gyroVLine.widthAnchor.constraint(equalToConstant: 2).isActive = true
        gyroVLine.heightAnchor.constraint(equalToConstant: 120).isActive = true

        // Gyro dot
        gyroDotView = NSView()
        gyroDotView.wantsLayer = true
        gyroDotView.layer?.backgroundColor = NSColor.systemBlue.cgColor
        gyroDotView.layer?.cornerRadius = 5
        gyroDotView.translatesAutoresizingMaskIntoConstraints = false
        gyroDotView.widthAnchor.constraint(equalToConstant: 10).isActive = true
        gyroDotView.heightAnchor.constraint(equalToConstant: 10).isActive = true
        gyroDotView.frame = CGRect(x: 55, y: 55, width: 10, height: 10)

        gyroVisualizerContainer.addSubview(gyroHLine)
        gyroVisualizerContainer.addSubview(gyroVLine)
        gyroVisualizerContainer.addSubview(gyroDotView)

        // Center the crosshair; dot starts at center via frame (not constraints)
        NSLayoutConstraint.activate([
            gyroHLine.centerXAnchor.constraint(equalTo: gyroVisualizerContainer.centerXAnchor),
            gyroHLine.centerYAnchor.constraint(equalTo: gyroVisualizerContainer.centerYAnchor),
            gyroVLine.centerXAnchor.constraint(equalTo: gyroVisualizerContainer.centerXAnchor),
            gyroVLine.centerYAnchor.constraint(equalTo: gyroVisualizerContainer.centerYAnchor),
        ])

        // ---- Touchpad X-Y visualizer ----
        touchpadVisualizerContainer = NSView()
        touchpadVisualizerContainer.wantsLayer = true
        touchpadVisualizerContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        touchpadVisualizerContainer.layer?.cornerRadius = 6
        touchpadVisualizerContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        touchpadVisualizerContainer.layer?.borderWidth = 1
        touchpadVisualizerContainer.translatesAutoresizingMaskIntoConstraints = false
        touchpadVisualizerContainer.heightAnchor.constraint(equalToConstant: 120).isActive = true
        touchpadVisualizerContainer.widthAnchor.constraint(equalToConstant: 190).isActive = true

        // Crosshair lines
        touchpadHLine = NSView()
        touchpadHLine.wantsLayer = true
        touchpadHLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        touchpadHLine.translatesAutoresizingMaskIntoConstraints = false
        touchpadHLine.heightAnchor.constraint(equalToConstant: 2).isActive = true
        touchpadHLine.widthAnchor.constraint(equalToConstant: 190).isActive = true

        touchpadVLine = NSView()
        touchpadVLine.wantsLayer = true
        touchpadVLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        touchpadVLine.translatesAutoresizingMaskIntoConstraints = false
        touchpadVLine.widthAnchor.constraint(equalToConstant: 2).isActive = true
        touchpadVLine.heightAnchor.constraint(equalToConstant: 120).isActive = true

        // Touchpad dot
        tpDotView = NSView()
        tpDotView.wantsLayer = true
        tpDotView.layer?.backgroundColor = NSColor.systemGreen.cgColor
        tpDotView.layer?.cornerRadius = 5
        tpDotView.translatesAutoresizingMaskIntoConstraints = false
        tpDotView.widthAnchor.constraint(equalToConstant: 10).isActive = true
        tpDotView.heightAnchor.constraint(equalToConstant: 10).isActive = true
        tpDotView.frame = CGRect(x: 85, y: 55, width: 10, height: 10)

        touchpadVisualizerContainer.addSubview(touchpadHLine)
        touchpadVisualizerContainer.addSubview(touchpadVLine)
        touchpadVisualizerContainer.addSubview(tpDotView)

        // Center the crosshair; dot starts at center via frame
        NSLayoutConstraint.activate([
            touchpadHLine.centerXAnchor.constraint(equalTo: touchpadVisualizerContainer.centerXAnchor),
            touchpadHLine.centerYAnchor.constraint(equalTo: touchpadVisualizerContainer.centerYAnchor),
            touchpadVLine.centerXAnchor.constraint(equalTo: touchpadVisualizerContainer.centerXAnchor),
            touchpadVLine.centerYAnchor.constraint(equalTo: touchpadVisualizerContainer.centerYAnchor),
        ])

        // Touchpad click indicator label
        touchpadClickLabel = NSTextField(labelWithString: "Touchpad: released")
        touchpadClickLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        touchpadClickLabel.textColor = .secondaryLabelColor
        touchpadClickLabel.alignment = .center

        // ---- Mode selector ----
        let modeLabel = NSTextField(labelWithString: "Mode")
        modeLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        modeLabel.textColor = .secondaryLabelColor

        modeSegment = NSSegmentedControl(labels: ["Off", "Gyro", "Touchpad", "Both"],
                                         trackingMode: .selectOne,
                                         target: self,
                                         action: #selector(modeChanged))
        modeSegment.setSelected(true, forSegment: 1) // Gyro by default

        // ---- Sensitivity ----
        sensLabel = NSTextField(labelWithString: "Sensitivity")
        sensLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        sensLabel.textColor = .secondaryLabelColor

        sensitivitySlider = NSSlider()
        sensitivitySlider.doubleValue = 1.0
        sensitivitySlider.minValue = 0.1
        sensitivitySlider.maxValue = 10.0
        sensitivitySlider.target = self
        sensitivitySlider.action = #selector(sensitivityChanged(_:))

        sensValueLabel = NSTextField(labelWithString: "1.0×")
        sensValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        sensValueLabel.textColor = .tertiaryLabelColor
        sensValueLabel.alignment = .right

        let sensRow = NSStackView()
        sensRow.orientation = .horizontal
        sensRow.spacing = 8
        sensRow.alignment = .centerY
        sensRow.addArrangedSubview(sensLabel)
        sensRow.addArrangedSubview(sensitivitySlider)
        sensRow.addArrangedSubview(sensValueLabel)

        // ---- Deadzone ----
        deadzoneLabel = NSTextField(labelWithString: "Deadzone")
        deadzoneLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        deadzoneLabel.textColor = .secondaryLabelColor

        deadzoneSlider = NSSlider()
        deadzoneSlider.doubleValue = 0.05
        deadzoneSlider.minValue = 0.0
        deadzoneSlider.maxValue = 0.5

        // ---- Invert Y ----
        invertYCheckbox = NSButton(checkboxWithTitle: "Invert Y axis", target: nil, action: nil)
        invertYCheckbox.state = .off

        // ---- Invert X ----
        invertXCheckbox = NSButton(checkboxWithTitle: "Invert X axis", target: nil, action: nil)
        invertXCheckbox.state = .off

        // ---- Gyro requires X button ----
        gyroRequiresXCheckbox = NSButton(checkboxWithTitle: "Gyro needs X button held", target: nil, action: nil)
        gyroRequiresXCheckbox.state = .on

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
        stack.addArrangedSubview(gyroVisualizerContainer)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(touchpadVisualizerContainer)
        stack.addArrangedSubview(touchpadClickLabel)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(modeLabel)
        stack.addArrangedSubview(modeSegment)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(sensRow)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(deadzoneLabel)
        stack.addArrangedSubview(deadzoneSlider)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(invertYCheckbox)
        stack.addArrangedSubview(invertXCheckbox)
        stack.addArrangedSubview(gyroRequiresXCheckbox)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(deltaLabel)
        stack.addArrangedSubview(gyroRateLabel)
        stack.addArrangedSubview(touchpadLabel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 700),
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

    /// Builds an activity indicator stack: [dot][label].
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
        let connected = manager.isControllerConnected
        updateStatusDot(connected: connected)

        if connected {
            statusLabel.stringValue = "DUALSHOCK 4 Wireless Controller"
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

    @objc private func sensitivityChanged(_ sender: NSSlider) {
        sensValueLabel.stringValue = String(format: "%.1f×", sender.doubleValue)
        manager.sensitivity = CGFloat(sender.doubleValue)
    }

    // MARK: - Tick

    private func tick() {
        manager.tick()

        manager.sensitivity = CGFloat(sensitivitySlider.doubleValue)
        manager.deadzone = CGFloat(deadzoneSlider.doubleValue)
        manager.invertY = invertYCheckbox.state == .on
        manager.invertX = invertXCheckbox.state == .on
        manager.gyroRequiresXButton = gyroRequiresXCheckbox.state == .on

        // Update sensitivity label
        sensValueLabel.stringValue = String(format: "%.1f×", sensitivitySlider.doubleValue)

        // Refresh activity indicators.
        updateActivityIndicators()
        updateButtonIndicators()
        updateRawValueReadouts()
        updateAccessibilityDot()
        refreshStatus()
    }

    private func updateActivityIndicators() {
        setDotColor(gyroActivityDotView, active: manager.gyroActive)
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

        // Update gyro X-Y visualizer dot position.
        // Normalize gyro values (±4500 range) to fit in 120x120 view (center at 60,60).
        // Rotate 90 deg: swap X and Y.
        // Apply invert X/Y to match mouse movement direction.
        var normX = max(-1, min(1, g.y / 4500))
        var normY = max(-1, min(1, g.x / 4500))
        if manager.invertX { normX = -normX }
        if manager.invertY { normY = -normY }
        let dotX = 55 + CGFloat(normX) * 50
        let dotY = 55 - CGFloat(normY) * 50 // Y inverted for screen coords
        gyroDotView.frame = CGRect(x: dotX, y: dotY, width: 10, height: 10)

        // Update touchpad X-Y visualizer dot position.
        // Touchpad normalized (0-1) mapped to 190x120 box (center at 95,60).
        let tpDotX = 5 + t.x * 180
        let tpDotY = 5 + (1 - t.y) * 110 // Y inverted for screen coords

        // Update touchpad dot color based on touch state.
        tpDotView.layer?.backgroundColor = manager.touchpadActive
            ? NSColor.systemGreen.cgColor
            : NSColor.systemBlue.cgColor

        // Make touchpad dot bigger and red when clicked.
        if manager.buttonTouchpadPressed {
            tpDotView.layer?.cornerRadius = 8
            tpDotView.frame = CGRect(x: tpDotX - 3, y: tpDotY - 3, width: 16, height: 16)
            tpDotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        } else {
            tpDotView.layer?.cornerRadius = 5
            tpDotView.frame = CGRect(x: tpDotX, y: tpDotY, width: 10, height: 10)
        }

        // Update touchpad click label.
        let isTouching = manager.touchpadActive || manager.buttonTouchpadPressed
        touchpadClickLabel.textColor = isTouching
            ? NSColor.systemGreen
            : NSColor.systemGray
        touchpadClickLabel.stringValue = isTouching
            ? "Touchpad: active"
            : "Touchpad: released"
    }

    private func setDotColor(_ stack: NSStackView, active: Bool, activeColor: CGColor = NSColor.systemGreen.cgColor) {
        guard let dot = stack.arrangedSubviews.first else { return }
        dot.layer?.backgroundColor = active ? activeColor : NSColor.systemGray.cgColor
    }
}
