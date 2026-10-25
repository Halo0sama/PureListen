// AccessibilityAppearance.swift — §8: Reduce Transparency / Increase Contrast
// / Reduce Motion detection and graceful degradation.
//
// Ground truth (SDK MacOSX27.0.sdk):
//   SwiftUICore …:23459  EnvironmentValues.accessibilityReduceTransparency    (macOS 10.15)
//   SwiftUICore …:23916  EnvironmentValues.colorSchemeContrast { .standard/.increased } (macOS 10.15)
//   SwiftUICore …:21710  EnvironmentValues.legibilityWeight                   (macOS 11)
//   AppKit/NSAccessibility.h:100-118
//        NSWorkspace.accessibilityDisplayShouldIncreaseContrast                (macOS 10.10)
//        NSWorkspace.accessibilityDisplayShouldDifferentiateWithoutColor       (macOS 10.10)
//        NSWorkspace.accessibilityDisplayShouldReduceTransparency              (macOS 10.10)
//        NSWorkspace.accessibilityDisplayShouldReduceMotion                    (macOS 10.12)
//        NSWorkspace.accessibilityDisplayShouldInvertColors                    (macOS 10.12)
//        NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification           (macOS 10.10)
//   AppKit/NSAppearance.h  NSAppearance.Name.accessibilityHighContrastAqua /
//        …DarkAqua / …VibrantLight / …VibrantDark + bestMatch(from:)          (macOS 10.14)
//   AppKit/NSAppearance.h  allowsVibrancy                                     (macOS 10.10)
//
// Platform note: there is NO new macOS 27 API for Liquid Glass diffusion in
// these headers. `NSWorkspace.accessibilityDisplayShouldReduceTransparency`
// remains the app-level switch; AppKit also exports
// `_NSGlassEffectDiffusionDidChangeNotification` in AppKit.tbd but it has no
// public header/declaration in the 27.0 SDK, so treat it as SPI (do not use).
//
// Strategy: detect via the SwiftUI environment when in SwiftUI, via NSWorkspace
// when in AppKit; *always* provide a non-translucent fallback that relies on
// materials + borders rather than glass.

import SwiftUI
import AppKit
import Combine

// MARK: - 8.1 Environment-driven glass degradation

/// The recommended production pattern: one modifier that renders real Liquid
/// Glass on macOS 26+, and an opaque/material fallback for Reduce Transparency.
///
/// (This scratch package targets macOS 27, so the `#available(macOS 26.0, *)`
/// inside `GlassAwareBackground` is redundant here — it is written out to show
/// the exact guard shape needed while the app stays at macOS 13. See
/// ../macos13-guards/Sources/GuardedUI/GuardedGlass.swift for the compiled
/// macOS-13 version.)
struct GlassAwareCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        if reduceTransparency {
            content
                .background(.regularMaterial.opacity(0.0), in: shape) // keep layout
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
        }
    }

    private var borderColor: Color {
        switch contrast {
        case .increased: Color(nsColor: .labelColor).opacity(0.55)
        default: Color.white.opacity(0.12)
        }
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 1.5 : 0.5
    }
}

// MARK: - 8.2 An opaque fallback surface for popovers/windows

/// Use when Reduce Transparency is on: solid `NSVisualEffectView`-equivalent
/// surface instead of glass. Keep the same shape/radius so layout does not move.
struct OpaquePanel<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Color(nsColor: .windowBackgroundColor),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}

// MARK: - 8.3 Border emphasis driven by Increase Contrast

struct ContrastBorder: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    contrast == .increased
                        ? Color(nsColor: .labelColor).opacity(0.7)
                        : Color.white.opacity(0.1),
                    lineWidth: contrast == .increased ? 1.5 : 0.5
                )
        }
    }
}

extension View {
    func contrastBorder(cornerRadius: CGFloat) -> some View {
        modifier(ContrastBorder(cornerRadius: cornerRadius))
    }
}

// MARK: - 8.4 AppKit-side detection: NSWorkspace + notifications

/// Observable wrapper around the AppKit accessibility-display flags. Use this
/// from NSView-based chrome (status item menu, custom popover window).
@MainActor
final class AccessibilityDisplayObserver: ObservableObject {
    @Published private(set) var shouldReduceTransparency: Bool = false
    @Published private(set) var shouldIncreaseContrast: Bool = false
    @Published private(set) var shouldReduceMotion: Bool = false

    private var cancellable: AnyCancellable?

    init() {
        refresh()
        cancellable = NotificationCenter.default
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let workspace = NSWorkspace.shared
        shouldReduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        shouldIncreaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        shouldReduceMotion = workspace.accessibilityDisplayShouldReduceMotion
    }
}

// MARK: - 8.5 NSAppearance: appearance + high-contrast appearance matching

@MainActor
enum AppearanceProbe {
    /// Resolve the current effective appearance of a window/view.
    static func isDark(in window: NSWindow) -> Bool {
        window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// High-contrast variants are *match-only* appearance names: they cannot be
    /// passed to `NSAppearance(named:)`, only to `bestMatch(from:)`.
    static func usesHighContrast(in window: NSWindow) -> Bool {
        let match = window.effectiveAppearance.bestMatch(from: [
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua,
            .aqua, .darkAqua
        ])
        return match == .accessibilityHighContrastAqua
            || match == .accessibilityHighContrastDarkAqua
    }

    /// Drawing-time appearance resolution.
    static func withDrawingAppearance(_ appearance: NSAppearance, _ body: () -> Void) {
        appearance.performAsCurrentDrawingAppearance(body)
    }

    /// `allowsVibrancy` tells you whether the appearance actually wants vibrant
    /// drawing; custom-drawn chrome should fall back to solid fills otherwise.
    static func allowsVibrancy(_ appearance: NSAppearance) -> Bool {
        appearance.allowsVibrancy
    }
}

// MARK: - 8.6 Reduce Motion: animation helper

struct MotionSensitiveView<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    @ViewBuilder var content: Content

    var body: some View {
        content.animation(reduceMotion ? nil : animation, value: UUID())
    }
}

// MARK: - 8.7 Legacy-weight / test-time availability helper

enum GlassSupport {
    /// True when the runtime supports Liquid Glass SwiftUI APIs.
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// True when the runtime supports the macOS 27 AppKit glass/corner APIs.
    static var isGoldenGateAvailable: Bool {
        if #available(macOS 27.0, *) { return true }
        return false
    }
}
