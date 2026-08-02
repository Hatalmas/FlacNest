import Foundation

enum FLACMetadataReader {
    static func readVorbisComments(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return [:] }
        guard data.count > 4, String(data: data.prefix(4), encoding: .ascii) == "fLaC" else { return [:] }

        var offset = 4
        var tags: [String: String] = [:]

        while offset + 4 <= data.count {
            let header = data[offset]
            let isLast = (header & 0x80) != 0
            let blockType = Int(header & 0x7F)
            let length = readUInt24BE(data, offset + 1)
            offset += 4

            guard length >= 0, offset + length <= data.count else { break }

            if blockType == 4 {
                tags = parseVorbisComments(data: data.subdata(in: offset..<(offset + length)))
            }

            offset += length
            if isLast { break }
        }

        return tags
    }

    private static func parseVorbisComments(data: Data) -> [String: String] {
        var offset = 0
        guard let vendorLength = readUInt32LE(data, offset) else { return [:] }
        offset += 4 + Int(vendorLength)

        guard let commentCount = readUInt32LE(data, offset) else { return [:] }
        offset += 4

        var tags: [String: String] = [:]
        for _ in 0..<commentCount {
            guard let length = readUInt32LE(data, offset) else { break }
            offset += 4
            guard length >= 0, offset + length <= data.count else { break }

            let commentData = data.subdata(in: offset..<(offset + length))
            offset += length

            guard let comment = String(data: commentData, encoding: .utf8),
                  let separator = comment.firstIndex(of: "=") else { continue }

            let key = String(comment[..<separator]).uppercased()
            let value = String(comment[comment.index(after: separator)...])
            if tags[key] == nil {
                tags[key] = value
            }
        }

        return tags
    }

    private static func readUInt32LE(_ data: Data, _ offset: Int) -> Int? {
        guard offset + 4 <= data.count else { return nil }
        return Int(data[offset])
            | (Int(data[offset + 1]) << 8)
            | (Int(data[offset + 2]) << 16)
            | (Int(data[offset + 3]) << 24)
    }

    private static func readUInt24BE(_ data: Data, _ offset: Int) -> Int {
        guard offset + 3 <= data.count else { return 0 }
        return (Int(data[offset]) << 16) | (Int(data[offset + 1]) << 8) | Int(data[offset + 2])
    }
}
