import Foundation
import IOKit
import IOKit.hid
import QuartzCore

/// Reads raw HID input reports from a PS4 DualShock 4 controller via IOKit.
///
/// This bypasses Apple's GameController framework, which on macOS does not
/// expose PS4 motion sensors, face buttons, or touchpad data. Instead we talk
/// directly to the HID device and parse the DS4 input report ourselves.
///
/// Sony Vendor ID: 0x054C
/// DS4 USB Product ID:   0x05C4
/// DS4 Bluetooth Product ID: 0x09CC
final class HidControllerReader {

    static let shared = HidControllerReader()

    private let kDS4VendorID: UInt32 = 0x054C
    private let kDS4ProductID_USB: UInt32 = 0x05C4
    private let kDS4ProductID_BT: UInt32 = 0x09CC

    private var hidManager: IOHIDManager?
    private var device: IOHIDDevice?

    // Callbacks
    var onReport: ((DS4Report) -> Void)?

    private var debugEnabled = true

    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
        let ts = String(format: "[%010.3f]", CFAbsoluteTimeGetCurrent())
        print("\(ts) HidControllerReader: \(message)")
    }

    init() {}

    deinit {
        stop()
    }

    /// Start scanning for DS4 devices and reading input reports.
    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager

        // Match Sony vendor ID; we filter by product ID in the callback.
        let matchDict: [String: Any] = [kIOHIDVendorIDKey as String: kDS4VendorID]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        // Device matching callback (device plugged in / discovered).
        IOHIDManagerRegisterDeviceMatchingCallback(manager,
            { context, result, sender, device in
                let selfPtr = Unmanaged<HidControllerReader>.fromOpaque(context!).takeUnretainedValue()
                selfPtr.deviceMatched(device: device)
            },
            Unmanaged.passUnretained(self).toOpaque())

        // Device removal callback.
        IOHIDManagerRegisterDeviceRemovalCallback(manager,
            { context, result, sender, device in
                let selfPtr = Unmanaged<HidControllerReader>.fromOpaque(context!).takeUnretainedValue()
                selfPtr.deviceRemoved(device: device)
            },
            Unmanaged.passUnretained(self).toOpaque())

        // Input value callback (reports arriving).
        IOHIDManagerRegisterInputValueCallback(manager,
            { context, result, sender, value in
                let selfPtr = Unmanaged<HidControllerReader>.fromOpaque(context!).takeUnretainedValue()
                selfPtr.inputValueReceived(value: value)
            },
            Unmanaged.passUnretained(self).toOpaque())

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        debugLog("IOHIDManagerOpen result: \(openResult)")

        // Schedule the manager with the current run loop so callbacks fire.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        debugLog("HID manager started, scanning for DS4…")
    }

    func stop() {
        if let mgr = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            hidManager = nil
        }
        if let dev = device {
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            device = nil
        }
        debugLog("HID manager stopped")
    }

    // MARK: - Device callbacks

    private func deviceMatched(device: IOHIDDevice) {
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? UInt32 ?? 0
        let vendorID  = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey  as CFString) as? UInt32 ?? 0
        debugLog("Device matched: vendor=0x\(String(vendorID, radix: 16)) product=0x\(String(productID, radix: 16))")

        if productID == kDS4ProductID_USB || productID == kDS4ProductID_BT {
            debugLog("  -> This is a DS4! Opening device…")
            self.device = device

            let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            debugLog("  -> IOHIDDeviceOpen result: \(openResult)")

            // Register input report callback on the device itself.
            // API: IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, bufferLength, callback, context)
            let reportBufferSize: CFIndex = 256
            var reportBuffer = [UInt8](repeating: 0, count: Int(reportBufferSize))
            reportBuffer.withUnsafeMutableBufferPointer { buffer in
                IOHIDDeviceRegisterInputReportCallback(
                    device,
                    buffer.baseAddress!,
                    reportBufferSize,
                    { context, result, sender, reportType, reportID, report, reportLength in
                        let selfPtr = Unmanaged<HidControllerReader>.fromOpaque(context!).takeUnretainedValue()
                        let bytes = UnsafeBufferPointer<UInt8>(start: report, count: Int(reportLength))
                        let data = Data(bytes)
                        selfPtr.parseReport(data)
                    },
                    Unmanaged.passUnretained(self).toOpaque()
                )
            }
            debugLog("  -> IOHIDDeviceRegisterInputReportCallback registered")

            // Send feature report to enable full DS4 input reporting (gyro, accel, touchpad).
            // Feature report 0x05: [0x05, 0x01] enables gyro reporting on DS4.
            let featureReport: [UInt8] = [0x05, 0x01]
            let featureResult = featureReport.withUnsafeBufferPointer { buffer in
                IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeFeature,
                    CFIndex(0x05),
                    buffer.baseAddress!,
                    CFIndex(featureReport.count)
                )
            }
            debugLog("  -> IOHIDDeviceSetReport(feature=0x05) result: \(featureResult)")
        } else {
            debugLog("  -> Not a DS4 (product=0x\(String(productID, radix: 16))), ignoring")
        }
    }

    private func deviceRemoved(device: IOHIDDevice) {
        if self.device == device {
            debugLog("DS4 device removed")
            self.device = nil
        }
    }

    // MARK: - Input value callback (IOHIDManager level)

    private func inputValueReceived(value: IOHIDValue) {
        // This fires for scheduled values; we primarily use the device-level
        // callback above, but log here too for debugging.
        let report = IOHIDValueGetBytePtr(value)
        let length = IOHIDValueGetLength(value)
        let bytes = UnsafeBufferPointer<UInt8>(start: report, count: length)
        let data = Data(buffer: bytes)
        debugLog("Manager-level input value received, length=\(length): \(data.hexEncoded)")
        parseReport(data)
    }

    // MARK: - Report parsing

    private func parseReport(_ data: Data) {
        guard data.count >= 3 else { return }

        let reportID = data[0]
        debugLog("HID report received: ID=0x\(String(reportID, radix: 16)) length=\(data.count) hex=\(data.hexEncoded)")

        // We care about Report ID 0x01 (basic) and 0x11 (full with gyro).
        guard reportID == 0x01 || reportID == 0x11 else { return }

        if let report = DS4Report(data: data) {
            onReport?(report)
        } else {
            debugLog("  -> Failed to parse DS4 report")
        }
    }
}

private extension Data {
    var hexEncoded: String {
        return map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
