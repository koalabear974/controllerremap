import Foundation

/// PS4 DualShock 4 HID input report parser — Bluetooth Report ID 0x11.
///
/// Byte mapping (based on user-provided documentation):
///   0:   Report ID (0x11)
///   1:   Transaction Header (0x80)
///   2:   Reserved (0x00)
///   3:   Left Stick X    (0=Left, 128=Center, 255=Right)
///   4:   Left Stick Y    (0=Top, 128=Center, 255=Bottom)
///   5:   Right Stick X   (0=Left, 128=Center, 255=Right)
///   6:   Right Stick Y   (0=Top, 128=Center, 255=Bottom)
///   7:   Buttons & D-Pad:
///         Bits 4-7: Triangle(7), Circle(6), Cross(5), Square(4)
///         Bits 0-3: D-Pad Hat (0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW, 8=Released)
///   8:   Buttons & Stick Clicks:
///         Bit 0=L1, 1=R1, 2=L2, 3=R2, 4=Share, 5=Options, 6=L3, 7=R3
///   9:   PS & Touchpad Click:
///         Bit 0=PS Button, Bit 1=Touchpad Click
///   10:  L2 Trigger Analog (0-255)
///   11:  R2 Trigger Analog (0-255)
///   12-13: Timestamp / Counter (16-bit LE)
///   14:  Battery Level / Status
///   15-16: Gyroscope X (Pitch)  — int16 LE
///   17-18: Gyroscope Y (Yaw)    — int16 LE
///   19-20: Gyroscope Z (Roll)   — int16 LE
///   21-22: Accelerometer X      — int16 LE
///   23-24: Accelerometer Y      — int16 LE
///   25-26: Accelerometer Z      — int16 LE
///   27-34: Unknown / Reserved
///   35:   Finger 1 Status:
///          Bit 7 = 0 when touching, 1 when released
///          Bits [6:0] = tracking packet counter
///   36-38: Finger 1 Coordinates (24-bit packed):
///          X = ((Byte 37 & 0x0F) << 8) | Byte 36
///          Y = (Byte 38 << 4) | ((Byte 37 & 0xF0) >> 4)
///   39-42: Finger 2 Status & Coordinates (same structure)
///   43-77: Unknown / Reserved

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
    var gyroX: Double = 0   // int16 LE raw
    var gyroY: Double = 0   // int16 LE raw
    var gyroZ: Double = 0   // int16 LE raw
    var accelX: Double = 0  // int16 LE raw
    var accelY: Double = 0  // int16 LE raw
    var accelZ: Double = 0  // int16 LE raw
}

struct DS4TouchData {
    var finger0X: UInt16 = 0   // 0-1919
    var finger0Y: UInt16 = 0   // 0-942
    var finger0Active: Bool = false
    var finger1X: UInt16 = 0
    var finger1Y: UInt16 = 0
    var finger1Active: Bool = false
}

struct DS4Report {
    var buttons: DS4ButtonState
    var motion: DS4MotionData
    var touchpad: DS4TouchData
    var rawBytes: [UInt8]

