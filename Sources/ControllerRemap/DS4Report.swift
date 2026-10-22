import Foundation

/// PS4 DualShock 4 HID input report parser.
///
/// macOS delivers DS4 input via two report types over Bluetooth:
///   - Report ID 0x01, 10 bytes: basic buttons + sticks (no gyro)
///   - Report ID 0x11, 78 bytes: full input report incl. gyro/accel/touchpad
///
/// After sending feature report 0x05 with value 0x01, the DS4 starts
/// emitting the 78-byte full report with motion sensor data.
///
/// Byte layout for Report ID 0x11 (78 bytes):
///   0:   Report ID (0x11)
///   1:   Unknown (0xc0)
///   2:   Unknown (0x00)
///   3-6: LeftStickX, LeftStickY, RightStickX, RightStickY (0x80 = center)
///   7:   L2 trigger analog
///   8:   R2 trigger analog
///   9-10: Gyro X (signed 16-bit LE)
///   11-12: Unknown / timestamp
///   13-14: Gyro Y (signed 16-bit LE)
///   15-16: Gyro Z (signed 16-bit LE)
///   17-23: Accel / other sensor data
///   ...

struct DS4ButtonState {
    var cross: Bool = false
    var circle: Bool = false
    var square: Bool = false
    var triangle: Bool = false
    var l1: Bool = false
    var r1: Bool = false
    var l2Button: Bool = false
    var r2Button: Bool = false
    var share: Bool = false
    var options: Bool = false
    var l3: Bool = false
    var r3: Bool = false
    var ps: Bool = false
    var touchpadButton: Bool = false
    var dpadUp: Bool = false
    var dpadDown: Bool = false
    var dpadLeft: Bool = false
    var dpadRight: Bool = false
    var l2Analog: UInt8 = 0
    var r2Analog: UInt8 = 0
}

struct DS4MotionData {
    var gyroX: Double = 0
    var gyroY: Double = 0
    var gyroZ: Double = 0
    var accelX: Double = 0
    var accelY: Double = 0
    var accelZ: Double = 0
}

struct DS4TouchData {
    var finger0X: UInt8 = 0
    var finger0Y: UInt8 = 0
    var finger0Active: Bool = false
}

struct DS4Report {
    var buttons: DS4ButtonState
    var motion: DS4MotionData
    var touchpad: DS4TouchData
    var rawBytes: [UInt8]

    init?(data: Data) {
        guard data.count >= 3 else { return nil }
        self.rawBytes = [UInt8](data)

        let reportID = data[0]

        // ---- Parse based on report ID ----
        if reportID == 0x11 {
            self.buttons = DS4Report.parseButtonsReport0x11(data)
            self.motion = DS4Report.parseMotionReport0x11(data)
            self.touchpad = DS4Report.parseTouchpadReport0x11(data)
        } else if reportID == 0x01 {
            self.buttons = DS4Report.parseButtonsReport0x01(data)
            self.motion = DS4MotionData()
            self.touchpad = DS4TouchData()
        } else {
            return nil
        }
    }

    // MARK: - Report ID 0x01 (10 bytes, basic)

    private static func parseButtonsReport0x01(_ data: Data) -> DS4ButtonState {
        var b = DS4ButtonState()
        let btn1 = data[1]
        let btn2 = data[2]

        b.square  = (btn1 & 0x01) != 0
        b.cross   = (btn1 & 0x02) != 0
        b.circle  = (btn1 & 0x04) != 0
        b.triangle = (btn1 & 0x08) != 0
        b.l1      = (btn1 & 0x10) != 0
        b.r1      = (btn1 & 0x20) != 0
        b.l2Button = (btn1 & 0x40) != 0
        b.r2Button = (btn1 & 0x80) != 0

        b.share       = (btn2 & 0x01) != 0
        b.options     = (btn2 & 0x02) != 0
        b.l3          = (btn2 & 0x04) != 0
        b.r3          = (btn2 & 0x08) != 0
        b.ps          = (btn2 & 0x10) != 0
        b.touchpadButton = (btn2 & 0x20) != 0

        if data.count > 7 { b.l2Analog = data[7] }
        if data.count > 8 { b.r2Analog = data[8] }
        if data.count > 10 {
            let dpad = data[10]
            b.dpadUp    = (dpad == 0x01 || dpad == 0x02 || dpad == 0x08)
            b.dpadDown  = (dpad == 0x04 || dpad == 0x05 || dpad == 0x06)
            b.dpadLeft  = (dpad == 0x06 || dpad == 0x07 || dpad == 0x08)
            b.dpadRight = (dpad == 0x02 || dpad == 0x03 || dpad == 0x04)
        }
        return b
    }

