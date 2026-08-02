import Foundation

enum TrackTimeFormatting {
    static func formatClock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    static func formatDuration(start: Double, end: Double?) -> String {
        guard let end else { return "—" }
        let duration = max(0, end - start)
        return formatClock(duration)
    }
}
