import Foundation
import CoreGraphics

/// Keeps portrait and landscape content inside the usable desktop area.
enum MirrorGeometry {
    static func fittedSize(source: CGSize, available: CGSize, preferredLongEdge: CGFloat = 960) -> CGSize? {
        guard source.width.isFinite, source.height.isFinite,
              source.width > 0, source.height > 0,
              available.width > 0, available.height > 0 else { return nil }
        let scale = min(preferredLongEdge / max(source.width, source.height),
                        available.width / source.width, available.height / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }
}
