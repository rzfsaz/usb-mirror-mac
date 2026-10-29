import Foundation
import CoreGraphics

let desktop = CGSize(width: 1200, height: 720)
for source in [CGSize(width: 1179, height: 2556), CGSize(width: 2556, height: 1179), CGSize(width: 1920, height: 1080)] {
    let fitted = MirrorGeometry.fittedSize(source: source, available: desktop)!
    assert(fitted.width <= desktop.width && fitted.height <= desktop.height)
    assert(abs(fitted.width / fitted.height - source.width / source.height) < 0.00001)
    assert((fitted.width > fitted.height) == (source.width > source.height))
}
assert(MirrorGeometry.fittedSize(source: .zero, available: desktop) == nil)
assert(MirrorGeometry.fittedSize(source: CGSize(width: CGFloat.nan, height: 100), available: desktop) == nil)
print("Portrait, landscape, bounds, aspect ratio, and invalid-input checks passed.")
