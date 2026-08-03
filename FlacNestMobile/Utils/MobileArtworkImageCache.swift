import ImageIO
import UIKit

enum MobileArtworkImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let pixelBucket = Int(maxPixelSize.rounded(.up))
        let key = cacheKey(url: url, maxPixelSize: pixelBucket) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = downsampledImage(at: url, maxPixelSize: CGFloat(pixelBucket)) else {
            return nil
        }

        cache.setObject(image, forKey: key, cost: imageCost(image))
        return image
    }

    static func clear() {
        cache.removeAllObjects()
    }

    private static func cacheKey(url: URL, maxPixelSize: Int) -> String {
        "\(url.path)|\(maxPixelSize)"
    }

    private static func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
