// ChromeEffects.swift — §5: window/popover chrome effects.
//
// Ground truth (SDK MacOSX27.0.sdk, SwiftUI …swiftinterface):
//   15832  @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
//          func backgroundExtensionEffect() -> some View
//   15835  same + backgroundExtensionEffect(isEnabled:)
//   15907  @available(… macOS 26.0 …) struct ScrollEdgeEffectStyle { automatic/hard/soft }
//   15926  func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set)
//   15930  func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all)
//   12820  func toolbarBackgroundVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...)   (macOS 15.0+)
//   16336  func containerBackground(_ style: some ShapeStyle, for: ContainerBackgroundPlacement)      (macOS 14.0+)
//   16311  ContainerBackgroundPlacement: macOS only `.window` (macOS 15.0);
//            `.tabView`, `.navigation`, `.navigationSplitView` are macOS-UNAVAILABLE.
//   22856  @available(… macOS 26.0 …) func safeAreaBar(edge: VerticalEdge, …)  / HorizontalEdge
//   29510  @available(iOS 26.0, macOS 26.0, *) ToolbarSpacer (macOS only)
//    7286  ToolbarContent.sharedBackgroundVisibility(_:)      (macOS 26.0)
//   13362  ToolbarItemVisibilityPriority (macOS 26.1 for .low/.high, 27.0 for init(lowerThan:))
//
// Doc-comment highlights (SDK symbol graph):
//   backgroundExtensionEffect: "The view will be duplicated into mirrored copies
//     which will be placed around the view on any edge with available safe area.
//     Additionally, a blur effect will be applied on top ... This modifier will
//     clip the view to prevent copies from overlapping ... Apply with discretion."
//   scrollEdgeEffect: "By default, a scroll view renders an automatic edge effect."
//   safeAreaBar: like safeAreaInset but also "extends the edge effect of any
//     scroll views affected by the inset safe area."

import SwiftUI

// MARK: - 5.1 backgroundExtensionEffect — now-playing window under the titlebar

/// Use case in PureListen: the separate now-playing window's artwork/gradient
/// should continue under the titlebar/popover edge without a hard seam.
struct NowPlayingBackdrop: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [.indigo.opacity(0.75), .blue.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .backgroundExtensionEffect()

            VStack(alignment: .leading) {
                Text("夜航").font(.title2.bold())
                Text("Artist").foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(minWidth: 320, minHeight: 400)
    }
}

/// Runtime toggle form (e.g. disable when Reduce Transparency is on).
struct ExtendableBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Color.orange.opacity(0.4)
            .backgroundExtensionEffect(isEnabled: !reduceTransparency)
            .frame(height: 200)
    }
}

// MARK: - 5.2 Scroll edge effects (macOS 26)

struct ScrollEdgeEffectDemo: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(0..<40, id: \.self) { i in
                    Text("Row \(i)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 12)
        }
        // .automatic | .hard | .soft
        .scrollEdgeEffectStyle(.soft, for: .all)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollEdgeEffectStyle(.automatic, for: [.bottom])
        // Hide entirely when you draw your own fading mask:
        .scrollEdgeEffectHidden(false, for: .top)
        .scrollEdgeEffectHidden(true, for: [.bottom])
    }
}

// MARK: - 5.3 Toolbar background visibility (macOS 15+) — window toolbar tint

struct WindowToolbarChrome: View {
    @State private var search = ""

    var body: some View {
        List { Text("content") }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

// MARK: - 5.4 containerBackground — only .window exists on macOS

struct WindowContainerBackground: View {
    var body: some View {
        VStack { Text("Now Playing") }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(.ultraThinMaterial, for: .window)      // macOS 15+
            .containerBackground(for: .window) {                        // view-builder form
                LinearGradient(colors: [.black.opacity(0.6), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
    }
}

// MARK: - 5.5 safeAreaBar — persistent now-playing bar (macOS 26)

/// Replaces the old `safeAreaInset` recipe when the bar needs the scroll edge
/// effect to extend behind it.
struct NowPlayingSafeAreaBar: View {
    @State private var isPlaying = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(0..<30, id: \.self) { i in Text("Track \(i)") }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("夜航").font(.system(size: 12, weight: .semibold))
                    Text("净听 · 24bit/96kHz")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { isPlaying.toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(in: .rect(cornerRadius: 0))
        }
    }
}

// MARK: - 5.6 Toolbar composition: spacers, shared background, visibility priority

/// `.toolbar { … }` (plain ToolbarContent): use for sharedBackgroundVisibility
/// and visibilityPriority. Note both modifiers are declared on
/// `ToolbarContent`, so they must be applied to the ToolbarItem, not the Button.
struct ToolbarItemChromeDemo: View {
    var body: some View {
        Text("Window content")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { } label: { Image(systemName: "gearshape") }
                }
                .visibilityPriority(.init(higherThan: .automatic))

                ToolbarItem(placement: .automatic) {
                    Button { } label: { Image(systemName: "ellipsis.circle") }
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}

/// `.toolbar(id:)` (customizable): every element must conform to
/// `CustomizableToolbarContent`, so do not mix plain-ToolbarContent-only
/// modifiers into this builder. ToolbarSpacer is customizable.
struct CustomizableToolbarDemo: View {
    var body: some View {
        Text("Window content")
            .toolbar(id: "now-playing") {
                ToolbarItem(id: "back") {
                    Button { } label: { Image(systemName: "chevron.left") }
                }
                ToolbarSpacer(.fixed)
                ToolbarItem(id: "title") {
                    Text("夜航").font(.headline)
                }
                ToolbarSpacer(.flexible, placement: .automatic)
                ToolbarItem(id: "more") {
                    Button { } label: { Image(systemName: "ellipsis.circle") }
                }
            }
    }
}

// MARK: - 5.7 Common gotchas, as compiling counter-examples

/// 1. `containerBackground(for: .navigation)` / `.tabView` / `.navigationSplitView`
///    are unavailable on macOS — only `.window` compiles. (Verified: error
///    "'navigation' is unavailable in macOS" from the SDK availability attrs.)
/// 2. `.toolbarBackgroundVisibility` needs a *window* toolbar placement:
///    `.windowToolbar` is the macOS-only ToolbarPlacement.
/// 3. backgroundExtensionEffect needs available safe area to extend into; it is
///    a no-op on a view that already fills its container edge-to-edge.
struct ChromeGotchaNotes: View { var body: some View { EmptyView() } }
