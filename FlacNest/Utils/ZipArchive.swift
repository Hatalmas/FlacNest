import Compression
import Foundation

/// Minimal ZIP support for FlacNest transfer packages: writes stored entries, reads stored or deflated entries.
/// ZIP64 is not supported, so archives and entries must stay below 4 GB and 65 535 entries.
enum ZipArchiveError: LocalizedError {
    case cannotCreate(URL)
    case archiveTooLarge
    case notAZipArchive
    case unsupportedZip64
    case unsupportedCompression(UInt16)
    case corruptEntry(String)
    case checksumMismatch(String)
    case unsafeEntryPath(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreate(let url):
            return "Could not create \(url.lastPathComponent)."
        case .archiveTooLarge:
            return "The package is larger than 4 GB, which is not supported."
        case .notAZipArchive:
            return "The file is not a valid FlacNest package."
        case .unsupportedZip64:
            return "The package uses ZIP64, which is not supported."
        case .unsupportedCompression(let method):
            return "The package uses an unsupported compression method (\(method))."
        case .corruptEntry(let name):
            return "The package entry “\(name)” is damaged."
        case .checksumMismatch(let name):
            return "The package entry “\(name)” failed its checksum."
        case .unsafeEntryPath(let name):
            return "The package contains an unsafe path: \(name)"
        }
    }
}

final class ZipArchiveWriter {
    private struct CentralEntry {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private let handle: FileHandle
    private var entries: [CentralEntry] = []
    private var offset: UInt64 = 0
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(url: URL, date: Date = Date()) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ZipArchiveError.cannotCreate(url)
        }
        handle = try FileHandle(forWritingTo: url)
        (dosTime, dosDate) = Self.dosDateTime(from: date)
    }

    deinit {
        try? handle.close()
    }

    func addFile(named name: String, data: Data) throws {
        let nameData = Data(name.utf8)
        guard data.count < Int(UInt32.max),
              offset + UInt64(data.count) + 30 + UInt64(nameData.count) < UInt64(UInt32.max),
              entries.count < Int(UInt16.max) else {
            throw ZipArchiveError.archiveTooLarge
        }

        let crc = CRC32.checksum(data)
        let size = UInt32(data.count)

        var header = Data()
        header.appendLE(UInt32(0x0403_4B50))
        header.appendLE(UInt16(20))
        header.appendLE(UInt16(0x0800))
        header.appendLE(UInt16(0))
        header.appendLE(dosTime)
        header.appendLE(dosDate)
        header.appendLE(crc)
        header.appendLE(size)
        header.appendLE(size)
        header.appendLE(UInt16(nameData.count))
        header.appendLE(UInt16(0))
        header.append(nameData)

        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)

        entries.append(CentralEntry(name: nameData, crc: crc, size: size, offset: UInt32(offset)))
        offset += UInt64(header.count + data.count)
    }

    func finish() throws {
        var directory = Data()
        for entry in entries {
            directory.appendLE(UInt32(0x0201_4B50))
            directory.appendLE(UInt16(0x031E))
            directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(0x0800))
            directory.appendLE(UInt16(0))
            directory.appendLE(dosTime)
            directory.appendLE(dosDate)
            directory.appendLE(entry.crc)
            directory.appendLE(entry.size)
            directory.appendLE(entry.size)
            directory.appendLE(UInt16(entry.name.count))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt32(0o100644) << 16)
            directory.appendLE(entry.offset)
            directory.append(entry.name)
        }

        guard offset + UInt64(directory.count) < UInt64(UInt32.max) else {
            throw ZipArchiveError.archiveTooLarge
        }

        var end = Data()
        end.appendLE(UInt32(0x0605_4B50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt32(directory.count))
        end.appendLE(UInt32(offset))
        end.appendLE(UInt16(0))

        try handle.write(contentsOf: directory)
        try handle.write(contentsOf: end)
        try handle.synchronize()
        try handle.close()
    }

    private static func dosDateTime(from date: Date) -> (UInt16, UInt16) {
        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let year = max(1980, components.year ?? 1980)
        let time = UInt16((components.hour ?? 0) << 11 | (components.minute ?? 0) << 5 | (components.second ?? 0) / 2)
        let day = UInt16((year - 1980) << 9 | (components.month ?? 1) << 5 | (components.day ?? 1))
        return (time, day)
    }
}

