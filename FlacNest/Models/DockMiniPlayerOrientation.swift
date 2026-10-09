import AppKit
import Foundation

enum DockMiniPlayerOrientation: String, CaseIterable, Identifiable, Codable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontal:
            return "Horizontal"
        case .vertical:
            return "Vertical"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .horizontal: 170
        case .vertical: 80
        }
    }

    var defaultHeight: CGFloat {
        switch self {
        case .horizontal: 80
        case .vertical: 170
        }
    }

    var minWidth: CGFloat {
        defaultWidth
    }

    var minHeight: CGFloat {
        defaultHeight
    }

    var defaultSize: NSSize {
        NSSize(width: defaultWidth, height: defaultHeight)
    }

    var minSize: NSSize {
        NSSize(width: minWidth, height: minHeight)
    }
}