    // MARK: - Report ID 0x11 (78 bytes, full)

    private static func parseButtonsReport0x11(_ data: Data) -> DS4ButtonState {
        var b = DS4ButtonState()
        guard data.count >= 11 else { return b }

        // Byte 1: Buttons L [Sq, X, O, Tri, L1, R1, L2-btn, R2-btn]
        let btn1 = data[1]
        b.square  = (btn1 & 0x01) != 0
        b.cross   = (btn1 & 0x02) != 0
        b.circle  = (btn1 & 0x04) != 0
        b.triangle = (btn1 & 0x08) != 0
        b.l1      = (btn1 & 0x10) != 0
        b.r1      = (btn1 & 0x20) != 0
        b.l2Button = (btn1 & 0x40) != 0
        b.r2Button = (btn1 & 0x80) != 0

        // Byte 2: Buttons R [Share, Opt, L3, R3, PS, TP-btn, -, -]
        let btn2 = data[2]
        b.share       = (btn2 & 0x01) != 0
        b.options     = (btn2 & 0x02) != 0
        b.l3          = (btn2 & 0x04) != 0
        b.r3          = (btn2 & 0x08) != 0
        b.ps          = (btn2 & 0x10) != 0
        b.touchpadButton = (btn2 & 0x20) != 0

        // Bytes 7-8: L2/R2 trigger analog
        if data.count > 7 { b.l2Analog = data[7] }
        if data.count > 8 { b.r2Analog = data[8] }

        // Byte 10: D-pad hat
        if data.count > 10 {
            let dpad = data[10]
            b.dpadUp    = (dpad == 0x01 || dpad == 0x02 || dpad == 0x08)
            b.dpadDown  = (dpad == 0x04 || dpad == 0x05 || dpad == 0x06)
            b.dpadLeft  = (dpad == 0x06 || dpad == 0x07 || dpad == 0x08)
            b.dpadRight = (dpad == 0x02 || dpad == 0x03 || dpad == 0x04)
        }
        return b
    }

    private static func parseMotionReport0x11(_ data: Data) -> DS4MotionData {
        var m = DS4MotionData()
        guard data.count >= 17 else { return m }

        // Based on observed 78-byte reports:
        //   Bytes 9-10:  Gyro X (signed 16-bit LE)
        //   Bytes 13-14: Gyro Y (signed 16-bit LE)
        //   Bytes 15-16: Gyro Z (signed 16-bit LE)
        m.gyroX = Double(readInt16LE(at: 9, in: data))
        m.gyroY = Double(readInt16LE(at: 13, in: data))
        m.gyroZ = Double(readInt16LE(at: 15, in: data))

        // Accel at bytes 17-22 (if available)
        if data.count >= 24 {
            m.accelX = Double(readInt16LE(at: 17, in: data))
            m.accelY = Double(readInt16LE(at: 19, in: data))
            m.accelZ = Double(readInt16LE(at: 21, in: data))
        }
        return m
    }

    private static func parseTouchpadReport0x11(_ data: Data) -> DS4TouchData {
        var t = DS4TouchData()
        // Touchpad data location in 78-byte report is TBD; leave zeros for now
        return t
    }

    private static func readInt16LE(at offset: Int, in data: Data) -> Int16 {
        guard offset + 1 < data.count else { return 0 }
        let low  = UInt16(data[offset])
        let high = UInt16(data[offset + 1])
        return Int16(bitPattern: UInt16(littleEndian: low | (high << 8)))
    }
}