struct ZipArchiveReader {
    struct Entry {
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int

        var isDirectory: Bool { name.hasSuffix("/") }
    }

    private let data: Data
    let entries: [Entry]

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
        entries = try Self.readCentralDirectory(in: data)
    }

    func contents(of entry: Entry) throws -> Data {
        let local = entry.localHeaderOffset
        guard local + 30 <= data.count, data.readLE(UInt32.self, at: local) == 0x0403_4B50 else {
            throw ZipArchiveError.corruptEntry(entry.name)
        }
        let nameLength = Int(data.readLE(UInt16.self, at: local + 26))
        let extraLength = Int(data.readLE(UInt16.self, at: local + 28))
        let start = local + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else {
            throw ZipArchiveError.corruptEntry(entry.name)
        }
        let payload = data.subdata(in: start ..< start + entry.compressedSize)

        let output: Data
        switch entry.method {
        case 0:
            output = payload
        case 8:
            output = try Self.inflate(payload, expectedSize: entry.uncompressedSize, name: entry.name)
        default:
            throw ZipArchiveError.unsupportedCompression(entry.method)
        }

        guard CRC32.checksum(output) == entry.crc else {
            throw ZipArchiveError.checksumMismatch(entry.name)
        }
        return output
    }

    private static func readCentralDirectory(in data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw ZipArchiveError.notAZipArchive }

        let searchStart = max(0, data.count - 22 - Int(UInt16.max))
        var endOffset: Int?
        var position = data.count - 22
        while position >= searchStart {
            if data.readLE(UInt32.self, at: position) == 0x0605_4B50 {
                endOffset = position
                break
            }
            position -= 1
        }
        guard let endOffset else { throw ZipArchiveError.notAZipArchive }

        let count = Int(data.readLE(UInt16.self, at: endOffset + 10))
        let directorySize = data.readLE(UInt32.self, at: endOffset + 12)
        let directoryOffset = data.readLE(UInt32.self, at: endOffset + 16)
        if count == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            throw ZipArchiveError.unsupportedZip64
        }

        var entries: [Entry] = []
        var cursor = Int(directoryOffset)
        for _ in 0 ..< count {
            guard cursor + 46 <= data.count, data.readLE(UInt32.self, at: cursor) == 0x0201_4B50 else {
                throw ZipArchiveError.notAZipArchive
            }
            let flags = data.readLE(UInt16.self, at: cursor + 8)
            let method = data.readLE(UInt16.self, at: cursor + 10)
            let crc = data.readLE(UInt32.self, at: cursor + 16)
            let compressedSize = data.readLE(UInt32.self, at: cursor + 20)
            let uncompressedSize = data.readLE(UInt32.self, at: cursor + 24)
            let nameLength = Int(data.readLE(UInt16.self, at: cursor + 28))
            let extraLength = Int(data.readLE(UInt16.self, at: cursor + 30))
            let commentLength = Int(data.readLE(UInt16.self, at: cursor + 32))
            let localOffset = data.readLE(UInt32.self, at: cursor + 42)

            guard cursor + 46 + nameLength <= data.count else { throw ZipArchiveError.notAZipArchive }
            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                throw ZipArchiveError.unsupportedZip64
            }

            let nameData = data.subdata(in: cursor + 46 ..< cursor + 46 + nameLength)
            let usesUTF8 = flags & 0x0800 != 0
            let name = String(data: nameData, encoding: usesUTF8 ? .utf8 : .isoLatin1)
                ?? String(decoding: nameData, as: UTF8.self)

            entries.append(Entry(
                name: name,
                method: method,
                crc: crc,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                localHeaderOffset: Int(localOffset)
            ))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func inflate(_ payload: Data, expectedSize: Int, name: String) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            payload.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, expectedSize,
                    sourceBase, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw ZipArchiveError.corruptEntry(name) }
        return output
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = value & 1 != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        table.withUnsafeBufferPointer { lookup in
            data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                for byte in buffer {
                    crc = lookup[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        var value: T = 0
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= count else { return 0 }
        Swift.withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination.bindMemory(to: UInt8.self), from: (startIndex + offset) ..< (startIndex + offset + size))
        }
        return T(littleEndian: value)
    }
}
