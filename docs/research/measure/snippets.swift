import SwiftUI
import AppKit

// ---- SwiftUI: glass, concentric, container, toolbar, scroll edge, buttons ----
@available(macOS 27.0, *)
struct SnippetGlass: View {
    @Namespace private var ns
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 8) {
            Text("净听")
                .font(.headline)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

            Button("Play") {}.buttonStyle(.glass)
            Button("Pause") {}.buttonStyle(.glassProminent)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "backward.fill")
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("back", in: ns)
                    if expanded {
                        Image(systemName: "forward.fill")
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .glassEffectID("fwd", in: ns)
                            .glassEffectTransition(.materialize)
                    }
                }
            }
            .animation(.snappy, value: expanded)

            ConcentricRectangle()
                .fill(.blue)

            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        }
        .padding(16)
        .containerShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .backgroundExtensionEffect()
        .opacity(appearsActive ? 1 : 0.6)
        .environment(\.materialActiveAppearance, .matchWindow)
    }
}

@available(macOS 27.0, *)
struct SnippetScroll: View {
    var body: some View {
        ScrollView {
            LazyVStack { ForEach(0..<50) { i in Text("Row \(i)") } }
                .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { } label: { Image(systemName: "play.fill") }
                Button { } label: { Image(systemName: "pause.fill") }
            }
            .visibilityPriority(.high)
            ToolbarItem(placement: .primaryAction) {
                Button { } label: { Image(systemName: "gearshape") }
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

@available(macOS 27.0, *)
struct SnippetSymbols: View {
    @State private var playing = false
    var body: some View {
        VStack {
            Image(systemName: "waveform")
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.variableColor.iterative, isActive: playing)
                .imageScale(.medium)
                .font(.system(size: 13, weight: .medium))
            Image(systemName: "speaker.wave.2.fill")
                .symbolEffect(.bounce, value: playing)
                .symbolEffect(.pulse, isActive: playing)
            Text("01:23").font(.caption2).monospacedDigit()
            Text("01:23").font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
}

// ---- AppKit: glass view, corner configuration, status item expanded interface ----
@available(macOS 27.0, *)
final class SnippetAppKit: NSObject, NSStatusItemExpandedInterfaceDelegate {
    func makeGlass() -> NSView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 16
        glass.tintColor = nil
        glass.effectIsInteractive = true
        glass.contentView = NSView()
        return glass
    }
    final class ConcentricCard: NSView {
        override var cornerConfiguration: NSViewCornerConfiguration? {
            get { .uniformCorners(radius: .containerConcentric(12)) }
        }
    }
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {}
    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {}
    func configure(item: NSStatusItem) {
        item.expandedInterfaceDelegate = self
        item.button?.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "净听")
    }
}

// ---- appearance / accessibility detection ----
func appearanceProbe() {
    let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    print(reduce, contrast)
}
func compileCheck() { print("snippets compile") }
