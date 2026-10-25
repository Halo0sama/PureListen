import Foundation
import CoreGraphics

// List on-screen windows (id, owner, name, bounds, layer)
let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    print("no windows"); exit(1)
}
for w in infos {
    let id = w[kCGWindowNumber as String] as? Int ?? -1
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    let name = w[kCGWindowName as String] as? String ?? ""
    let layer = w[kCGWindowLayer as String] as? Int ?? -999
    let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let alpha = w[kCGWindowAlpha as String] as? Double ?? -1
    let x = bounds["X"] as? Double ?? 0, y = bounds["Y"] as? Double ?? 0
    let wd = bounds["Width"] as? Double ?? 0, ht = bounds["Height"] as? Double ?? 0
    print(String(format: "id=%7d layer=%4d alpha=%.2f owner=%@ name=%@  [%.0f,%.0f %.0fx%.0f]", id, layer, alpha, owner, name, x, y, wd, ht))
}
