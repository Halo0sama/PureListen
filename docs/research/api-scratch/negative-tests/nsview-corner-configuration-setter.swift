// NEGATIVE TEST — must FAIL even at macOS 27: NSView.cornerConfiguration is a
// get-only property; configure it by overriding the getter in a subclass.
import AppKit

@available(macOS 27.0, *)
func configure(_ view: NSView) {
    view.cornerConfiguration = .corners(radius: .fixed(12))
}
