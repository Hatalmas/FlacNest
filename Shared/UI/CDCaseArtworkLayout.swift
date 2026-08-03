import CoreGraphics

enum CDCaseArtworkLayout {
    static let casePixelSize = CGSize(width: 680, height: 624)
    static let artworkPixelRect = CGRect(x: 72, y: 18, width: 588, height: 579)

    static var aspectRatio: CGFloat { casePixelSize.width / casePixelSize.height }

    static func displayWidth(forHeight height: CGFloat) -> CGFloat {
        height * aspectRatio
    }
}
