// GlassBasics.swift — §1 of the cheat sheet: Glass variants + `.glassEffect(_:in:)`.
//
// Ground truth (SDK MacOSX27.0.sdk):
//   SwiftUICore/arm64e-apple-macos.swiftinterface:3064
//     @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
//     @available(visionOS, unavailable)
//     func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View
//   SwiftUICore …:7245  struct Glass { regular / clear / identity; tint(_:); interactive(_:) }
//   SwiftUICore …:3069  DefaultGlassEffectShape — "The default shape applied by
//                        glass effects, a capsule." (doc comment in symbol graph)
//
// Everything on this page is macOS 26.0+. There is no macOS 27-only glass API
// in SwiftUI (the macOS 27 delta for Liquid Glass is AppKit-side: see
// AppKitGlassViews.swift — NSGlassEffectView.effectIsInteractive).

import SwiftUI

// MARK: - 1.1 All four Glass configurations in one place

/// Every documented way to configure `Glass`.
struct GlassVariantsGallery: View {
    var body: some View {
        VStack(spacing: 12) {
            // Default: .regular + DefaultGlassEffectShape (a capsule).
            Label("Regular (default)", systemImage: "play.fill")
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect()

            // The regular variant auto-adjusts content legibility against the
            // backdrop (doc comment on Glass.regular).
            Text("Glass.regular")
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 14))

            // Clear variant: the SDK doc explicitly says you must add a dimming
            // treatment beneath it to keep content legible.
            Text("Glass.clear")
                .padding()
                .background(.black.opacity(0.3))
                .glassEffect(.clear, in: .rect(cornerRadius: 14))

            // Identity: "content remains unaffected as if no glass effect was
            // applied". Useful for previews / disabling without branching.
            Text("Glass.identity")
                .padding()
                .glassEffect(.identity, in: .rect(cornerRadius: 14))

            // Tint: tints the glass material; parameter is `Color?`.
            Text("Tinted")
                .padding()
                .glassEffect(.regular.tint(.orange), in: .rect(cornerRadius: 14))

            // Interactive: adds the pointer/press visual response; enable it on
            // glass that is (or contains) interactive controls.
            Button("Interactive glass") {}
                .buttonStyle(.plain)
                .padding()
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

            // Chaining, plus an explicit `false` to opt out again.
            Text("Tinted + interactive")
                .padding()
                .glassEffect(.regular.tint(.blue).interactive())
                .glassEffect(.regular.interactive(false), in: .rect(cornerRadius: 14))

            // Shapes: anything conforming to Shape.
            HStack(spacing: 12) {
                Image(systemName: "backward.fill")
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: .circle)
                Image(systemName: "play.fill")
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(.accentColor), in: .circle)
                Image(systemName: "forward.fill")
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: Capsule())
            }
        }
        .padding(20)
    }
}

// MARK: - 1.2 Glass anchors to the view's bounds (padding included)

/// The SDK doc comment states: "SwiftUI anchors the glass to the view's bounds.
/// ... the physical glass material fills the entirety of the label's frame,
/// which includes the padding." Order matters: pad first, then glass.
struct GlassBoundsDemo: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("pad → glass")
                .padding(14)
                .glassEffect(in: Capsule())

            Text("glass → pad")
                .glassEffect(in: Capsule())
                .padding(14) // this padding is *outside* the glass shape

            Text("frame → glass")
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassEffect(in: .rect(cornerRadius: 12))
        }
        .padding(20)
    }
}

// MARK: - 1.3 A reusable "glass chip" for the popover

/// Small metadata chip used in the 360×560 popover (format / bitrate / source).
struct GlassChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(
                .regular.tint(.accentColor.opacity(0.35)),
                in: Capsule()
            )
    }
}

// MARK: - 1.4 Minimum deployment check

#if os(macOS)
/// Compile-time proof: the `Glass` type itself is only visible when the
/// deployment target is ≥ macOS 26.0. If you paste this file into a target
/// still declared `platforms: [.macOS(.v13)]`, the build fails with
///   "'glassEffect' is only available in macOS 26.0 or newer"
/// exactly as documented in negative-tests/glass-effect-unguarded.swift.
private func _glassAvailabilityProbe() -> some View {
    GlassChip(title: "24-bit / 96 kHz", systemImage: "waveform")
}
#endif
