import Foundation

enum MetadataTextRepair {
    /// Recovers UTF-8 that was decoded as Latin-1 / CP1250 / CP1252, then NFC-normalizes.
    static func repaired(_ text: String) -> String {
        let recovered = recoveredUTF8(fromMisdecoded: text) ?? text
        return recovered.precomposedStringWithCanonicalMapping
    }

    static func repaired(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = repaired(text)
        return value.isEmpty ? nil : value
    }

    static func looksDamaged(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if text.contains("\u{FFFD}") || text.contains("ï¿½") {
            return true
        }
        return looksLikeUTF8Mojibake(text)
    }

    static func recoveredUTF8(fromMisdecoded text: String) -> String? {
        guard looksLikeUTF8Mojibake(text) || text.contains("\u{FFFD}") || text.contains("ï¿½") else {
            return nil
        }

        let encodings: [String.Encoding] = [
            .isoLatin1,
            .windowsCP1252,
            String.Encoding(rawValue: 0x0500), // Windows-1250
            .isoLatin2,
        ]

        for encoding in encodings {
            guard let data = text.data(using: encoding),
                  let utf8 = String(data: data, encoding: .utf8),
                  !utf8.contains("\u{FFFD}"),
                  utf8 != text else {
                continue
            }
            return utf8
        }
        return nil
    }

    private static func looksLikeUTF8Mojibake(_ text: String) -> Bool {
        for (first, second) in zip(text, text.dropFirst()) {
            guard first == "Ã" || first == "Â" || first == "Å" || first == "Ä" || first == "Ă" else {
                continue
            }
            if let value = second.unicodeScalars.first?.value, (0x80...0xBF).contains(value) {
                return true
            }
        }
        return false
    }
}
