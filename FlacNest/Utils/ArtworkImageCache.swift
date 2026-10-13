import AppKit
import Foundation
import ImageIO

enum ArtworkImageCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    static func fileRevision(for url: URL?) -> String {
        guard let url else { return "" }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let size = values?.fileSize ?? 0
        let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.path)#\(size)#\(mtime)"
    }

    static func image(for url: URL) -> NSImage? {
        let key = fileRevision(for: url) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Downsampled artwork for list and grid cells; `maxPixelSize` is in pixels, not points.
    static func thumbnail(for url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let bucket = Int((maxPixelSize / 64).rounded(.up)) * 64
        let key = "\(fileRevision(for: url))#\(bucket)" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return image(for: url)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: bucket,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return image(for: url)
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    static func removeImage(for _: URL) {
        cache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    static func removeAll() {
        cache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }
}