    init?(data: Data) {
        guard data.count >= 43 else { return nil }
        self.rawBytes = [UInt8](data)

        let reportID = data[0]

        // Log raw bytes for debugging
        let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("🔍 DS4 raw [ID=0x\(String(reportID, radix: 16)) len=\(data.count)]: \(hex)")

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

    // MARK: - Report ID 0x01 (10 bytes, basic - USB mode)

    private static func parseButtonsReport0x01(_ data: Data) -> DS4ButtonState {
        var b = DS4ButtonState()
        guard data.count >= 3 else { return b }

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

    // MARK: - Report ID 0x11 (78 bytes, Bluetooth full)

    private static func parseButtonsReport0x11(_ data: Data) -> DS4ButtonState {
        var b = DS4ButtonState()
        guard data.count >= 15 else { return b }

        // Byte 7: Buttons (bits 4-7) & D-Pad (bits 0-3)
        let btn7 = data[7]
        b.triangle = (btn7 & 0x80) != 0   // Bit 7
        b.circle   = (btn7 & 0x40) != 0   // Bit 6
        b.cross    = (btn7 & 0x20) != 0   // Bit 5
        b.square   = (btn7 & 0x10) != 0   // Bit 4

        // D-pad hat (bits 0-3)
        let dpad = btn7 & 0x0F
        b.dpadUp    = (dpad == 0x00 || dpad == 0x01 || dpad == 0x07)
        b.dpadRight = (dpad == 0x01 || dpad == 0x02 || dpad == 0x03)
        b.dpadDown  = (dpad == 0x02 || dpad == 0x03 || dpad == 0x04)
        b.dpadLeft  = (dpad == 0x04 || dpad == 0x05 || dpad == 0x06)

        // Byte 8: L1, R1, L2, R2, Share, Options, L3, R3
        let btn8 = data[8]
        b.l1      = (btn8 & 0x01) != 0   // Bit 0
        b.r1      = (btn8 & 0x02) != 0   // Bit 1
        b.l2Button = (btn8 & 0x04) != 0  // Bit 2
        b.r2Button = (btn8 & 0x08) != 0  // Bit 3
        b.share   = (btn8 & 0x10) != 0   // Bit 4
        b.options = (btn8 & 0x20) != 0   // Bit 5
        b.l3      = (btn8 & 0x40) != 0   // Bit 6
        b.r3      = (btn8 & 0x80) != 0   // Bit 7

        // Byte 9: PS & Touchpad Click
        let btn9 = data[9]
        b.ps             = (btn9 & 0x01) != 0   // Bit 0
        b.touchpadButton = (btn9 & 0x02) != 0   // Bit 1

        // Bytes 10-11: L2 / R2 Trigger Analog
        if data.count > 10 { b.l2Analog = data[10] }
        if data.count > 11 { b.r2Analog = data[11] }

        return b
    }

    private static func parseMotionReport0x11(_ data: Data) -> DS4MotionData {
        var m = DS4MotionData()
        guard data.count >= 26 else { return m }

        // Bytes 15-16: Gyro X (Pitch) — int16 LE
        // Bytes 17-18: Gyro Y (Yaw)   — int16 LE
        // Bytes 19-20: Gyro Z (Roll)  — int16 LE
        m.gyroX = Double(readInt16LE(at: 15, in: data))
        m.gyroY = Double(readInt16LE(at: 17, in: data))
        m.gyroZ = Double(readInt16LE(at: 19, in: data))

        // Bytes 21-26: Accelerometer
        if data.count >= 26 {
            m.accelX = Double(readInt16LE(at: 21, in: data))
            m.accelY = Double(readInt16LE(at: 23, in: data))
            m.accelZ = Double(readInt16LE(at: 25, in: data))
        }
        return m
    }

    private static func parseTouchpadReport0x11(_ data: Data) -> DS4TouchData {
        var t = DS4TouchData()
        guard data.count >= 42 else { return t }

        // Byte 35: Finger 1 Status
        //   Bit 7 = 0 when touching, 1 when released
        //   Bits [6:0] = tracking packet counter
        let f1Status = data[35]
        t.finger0Active = (f1Status & 0x80) == 0  // Active when bit 7 is 0

        // Bytes 36-38: Finger 1 Coordinates (24-bit packed)
        //   X = ((Byte 37 & 0x0F) << 8) | Byte 36
        //   Y = (Byte 38 << 4) | ((Byte 37 & 0xF0) >> 4)
        let f1X = ((UInt16(data[37] & 0x0F) << 8) | UInt16(data[36]))
        let f1Y = ((UInt16(data[38]) << 4) | UInt16((data[37] & 0xF0) >> 4))
        t.finger0X = f1X
        t.finger0Y = f1Y

        // Bytes 39-42: Finger 2 (same structure)
        if data.count >= 42 {
            let f2Status = data[39]
            t.finger1Active = (f2Status & 0x80) == 0
            let f2X = ((UInt16(data[41] & 0x0F) << 8) | UInt16(data[40]))
            let f2Y = ((UInt16(data[42]) << 4) | UInt16((data[41] & 0xF0) >> 4))
            t.finger1X = f2X
            t.finger1Y = f2Y
        }

        return t
    }

    private static func readInt16LE(at offset: Int, in data: Data) -> Int16 {
        guard offset + 1 < data.count else { return 0 }
        let low  = UInt16(data[offset])
        let high = UInt16(data[offset + 1])
        return Int16(bitPattern: UInt16(littleEndian: low | (high << 8)))
    }
}
