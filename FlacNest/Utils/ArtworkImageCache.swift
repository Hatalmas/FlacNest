import AppKit
import Foundation
import ImageIO

enum ArtworkImageCache {
    private static let cache = NSCache<NSURL, NSImage>()
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    static func image(for url: URL) -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url as URL) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Downsampled artwork for list and grid cells; `maxPixelSize` is in pixels, not points.
    static func thumbnail(for url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let bucket = Int((maxPixelSize / 64).rounded(.up)) * 64
        let key = "\(url.path)#\(bucket)" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: bucket,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return image(for: url)
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    static func removeImage(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
        thumbnailCache.removeAllObjects()
    }

    static func removeAll() {
        cache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }
}
