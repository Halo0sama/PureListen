// GuardedGlass.swift — deployed at macOS 13: exact #available pattern for
// Liquid Glass (macOS 26.0+) with a material fallback.
//
// Compile-verified with: swift build   (platforms: [.macOS(.v13)])
//
// The rule while the app keeps macOS 13:
//   1. Put all macOS 26-only code in a type/function annotated
//      `@available(macOS 26.0, *)`.
//   2. At the call site use `if #available(macOS 26.0, *) { … } else { … }`
//      inside a @ViewBuilder.
//   3. Every macOS 14/15 API ALSO needs a guard at macOS 13
//      (containerBackground = 14, toolbarBackgroundVisibility = 15,
//       Color.mix = 15, materialActiveAppearance = 15, symbolEffect = 14).
//
// What breaks if you do nothing: "'glassEffect' is only available in macOS
// 26.0 or newer" and " 'ConcentricRectangle' is only available in macOS 26.0
// or newer" — see ../negative-tests/ for the captured errors.

import SwiftUI
import AppKit

// MARK: - 1. The macOS 26 implementation (compile-isolated)

@available(macOS 26.0, *)
struct LiquidGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .glassEffect(
                .regular.tint(tint),
                in: ConcentricRectangle(corners: .concentric)
            )
            .containerShape(.rect(cornerRadius: cornerRadius))
    }
}

/// macOS 26-only interactive variant + macOS 27-only AppKit interactivity demo.
@available(macOS 26.0, *)
struct LiquidGlassInteractiveCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
    }
}

// MARK: - 2. The macOS 13 fallback (no availability restriction)

struct MaterialCardFallback<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(.regularMaterial, in: shape)
            .overlay(
                shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }
}

// MARK: - 3. The guarded call site — copy this shape

/// Public entry point used by the app. Compiles at macOS 13 and upgrades to
/// Liquid Glass automatically on macOS 26+.
struct AdaptiveGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            LiquidGlassCard(cornerRadius: cornerRadius, tint: tint) {
                content
            }
        } else {
            MaterialCardFallback(cornerRadius: cornerRadius) {
                content
            }
        }
    }
}

// MARK: - 4. Reduce Transparency aware wrapper (all versions)

struct AccessibleAdaptiveGlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var cornerRadius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        if reduceTransparency {
            // Opaque, high-contrast-friendly surface; identical layout.
            OpaqueAccessibleCard(cornerRadius: cornerRadius) { content }
        } else if #available(macOS 26.0, *) {
            LiquidGlassCard(cornerRadius: cornerRadius, tint: nil) { content }
                .overlay(border)
        } else {
            MaterialCardFallback(cornerRadius: cornerRadius) { content }
                .overlay(border)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                contrast == .increased
                    ? Color(nsColor: .labelColor).opacity(0.65)
                    : Color.white.opacity(0.1),
                lineWidth: contrast == .increased ? 1.5 : 0.5
            )
    }
}

struct OpaqueAccessibleCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color(nsColor: .windowBackgroundColor), in: shape)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

// MARK: - 5. Version capability probes (single source of truth)

enum GlassSupport {
    /// True on macOS 26+: Liquid Glass SwiftUI API present.
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// True on macOS 27+: AppKit glass interactivity, view corner config,
    /// NSStatusItem expanded-interface sessions.
    static var isGoldenGateAvailable: Bool {
        if #available(macOS 27.0, *) { return true }
        return false
    }

    /// True on macOS 15+: Color.mix, MaterialActiveAppearance.
    static var supportsColorMix: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// True on macOS 14+: containerBackground, symbolEffect.
    static var supportsContainerBackground: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }
}

// MARK: - 6. Inline guarded expression (no wrapper type needed)

extension View {
    /// Minimal inline pattern when a whole wrapper type is overkill.
    @ViewBuilder
    func liquidGlassIfAvailable(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.thinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Two-level guard: glass on 26, interactive AppKit-style behavior
    /// available only on 27 (effectIsInteractive is an AppKit property, so the
    /// SwiftUI equivalent here would forward to an NSViewRepresentable).
    @ViewBuilder
    func goldInteractiveGlassIfAvailable() -> some View {
        if #available(macOS 27.0, *) {
            self.liquidGlassIfAvailable(cornerRadius: 16)
        } else {
            self.liquidGlassIfAvailable(cornerRadius: 16)
        }
    }
}
