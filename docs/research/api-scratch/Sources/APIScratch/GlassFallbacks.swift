// GlassFallbacks.swift — §12: graceful degradation when Liquid Glass is not
// available (macOS 13–15) or when Reduce Transparency is on.
//
// The app currently declares `platforms: [.macOS(.v13)]`, so EVERY macOS 26/27
// API in this package must sit behind `#available` there. The compile-verified
// guarded versions live in ../macos13-guards/. This file contains the fallback
// building blocks that need no availability checks at all — they compile on
// macOS 13 and are the "else" branch of every guard.
//
// Native look on macOS 13–15:
//   * NSVisualEffectView / SwiftUI Material for translucency
//   * continuous RoundedRectangle + 0.5pt hairline border
//   * soft, low-opacity shadow
//   * generous padding and SF Symbols at matching optical size
// The Golden Gate deltas are: tighter uniform radii, specular rim on controls,
// and the morphing/interactive glass behaviors — not the base layout.

import SwiftUI
import AppKit

// MARK: - 12.1 The canonical fallback surface

/// Drop-in visual replacement for `.glassEffect(.regular, in: shape)`.
struct GlassFallbackSurface<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(.regularMaterial)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.06),
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

/// Convenience modifier mirroring the glass API shape (so switching branches
/// later is a one-line change).
extension View {
    /// Pre-26 / Reduce-Transparency fallback for `.glassEffect(_:in:)`.
    func glassFallback<S: InsettableShape>(in shape: S) -> some View {
        background(GlassFallbackSurface(shape: shape))
    }
}

// MARK: - 12.2 Adaptive surface: reduced transparency first, then version

/// Environment-only branching (no #available): this compiles even at macOS 13.
/// Put version branching *outside* in the caller (see macos13-guards package).
struct AdaptiveSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay {
                shape.strokeBorder(
                    contrast == .increased
                        ? Color(nsColor: .labelColor).opacity(0.6)
                        : Color.white.opacity(0.12),
                    lineWidth: contrast == .increased ? 1.5 : 0.5
                )
            }
    }
}

// MARK: - 12.3 The pre-26 "dated vs. native" checklist encoded as code

/// On macOS 13–15 you cannot get real Liquid Glass. Aim for calm, native
/// translucency instead of fake gloss:
struct DatedVsNativeRules: View {
    var body: some View {
        VStack(spacing: 16) {
            // ✗ dated: hard-coded translucent white on everything + big offset blur
            Text("dated")
                .padding()
                .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 12)

            // ✓ native-ish: semantic material, continuous 10–12pt radius,
            //   hairline border, subtle shadow.
            Text("native")
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
        .padding(20)
    }
}

// MARK: - 12.4 AppKit fallback for NSView chrome

@MainActor
enum AppKitFallbackChrome {
    /// Solid, appearance-tracking background for a borderless panel on macOS 13.
    static func makePanelBackground() -> NSVisualEffectView {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        return effect
    }

    /// If Reduce Transparency is on, swap to an opaque window background.
    static func applyAccessibilityAppearance(to window: NSWindow) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
        } else {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}

// MARK: - 12.5 Feature-gate enum used by call sites

/// Central place to ask "should I draw glass?" so the rest of the UI never
/// sprinkles `#available` around.
enum GlassAvailability {
    /// Version support *and* accessibility preference.
    @MainActor
    static func shouldUseGlass() -> Bool {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return false }
        if #available(macOS 26.0, *) {
            return true
        } else {
            return false
        }
    }

    /// macOS 27 AppKit corner-configuration support.
    @MainActor
    static func supportsConcentricViewCorners() -> Bool {
        if #available(macOS 27.0, *) { return true }
        return false
    }
}
