import Foundation
import MachO

enum FFmpegLocator {
    private static let bundledSubdirectory = "bin"

    static func locateExecutable() -> URL? {
        var candidates: [URL] = []
        if let bundled = bundledExecutableURL() {
            candidates.append(bundled)
        }
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/local/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/bin/ffmpeg"),
        ])

        return candidates.first { isRunnable($0) }
    }

    static var usesBundledExecutable: Bool {
        bundledExecutableURL().map(isRunnable) ?? false
    }

    static func isRunnable(_ url: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return false }
        guard let architectures = machoArchitectures(in: url) else { return true }
        return architectures.contains(currentCPUType)
    }

    private static func bundledExecutableURL() -> URL? {
        Bundle.main.url(
            forResource: "ffmpeg",
            withExtension: nil,
            subdirectory: bundledSubdirectory
        )
    }

    private static var currentCPUType: cpu_type_t {
#if arch(arm64)
        return CPU_TYPE_ARM64
#elseif arch(x86_64)
        return CPU_TYPE_X86_64
#else
        return 0
#endif
    }

    private static func machoArchitectures(in url: URL) -> Set<cpu_type_t>? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 8), header.count >= 8 else { return nil }
        let magic = header.withUnsafeBytes { $0.load(as: UInt32.self) }

        switch magic {
        case FAT_MAGIC, FAT_CIGAM:
            return fatArchitectures(from: handle, header: header, magic: magic)
        case MH_MAGIC_64, MH_CIGAM_64, MH_MAGIC, MH_CIGAM:
            let swapped = magic == MH_CIGAM_64 || magic == MH_CIGAM
            let cpu = header.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: Int32.self) }
            return [swapped ? cpu.byteSwapped : cpu]
        default:
            return nil
        }
    }

    private static func fatArchitectures(from handle: FileHandle, header: Data, magic: UInt32) -> Set<cpu_type_t>? {
        let swapped = magic == FAT_CIGAM
        var count = header.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
        if swapped { count = count.byteSwapped }

        var architectures: Set<cpu_type_t> = []
        for _ in 0..<count {
            guard let arch = try? handle.read(upToCount: 20), arch.count >= 4 else { break }
            var cpu = arch.prefix(4).withUnsafeBytes { $0.load(as: Int32.self) }
            if swapped { cpu = cpu.byteSwapped }
            architectures.insert(cpu)
        }
        return architectures.isEmpty ? nil : architectures
    }
}
