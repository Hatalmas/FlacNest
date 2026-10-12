import Foundation

enum CDSpinUpSoundMode: String, CaseIterable, Identifiable, Codable {
    case never
    case always
    case whenCDShown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never:
            return "Never"
        case .always:
            return "Always"
        case .whenCDShown:
            return "When the CD image is shown"
        }
    }
}

enum CDSpinUpSoundVolume: String, CaseIterable, Identifiable, Codable {
    case soft
    case medium
    case loud

    var id: String { rawValue }

    var label: String {
        switch self {
        case .soft: return "Soft"
        case .medium: return "Medium"
        case .loud: return "Loud"
        }
    }

    var gain: Float {
        switch self {
        case .soft: return 0.2
        case .medium: return 0.45
        case .loud: return 1
        }
    }
}
