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

for (key, translations) in L10n.strings {
    assert(translations.count == 3, "Missing translations: \(key)")
    for language in AppLanguage.allCases {
        let value = L10n.text(key, language: language)
        assert(!value.isEmpty)
        assert(value.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
    }
}
assert(L10n.text("Mulai mirroring", language: .english) == "Start mirroring")
assert(L10n.text("Gelap", language: .japanese) == "ダーク")
assert(L10n.text("Bahasa", language: .chinese) == "语言")
assert(L10n.text("USB Mirror", language: .english) == "USB Mirror")
print("All four languages have complete translations and matching format placeholders.")
