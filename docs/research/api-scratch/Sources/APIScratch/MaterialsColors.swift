// MaterialsColors.swift — §6: Materials, MaterialActiveAppearance, Color,
// HDR color (macOS 26).
//
// Ground truth (SDK MacOSX27.0.sdk):
//   SwiftUICore …:7987  struct Material; statics: .regular/.thick/.thin/.ultraThin/.ultraThick (+ .bar macOS 12)
//   SwiftUICore …:8070  @available(iOS 18.0, macOS 15.0, …) struct MaterialActiveAppearance
//                        .automatic / .active / .inactive / .matchWindow
//   SwiftUICore …:8088  EnvironmentValues.materialActiveAppearance
//   SwiftUICore …:8100  Material.materialActiveAppearance(_:) -> Material   (macOS 15)
//   SwiftUICore …:8119  View.materialActiveAppearance(_:) -> some View       (macOS 15)
//   SwiftUICore …:10020 @available(iOS 26.0, macOS 26.0, …) Color.ResolvedHDR
//                        init(_ color: Color.Resolved, headroom: Float? = nil)
//   SwiftUICore …:21231 Color.mix(with:by:in:)                                 (macOS 15)
//   AppKit/NSColor.h:164  +colorWithRed:green:blue:alpha:exposure:            (macOS 26)
//   AppKit/NSColor.h:167  +colorWithRed:green:blue:alpha:linearExposure:      (macOS 26)
//   AppKit/NSColor.h:170  colorByApplyingContentHeadroom:                     (macOS 26)
//   AppKit/NSColor.h:376  linearExposure                                      (macOS 26)
//
// Doc-comment highlights:
//  * Material is a `ShapeStyle`, not a view: use `.background(_:in:)` etc.
//  * `.bar` is the toolbar/bar material.
//  * NSColor exposure APIs: "Each whole value of exposure produces a color that
//    is twice as bright" — for HDR highlights only, never body text.

import SwiftUI
import AppKit

// MARK: - 6.1 Material variants

struct MaterialGallery: View {
    var body: some View {
        VStack(spacing: 10) {
            materialRow("ultraThinMaterial", .ultraThinMaterial)
            materialRow("thinMaterial", .thinMaterial)
            materialRow("regularMaterial", .regularMaterial)
            materialRow("thickMaterial", .thickMaterial)
            materialRow("ultraThickMaterial", .ultraThickMaterial)
            materialRow("bar (macOS 12)", .bar)

            // Material resolved through the environment as a ShapeStyle:
            Rectangle()
                .fill(.regularMaterial)
                .frame(height: 30)
        }
        .padding(20)
        .background(.thickMaterial)
    }

    private func materialRow(_ name: String, _ material: Material) -> some View {
        Text(name)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(material, in: .rect(cornerRadius: 8))
    }
}

// MARK: - 6.2 MaterialActiveAppearance (macOS 15+)

/// Controls whether a material renders as if its window were active.
/// `.matchWindow` is the native-looking default for custom chrome that should
/// dim together with the window when the app is inactive.
struct MaterialActiveAppearanceDemo: View {
    @Environment(\.materialActiveAppearance) private var activeAppearance

    var body: some View {
        VStack(spacing: 10) {
            Text("matchWindow")
                .padding(8)
                .background(.regularMaterial.materialActiveAppearance(.matchWindow))
            Text("active")
                .padding(8)
                .background(.regularMaterial.materialActiveAppearance(.active))
            Text("inactive")
                .padding(8)
                .background(.regularMaterial.materialActiveAppearance(.inactive))
            Text("automatic")
                .padding(8)
                .background(.regularMaterial.materialActiveAppearance(.automatic))

            // Read the environment value (e.g. to forward it):
            Text("env: \(String(describing: activeAppearance))")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

// MARK: - 6.3 Color: semantic macOS colors, mixing, Resolved / ResolvedHDR

struct ColorDemo: View {
    var body: some View {
        VStack(spacing: 10) {
            // Semantic AppKit colors bridged into SwiftUI:
            HStack(spacing: 6) {
                swatch(Color(nsColor: .labelColor))
                swatch(Color(nsColor: .secondaryLabelColor))
                swatch(Color(nsColor: .separatorColor))
                swatch(Color(nsColor: .controlAccentColor))
                swatch(Color(nsColor: .selectedContentBackgroundColor))
                swatch(Color(nsColor: .windowBackgroundColor))
                swatch(Color(nsColor: .underPageBackgroundColor))
            }

            // Pre-resolved color (fast path; no environment needed):
            let base = Color.Resolved(red: 0.20, green: 0.55, blue: 1.0, opacity: 1.0)
            Color(base)
                .frame(height: 24)

            // HDR color (macOS 26): base SDR color + headroom. Only use for
            // small glows/highlights on EDR displays.
            let hdr = Color.ResolvedHDR(base, headroom: 2.0)
            LinearGradient(
                colors: [Color(hdr), Color(base)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 24)
            .clipShape(.rect(cornerRadius: 6))

            // Mixing (macOS 15): perceptual by default; also .perceptual/.device.
            Color.blue
                .mix(with: .red, by: 0.35)
                .frame(height: 12)
            Color.blue
                .mix(with: .red, by: 0.35, in: .perceptual)
                .frame(height: 12)

            // Adjustments & blending.
            Color.orange
                .brightness(0.05)
                .saturation(0.9)
                .contrast(1.05)
                .colorMultiply(.white)
                .frame(height: 12)

            // Tint / foreground styles.
            Text("Progress")
                .foregroundStyle(.tint)
                .tint(.accentColor)
        }
        .padding(20)
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: 24, height: 24)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
    }
}

// MARK: - 6.4 AppKit-side HDR color (macOS 26)

/// Only needed when drawing with AppKit directly (e.g. custom NSView chrome).
@MainActor
enum AppKitHDRColor {
    static func specular(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1, exposure: 1.5)
    }

    static func linear(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1, linearExposure: 2.0)
    }

    static func sdr(from color: NSColor) -> NSColor {
        color.standardDynamicRange          // Swift name of standardDynamicRangeColor
    }

    static func headroom(of color: NSColor) -> CGFloat {
        color.linearExposure
    }
}

// MARK: - 6.5 Semantic colors vs. hard-coded hexes

/// Rule of thumb for Golden Gate: hard-coded grays never track the system's
/// appearance/contrast settings. Prefer:
///   * `.primary/.secondary/.tertiary/.quaternary` for text hierarchy
///   * `.separator`, `.quaternary` fills for hairlines and wells
///   * `Color(nsColor: .controlAccentColor)` when you need the real accent
///   * album-art tint only as a *low-opacity* wash behind glass, never as the
///     only source of contrast.
struct SemanticColorRules: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Primary").font(.body)
            Text("Secondary").font(.callout).foregroundStyle(.secondary)
            Text("Tertiary").font(.caption).foregroundStyle(.tertiary)
            Divider().overlay(.separator)
            Text("Quaternary fill well")
                .padding(6)
                .background(.quaternary, in: .rect(cornerRadius: 6))
        }
        .padding(20)
    }
}
