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

    /// Parses a pasted track line, trimming whitespace and removing a trailing duration such as `3:52`.
    static func importedTrackTitle(from line: String) -> String {
        var title = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if let durationRange = title.range(
            of: #"\s+\d{1,2}:\d{2}(?::\d{2})?\s*$"#,
            options: .regularExpression
        ) {
            title.removeSubrange(durationRange)
        }

        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
