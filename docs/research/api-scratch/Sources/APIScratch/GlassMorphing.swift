// GlassMorphing.swift — §2 of the cheat sheet: GlassEffectContainer / morphing.
//
// Ground truth (SDK MacOSX27.0.sdk, SwiftUICore …swiftinterface):
//   11523  @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
//          @available(visionOS, unavailable)
//          struct GlassEffectContainer<Content: View> {
//            init(spacing: CGFloat? = nil, @ContentBuilder content: () -> Content)
//          }
//   22411  func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View
//   12644  func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View
//   3512   func glassEffectTransition(_ transition: GlassEffectTransition) -> some View
//   3498   struct GlassEffectTransition { matchedGeometry / materialize / identity }
//
// Doc-comment highlights extracted from the SDK symbol graph:
//   * GlassEffectContainer: "combines multiple glass shapes into a single shape
//     that can morph individual shapes into one another ... As shapes near one
//     another, their paths start to blend into one another. The higher the
//     spacing, the sooner blending begins as glass approaches each other."
//   * glassEffectTransition(.matchedGeometry): "if a newly appearing shape is
//     within the spacing of any existing shape, it will use that shape's
//     geometry to transition out of."
//   * glassEffectUnion: "All glass effects with the same shape and glass will
//     be combined into a single shape."
//
// All APIs here are macOS 26.0+.

import SwiftUI

// MARK: - 2.1 Container + ID + matchedGeometry (SDK's own example, verbatim shape)

/// The canonical morphing pattern: two glass buttons that merge into one pill.
struct GlassMorphingPlaybackControls: View {
    @Namespace private var namespace
    @State private var isExpanded = false

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill")
                    .frame(width: 36, height: 36)
                    .glassEffect()
                    .glassEffectID("volume", in: namespace)

                if isExpanded {
                    Image(systemName: "list.bullet")
                        .frame(width: 36, height: 36)
                        .glassEffect()
                        .glassEffectID("queue", in: namespace)
                        .glassEffectTransition(.matchedGeometry)
                }

                Button {
                    withAnimation(.spring(duration: 0.35)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "xmark" : "ellipsis")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("toggle", in: namespace)
            }
        }
        .padding(20)
    }
}

// MARK: - 2.2 The three GlassEffectTransition values

struct GlassTransitionGallery: View {
    @Namespace private var namespace
    @State private var showMatched = false
    @State private var showMaterialize = false
    @State private var showIdentity = false

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                // matchedGeometry: shares geometry with nearest glass in container.
                HStack {
                    Image(systemName: "pencil")
                        .frame(width: 40, height: 40)
                        .glassEffect()
                        .glassEffectID("pencil", in: namespace)
                    if showMatched {
                        Image(systemName: "note.text")
                            .frame(width: 40, height: 40)
                            .glassEffect()
                            .glassEffectID("note", in: namespace)
                            .glassEffectTransition(.matchedGeometry)
                    }
                }
                Toggle("matchedGeometry", isOn: $showMatched).toggleStyle(.button)

                // materialize: fades content, animates the material in/out,
                // no geometry matching.
                HStack {
                    Text("A")
                        .frame(width: 40, height: 40)
                        .glassEffect()
                        .glassEffectID("a", in: namespace)
                    if showMaterialize {
                        Text("B")
                            .frame(width: 40, height: 40)
                            .glassEffect()
                            .glassEffectID("b", in: namespace)
                            .glassEffectTransition(.materialize)
                    }
                }
                Toggle("materialize", isOn: $showMaterialize).toggleStyle(.button)

                // identity: no transition at all.
                HStack {
                    Text("C")
                        .frame(width: 40, height: 40)
                        .glassEffect()
                        .glassEffectID("c", in: namespace)
                    if showIdentity {
                        Text("D")
                            .frame(width: 40, height: 40)
                            .glassEffect()
                            .glassEffectID("d", in: namespace)
                            .glassEffectTransition(.identity)
                    }
                }
                Toggle("identity", isOn: $showIdentity).toggleStyle(.button)
            }
        }
        .padding(20)
    }
}

// MARK: - 2.3 glassEffectUnion

/// Two separate views contribute geometry to *one* glass shape. This is the
/// pattern for a segmented "pill" background behind labels.
struct GlassUnionSegmentedPill: View {
    enum Side: Hashable, Sendable { case leading, trailing }

    @Namespace private var namespace
    @State private var selected: Side = .leading

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                segment("暂停", side: .leading)
                segment("继续", side: .trailing)
            }
            .padding(3)
        }
        .padding(20)
    }

    private func segment(_ title: String, side: Side) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .glassEffect(
                .regular.tint(selected == side ? .accentColor : nil),
                in: .rect(cornerRadius: 10)
            )
            .glassEffectUnion(id: "segmented", namespace: namespace)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy) { selected = side }
            }
    }
}

// MARK: - 2.4 Container spacing: "the higher the spacing, the sooner blending"

/// Use one container per visual cluster. Do not wrap the whole popover in a
/// single huge container: the container merges *all* glass inside it.
struct GlassSpacingComparison: View {
    @Namespace private var namespace

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            spacingRow(label: "spacing: 0", spacing: 0)
            spacingRow(label: "spacing: 12", spacing: 12)
            spacingRow(label: "spacing: 24", spacing: 24)
        }
        .padding(20)
    }

    private func spacingRow(label: String, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption)
            GlassEffectContainer(spacing: spacing) {
                HStack(spacing: 8) {
                    ForEach(0..<3) { i in
                        Circle()
                            .frame(width: 24, height: 24)
                            .glassEffect()
                            .glassEffectID(i, in: namespace)
                    }
                }
            }
        }
    }
}
