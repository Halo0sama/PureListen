// ConcentricRadii.swift — §4: ConcentricRectangle, concentric radii, per-corner radii.
//
// Ground truth (SDK MacOSX27.0.sdk, SwiftUICore …swiftinterface):
//   16935  @available(iOS 26.0, macOS 26.0, …) struct ConcentricRectangle : Shape, Animatable
//            init()
//            init(corners: Edge.Corner.Style, isUniform: Bool = false)
//            init(topLeadingCorner:…, topTrailingCorner:…, bottomLeadingCorner:…, bottomTrailingCorner:…)
//            init(uniformTopCorners:…, uniformBottomCorners:…)  (+ 4 more uniformInits)
//   16966  extension Shape where Self == ConcentricRectangle { static func rect(…) }
//   24785  @available(… macOS 26.0 …) extension Edge.Corner { struct Style }
//            .fixed(_ radius: CGFloat) / .concentric / .concentric(minimum:)
//   17043  struct RoundedRectangularShapeCorners { .fixed/.concentric/.concentric(minimum:) }
//   17037  protocol RoundedRectangularShape : InsettableShape { func corners(in:) -> Corners? }
//   17082  func containerShape(_ shape: some RoundedRectangularShape) -> some View
//   17039  func containerCornerOffset(_ edges: Edge.Set, sizeToFit: Bool = false) -> some View
//   19xxx  struct RectangleCornerInsets; EdgeInsets.inset(by:edges:)
//
// Doc-comment highlights (SDK symbol graph):
//   "A shape whose corners you configure, individually or uniformly, to be
//    squared, rounded, or concentric relative to a container shape's corners."
//   Edge.Corner.Style.concentric: "the system calculates the corner radius to
//    equal the container shape's corner radius minus the distance between
//    corners. When the system calculates a zero radius, the corner is square."
//   `isUniform: false` in rect(corners:isUniform:) => each corner may resolve
//    to a different radius; `true` => largest radius is applied to all four.
//   RoundedRectangle/UEN/Rectangle/Circle all conform to RoundedRectangularShape
//    (macOS 26.0). ConcentricRectangle does NOT conform; it *consumes* the
//    container shape declared by `.containerShape(...)`.
//
// EVERYTHING here is macOS 26.0+ except RectangleCornerRadii/UnevenRoundedRectangle
// (macOS 13/14) which are included as the pre-26 fallback for per-corner radii.

import SwiftUI

// MARK: - 4.1 ConcentricRectangle construction

struct ConcentricRectangleGallery: View {
    var body: some View {
        VStack(spacing: 12) {
            Color.accentColor.opacity(0.25)
                .frame(height: 40)
                .clipShape(ConcentricRectangle())                       // all corners .concentric

            Color.accentColor.opacity(0.25)
                .frame(height: 40)
                .clipShape(ConcentricRectangle(corners: .fixed(12)))     // fixed uniform radius

            Color.accentColor.opacity(0.25)
                .frame(height: 40)
                .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))

            Color.accentColor.opacity(0.25)
                .frame(height: 40)
                .clipShape(
                    // top corners fixed 8pt, bottom corners concentric to container.
                    ConcentricRectangle(
                        topLeadingCorner: .fixed(8),
                        topTrailingCorner: .fixed(8),
                        bottomLeadingCorner: .concentric,
                        bottomTrailingCorner: .concentric
                    )
                )

            Color.accentColor.opacity(0.25)
                .frame(height: 40)
                .clipShape(
                    ConcentricRectangle(
                        uniformTopCorners: .fixed(10),
                        uniformBottomCorners: .concentric(minimum: .fixed(4))
                    )
                )

            // Shape.rect(…) static factories — useful when a modifier wants
            // `some Shape` and you do not want a local variable.
            Color.accentColor.opacity(0.25)
                .frame(height: 40)
                .clipShape(.rect(corners: .fixed(16)))
        }
        .padding(20)
        .containerShape(.rect(cornerRadius: 24)) // declares this stack's own corners
    }
}

// MARK: - 4.2 The real concentric-nesting recipe (cards inside a popover)

