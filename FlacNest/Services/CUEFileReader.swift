import Foundation

enum CUEFileReader {
    /// Reads CUE sheet text, trying common encodings used by rip tools.
    static func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if data.isEmpty {
            return ""
        }

        if let whole = bestDecodedText(for: data), !containsReplacementCharacters(whole) {
            return whole
        }

        return decodeLineByLine(data)
    }

    private static let preferredEncodings: [String.Encoding] = [
        .utf8,
        String.Encoding(rawValue: 0x0500), // Windows-1250 (Central European)
        .isoLatin2,
        .windowsCP1252,
        .isoLatin1,
        .shiftJIS,
        .utf16,
        .utf16LittleEndian,
        .utf16BigEndian,
    ]

    private static func decodeLineByLine(_ data: Data) -> String {
        let normalized = normalizeToLF(data)
        let lines = normalized.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        return lines.map { line in
            decodeBestLine(strippingCR(from: Data(line)))
        }.joined(separator: "\n")
    }

    private static func decodeBestLine(_ lineData: Data) -> String {
        if lineData.isEmpty { return "" }
        if let text = bestDecodedText(for: lineData) {
            return text
        }
        return String(decoding: lineData, as: UTF8.self)
    }

    private static func bestDecodedText(for data: Data) -> String? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = Data(bytes.dropFirst(3))
        }

        var best: (text: String, score: Int)?
        for encoding in preferredEncodings {
            guard let text = String(data: bytes, encoding: encoding) else { continue }
            let score = scoreCueText(text)
            if best == nil || score > best!.score {
                best = (text, score)
            }
        }
        return best?.text
    }

    private static func scoreCueText(_ text: String) -> Int {
        var score = 0
        score -= text.count(where: { $0 == "\u{FFFD}" }) * 1_000
        if text.contains("ï¿½") { score -= 500 }

        let upper = text.uppercased()
        if upper.contains("FILE ") { score += 20 }
        if upper.contains("TRACK ") { score += 10 }
        if upper.contains("INDEX ") { score += 5 }
        if upper.contains("PERFORMER ") { score += 5 }
        if upper.contains("TITLE ") { score += 5 }

        let centralEuropean = "áéíóöőúüűÁÉÍÓÖŐÚÜŰ"
        score += text.count(where: { centralEuropean.contains($0) }) * 3
        return score
    }

    private static func containsReplacementCharacters(_ text: String) -> Bool {
        text.contains("\u{FFFD}")
    }

    private static func normalizeToLF(_ data: Data) -> Data {
        var result = Data()
        result.reserveCapacity(data.count)
        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            if byte == 0x0D {
                if data.index(after: index) < data.endIndex, data[data.index(after: index)] == 0x0A {
                    index = data.index(index, offsetBy: 2)
                } else {
                    index = data.index(after: index)
                }
                result.append(0x0A)
            } else {
                result.append(byte)
                index = data.index(after: index)
            }
        }
        return result
    }

    private static func strippingCR(from data: Data) -> Data {
        if data.last == 0x0D {
            return Data(data.dropLast())
        }
        return data
    }
}
