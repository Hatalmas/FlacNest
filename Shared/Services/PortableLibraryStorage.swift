import Foundation

enum PortableLibraryStorage {
    private static let activePackagePathKey = "portableLibraryActivePackagePath"
    private static let activePackageNameKey = "portableLibraryActivePackageName"

    static var activePackageName: String? {
        UserDefaults.standard.string(forKey: activePackageNameKey)
    }

    static func loadActivePackage() throws -> PortableLibraryPackage? {
        guard let path = UserDefaults.standard.string(forKey: activePackagePathKey),
              !path.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return try PortableLibraryLoader.load(from: url)
    }

    static func installPackage(from sourceURL: URL) throws -> PortableLibraryPackage {
        let fileManager = FileManager.default
        let importsRoot = try importsDirectoryURL()
        let destinationURL = importsRoot
            .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let package = try PortableLibraryLoader.load(from: destinationURL)
        UserDefaults.standard.set(destinationURL.path, forKey: activePackagePathKey)
        UserDefaults.standard.set(package.packageName, forKey: activePackageNameKey)
        return package
    }

    static func clearActivePackage() {
        UserDefaults.standard.removeObject(forKey: activePackagePathKey)
        UserDefaults.standard.removeObject(forKey: activePackageNameKey)
    }

    private static func importsDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let imports = base.appendingPathComponent("FlacNestMobile/Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        return imports
    }
}
