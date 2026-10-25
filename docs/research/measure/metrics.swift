import AppKit
import SwiftUI
import CoreText

func weightTrait(_ f: NSFont) -> Double {
    let traits = CTFontCopyTraits(f as CTFont) as NSDictionary
    return (traits[kCTFontWeightTrait] as? Double) ?? -9
}

func hex(_ c: NSColor, _ appearance: NSAppearance.Name) -> String {
    var out = "?"
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
        if let c2 = c.usingColorSpace(.sRGB) {
            let r = Int((c2.redComponent * 255).rounded())
            let g = Int((c2.greenComponent * 255).rounded())
            let b = Int((c2.blueComponent * 255).rounded())
            let a = c2.alphaComponent
            out = a >= 0.999 ? String(format: "#%02X%02X%02X", r,g,b) : String(format: "#%02X%02X%02X a=%.3f", r,g,b,a)
        }
    }
    return out
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

print("== system font sizes ==")
print("NSFont.systemFontSize:", NSFont.systemFontSize)
print("NSFont.smallSystemFontSize:", NSFont.smallSystemFontSize)
print("NSFont.labelFontSize:", NSFont.labelFontSize)
print("NSFont.systemFontSize(for: .regular):", NSFont.systemFontSize(for: .regular))

print("\n== preferred fonts for text styles ==")
let styles: [(String, NSFont.TextStyle)] = [
    ("largeTitle", .largeTitle), ("title1", .title1), ("title2", .title2), ("title3", .title3),
    ("headline", .headline), ("body", .body), ("callout", .callout), ("subheadline", .subheadline),
    ("footnote", .footnote), ("caption1", .caption1), ("caption2", .caption2),
    ]
for (name, s) in styles {
    let f = NSFont.preferredFont(forTextStyle: s)
    print(String(format: "%-14s size=%5.2f  weight=%5.2f  family=%@  font=%@", (name as NSString).utf8String!, f.pointSize, weightTrait(f), f.familyName ?? "?", f.fontName))
}

print("\n== NSColor semantics (sRGB) ==")
let colors: [(String, NSColor)] = [
    ("labelColor", .labelColor), ("secondaryLabelColor", .secondaryLabelColor),
    ("tertiaryLabelColor", .tertiaryLabelColor), ("quaternaryLabelColor", .quaternaryLabelColor),
    ("placeholderTextColor", .placeholderTextColor),
    ("separatorColor", .separatorColor), ("gridColor", .gridColor),
    ("windowBackgroundColor", .windowBackgroundColor), ("controlBackgroundColor", .controlBackgroundColor),
    ("underPageBackgroundColor", .underPageBackgroundColor), ("textBackgroundColor", .textBackgroundColor),
    ("controlColor", .controlColor), ("controlAccentColor", .controlAccentColor),
    ("selectedContentBackgroundColor", .selectedContentBackgroundColor),
    ("unemphasizedSelectedContentBackgroundColor", .unemphasizedSelectedContentBackgroundColor),
    ("selectedTextBackgroundColor", .selectedTextBackgroundColor),
    ("keyboardFocusIndicatorColor", .keyboardFocusIndicatorColor),
    ("linkColor", .linkColor), ("windowFrameTextColor", .windowFrameTextColor),
    ("headerTextColor", .headerTextColor), ("findHighlightColor", .findHighlightColor),
    ("systemBlue", .systemBlue), ("systemRed", .systemRed), ("systemGreen", .systemGreen),
    ("systemYellow", .systemYellow), ("systemOrange", .systemOrange), ("systemPurple", .systemPurple),
    ("systemPink", .systemPink), ("systemTeal", .systemTeal), ("systemIndigo", .systemIndigo),
    ("systemMint", .systemMint), ("systemCyan", .systemCyan), ("systemBrown", .systemBrown),
    ("systemGray", .systemGray),
]
for (n,c) in colors {
    print(String(format: "%-46s light=%-22s dark=%s", (n as NSString).utf8String!, (hex(c,.aqua) as NSString).utf8String!, (hex(c,.darkAqua) as NSString).utf8String!))
}

print("\n== animations ==")
print("NSAnimationContext.current.duration:", NSAnimationContext.current.duration)
NSAnimationContext.beginGrouping()
print("in grouping duration:", NSAnimationContext.current.duration, "timingFunction:", String(describing: NSAnimationContext.current.timingFunction))
NSAnimationContext.endGrouping()

print("\n== screens ==")
for s in NSScreen.screens { print("frame:", s.frame, "visible:", s.visibleFrame, "backingScale:", s.backingScaleFactor) } 