/// Root: one `.containerShape(.rect(cornerRadius: ...))` declares the container
/// radius. Every nested card uses `ConcentricRectangle(corners: .concentric)`
/// and the system resolves `r_child = r_container - inset` per corner.
struct ConcentricNestingDemo: View {
    private let popoverRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 10) {
            header
            playlistCard
        }
        .padding(12)
        .containerShape(.rect(cornerRadius: popoverRadius))
        // Optional: paint the popover surface (the system popover already has
        // its own material; this is for the borderless-window variant).
        .background(.ultraThinMaterial, in: ConcentricRectangle(corners: .concentric))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .frame(width: 40, height: 40)
                .background(.quaternary, in: ConcentricRectangle(corners: .concentric))
            VStack(alignment: .leading, spacing: 2) {
                Text("夜航").font(.headline)
                Text("净听 · 无损").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        // Nested card: one inset level below the popover edge.
        .background(.regularMaterial, in: ConcentricRectangle(corners: .concentric))
    }

    private var playlistCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("播放队列").font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(0..<3, id: \.self) { i in
                HStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 32, height: 32)
                    Text("曲目 \(i + 1)")
                    Spacer()
                    Image(systemName: "waveform").foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        // One more concentric level: still resolves against the root
        // containerShape radius minus this card's distance from the edge.
        .background(.regularMaterial, in: ConcentricRectangle(corners: .concentric))
    }
}

// MARK: - 4.3 RoundedRectangularShape: generic code + corners(in:)

/// Escape hatch when you need the *resolved* radii (e.g. to draw a matching
/// stroke or to animate). `corners(in:)` returns nil when the shape has no
/// corner information.
struct ResolvedCornersProbe<ContainerShape: RoundedRectangularShape>: View {
    let containerShape: ContainerShape
    let size: CGSize

    var body: some View {
        let corners: RoundedRectangularShapeCorners =
            containerShape.corners(in: size) ?? .concentric

        return VStack(alignment: .leading, spacing: 4) {
            Text("topLeading: \(String(describing: corners.topLeading))")
            Text("bottomTrailing: \(String(describing: corners.bottomTrailing))")
            Text("radius(topLeading): \(String(describing: corners[.topLeading]))")
        }
        .font(.caption2.monospaced())
        .padding(12)
    }
}

// MARK: - 4.4 Corner insets, safe-area-free corner avoidance

struct CornerOffsetDemo: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
            Text("角落里的浮层")
                .padding(8)
                .glassEffect(in: .rect(cornerRadius: 10))
                .padding(8)
                // Keep custom chrome out of the window/presentation corner
                // insets (macOS 26, incl. window radii and system UI).
                .containerCornerOffset(.all)
        }
        // EdgeInsets can be adjusted for corner insets too:
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
            .inset(by: RectangleCornerInsets()))
    }
}

// MARK: - 4.5 Pre-26 fallback: per-corner radii without ConcentricRectangle

struct LegacyPerCornerRadii: View {
    var body: some View {
        VStack(spacing: 8) {
            // RectangleCornerRadii is a plain value type (macOS 10.15), not a
            // View — feed it to UnevenRoundedRectangle / Shape.rect(cornerRadii:).
            let radii = RectangleCornerRadii(
                topLeading: 12, bottomLeading: 12,
                bottomTrailing: 4, topTrailing: 4
            )
            Text("topLeading radius: \(radii.topLeading)")

            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 12, bottomLeading: 12,
                    bottomTrailing: 4, topTrailing: 4
                ),
                style: .continuous
            )
            .fill(.quaternary)
            .frame(height: 32)

            // Just a description of each corner's radius for debugging:
            Text("per-corner OK")
        }
        .padding(20)
    }
}

// MARK: - 4.6 What NOT to do

/// ConcentricRectangle is a Shape, not a RoundedRectangularShape. Passing it to
/// `.containerShape(_:)` does not compile:
///
///     .containerShape(ConcentricRectangle(corners: .fixed(20)))   // ✗
///     error: 'containerShape' requires that 'ConcentricRectangle'
///            conform to 'RoundedRectangularShape'
///
/// Pass a real RoundedRectangularShape (RoundedRectangle / Capsule / Circle /
/// UnevenRoundedRectangle) to `.containerShape(...)`, then use
/// ConcentricRectangle *inside* to inherit the corners.
struct RoundContainerShapeCorrectly: View {
    var body: some View {
        Color.clear
            .frame(height: 40)
            .containerShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
