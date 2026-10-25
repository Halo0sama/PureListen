// NEGATIVE TEST — SwiftUI + AppKit glass mixed without any guard.
import SwiftUI
import AppKit

func makeGlassView() -> NSView {
    NSGlassEffectView()
}
