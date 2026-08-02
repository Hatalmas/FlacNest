import AppKit
import Foundation

enum ArtworkImageCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(for url: URL) -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url as URL) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func removeImage(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    static func removeAll() {
        cache.removeAllObjects()
    }
}
