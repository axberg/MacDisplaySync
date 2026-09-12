import Foundation

struct MonitorDisplay: Codable, Identifiable, Hashable {
    let index: Int
    let displayID: UInt32
    let name: String
    let uuid: String

    var id: String { uuid }
}

struct VCPReading: Codable, Equatable {
    let code: Int
    let current: Int
    let maximum: Int
}

enum ControlKind {
    case slider
    case toggle(on: Int, off: Int)
}

struct MonitorFeature: Identifiable {
    let code: Int
    let name: String
    let symbol: String
    let kind: ControlKind

    var id: Int { code }
}

enum FeatureCatalog {
    static let display = [
        MonitorFeature(code: 0x10, name: "Brightness", symbol: "sun.max", kind: .slider),
        MonitorFeature(code: 0x12, name: "Contrast", symbol: "circle.lefthalf.filled", kind: .slider),
        MonitorFeature(code: 0x87, name: "Sharpness", symbol: "camera.filters", kind: .slider)
    ]

    static let audio = [
        MonitorFeature(code: 0x62, name: "Volume", symbol: "speaker.wave.2", kind: .slider),
        MonitorFeature(code: 0x8D, name: "Mute", symbol: "speaker.slash", kind: .toggle(on: 1, off: 2)),
        MonitorFeature(code: 0x8F, name: "Treble", symbol: "waveform.path", kind: .slider),
        MonitorFeature(code: 0x91, name: "Bass", symbol: "waveform", kind: .slider),
        MonitorFeature(code: 0x93, name: "Balance", symbol: "arrow.left.and.right", kind: .slider)
    ]

    static let color = [
        MonitorFeature(code: 0x16, name: "Red gain", symbol: "r.circle.fill", kind: .slider),
        MonitorFeature(code: 0x18, name: "Green gain", symbol: "g.circle.fill", kind: .slider),
        MonitorFeature(code: 0x1A, name: "Blue gain", symbol: "b.circle.fill", kind: .slider),
        MonitorFeature(code: 0x90, name: "Hue", symbol: "paintpalette", kind: .slider),
        MonitorFeature(code: 0x8A, name: "Saturation", symbol: "drop.halffull", kind: .slider)
    ]

    static let position = [
        MonitorFeature(code: 0x20, name: "Horizontal position", symbol: "arrow.left.and.right", kind: .slider),
        MonitorFeature(code: 0x30, name: "Vertical position", symbol: "arrow.up.and.down", kind: .slider)
    ]

    static let probeCodes: [Int] = {
        let regular = display + audio + color + position
        return regular.map(\.code) + [0x14, 0x60, 0xCC, 0xD6, 0xD7, 0xF4]
    }()
}

struct DiscreteOption: Identifiable, Hashable {
    let value: Int
    let label: String
    var id: Int { value }
}

enum DiscreteCatalog {
    static let inputs = [
        DiscreteOption(value: 0x0F, label: "DisplayPort 1"),
        DiscreteOption(value: 0x10, label: "DisplayPort 2"),
        DiscreteOption(value: 0x11, label: "HDMI 1"),
        DiscreteOption(value: 0x12, label: "HDMI 2"),
        DiscreteOption(value: 0x1B, label: "USB-C")
    ]

    static let lgInputs = [
        DiscreteOption(value: 0xD0, label: "DisplayPort 1"),
        DiscreteOption(value: 0xD1, label: "DisplayPort 2"),
        DiscreteOption(value: 0x90, label: "HDMI 1"),
        DiscreteOption(value: 0x91, label: "HDMI 2"),
        DiscreteOption(value: 0xD2, label: "USB-C / DisplayPort 3")
    ]

    static let colorTemperatures = [
        DiscreteOption(value: 0x01, label: "sRGB"),
        DiscreteOption(value: 0x02, label: "Display native"),
        DiscreteOption(value: 0x04, label: "5000 K"),
        DiscreteOption(value: 0x05, label: "6500 K"),
        DiscreteOption(value: 0x06, label: "7500 K"),
        DiscreteOption(value: 0x08, label: "9300 K"),
        DiscreteOption(value: 0x0B, label: "User 1"),
        DiscreteOption(value: 0x0C, label: "User 2")
    ]

    static let osdLanguages = [
        DiscreteOption(value: 0x01, label: "Chinese (Traditional)"),
        DiscreteOption(value: 0x02, label: "English"),
        DiscreteOption(value: 0x03, label: "French"),
        DiscreteOption(value: 0x04, label: "German"),
        DiscreteOption(value: 0x05, label: "Italian"),
        DiscreteOption(value: 0x06, label: "Japanese"),
        DiscreteOption(value: 0x07, label: "Korean"),
        DiscreteOption(value: 0x08, label: "Portuguese"),
        DiscreteOption(value: 0x09, label: "Russian"),
        DiscreteOption(value: 0x0A, label: "Spanish"),
        DiscreteOption(value: 0x0B, label: "Swedish"),
        DiscreteOption(value: 0x0C, label: "Turkish"),
        DiscreteOption(value: 0x0D, label: "Chinese (Simplified)")
    ]

    static let pictureByPicture = [
        DiscreteOption(value: 0x01, label: "Off"),
        DiscreteOption(value: 0x02, label: "Mode 2"),
        DiscreteOption(value: 0x03, label: "66 / 33"),
        DiscreteOption(value: 0x05, label: "50 / 50")
    ]
}

enum VCPLabels {
    static let names: [Int: String] = [
        0x02: "New control value", 0x04: "Restore factory defaults",
        0x05: "Restore brightness/contrast", 0x06: "Restore geometry",
        0x08: "Restore color defaults", 0x0B: "Color temperature increment",
        0x0C: "Color temperature", 0x0E: "Clock", 0x10: "Brightness",
        0x12: "Contrast", 0x14: "Color preset", 0x16: "Red gain",
        0x18: "Green gain", 0x1A: "Blue gain", 0x1E: "Auto setup",
        0x20: "Horizontal position", 0x30: "Vertical position",
        0x3E: "Clock phase", 0x52: "Active control", 0x60: "Input source",
        0x62: "Speaker volume", 0x6C: "Red black level",
        0x6E: "Green black level", 0x70: "Blue black level",
        0x87: "Sharpness", 0x8A: "Saturation", 0x8D: "Audio mute",
        0x8F: "Treble", 0x90: "Hue", 0x91: "Bass", 0x93: "Balance",
        0xAC: "Horizontal frequency", 0xAE: "Vertical frequency",
        0xAF: "Synchronization", 0xB6: "Display technology",
        0xC0: "Usage time", 0xC6: "Application enable key",
        0xC8: "Controller type", 0xC9: "Firmware level",
        0xCA: "OSD/button control", 0xCC: "OSD language",
        0xD6: "Power mode", 0xD7: "LG PBP / auxiliary power",
        0xDC: "Display mode", 0xDF: "VCP version",
        0xF4: "LG alternate input", 0xF9: "LG black stabilizer"
    ]

    static func name(for code: Int) -> String {
        names[code] ?? (code >= 0xE0 ? "Vendor-specific" : "VCP feature")
    }
}
