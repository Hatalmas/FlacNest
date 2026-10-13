import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct AlbumBarcodeView: View {
    let barcode: String
    var cornerRadius: CGFloat = 10
    var barcodeHeight: CGFloat = 72

    var body: some View {
        VStack(spacing: 6) {
            if let image = Self.barcodeImage(for: barcode) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: barcodeHeight)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
            }

            Text(barcode)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(Color.black.opacity(0.75))
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Barcode \(barcode)")
    }

    private static func barcodeImage(for barcode: String) -> NSImage? {
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(barcode.utf8)
        filter.quietSpace = 7
        filter.barcodeHeight = 64
        guard let ciImage = filter.outputImage else { return nil }

        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
