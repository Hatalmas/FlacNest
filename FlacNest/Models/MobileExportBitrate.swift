import Foundation

enum MobileExportBitrate: Int, CaseIterable, Identifiable {
    case kbps256 = 256
    case kbps320 = 320

    var id: Int { rawValue }

    var label: String { "\(rawValue) kbps" }

    var ffmpegBitrateArgument: String { "\(rawValue)k" }
}

enum MobileExportParallelism: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case four = 4
    case six = 6
    case eight = 8

    var id: Int { rawValue }

    var label: String {
        rawValue == 1 ? "1 thread" : "\(rawValue) threads"
    }
}
