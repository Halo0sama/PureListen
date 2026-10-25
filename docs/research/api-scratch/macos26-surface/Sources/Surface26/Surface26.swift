// Surface26.swift — compile-verified at `platforms: [.macOS("26.0")]`.
//
// This is the reference for the deployment decision actually taken in the app
// manifest (observed 2026-10-26: `platforms: [.macOS("26.0")]`).
//
// At macOS 26.0 deployment you get WITHOUT ANY GUARD:
//   • SwiftUI liquid glass: glassEffect / Glass variants / GlassEffectContainer /
//     glassEffectID / glassEffectUnion / glassEffectTransition /
//     GlassButtonStyle / GlassProminentButtonStyle
//   • ConcentricRectangle / Edge.Corner.Style / RoundedRectangularShapeCorners /
//     containerShape(some RoundedRectangularShape) / containerCornerOffset
//   • backgroundExtensionEffect / scrollEdgeEffectStyle / scrollEdgeEffectHidden /
//     safeAreaBar / ToolbarSpacer / sharedBackgroundVisibility / buttonSizing /
//     controlSize(range) / symbolVariableValueMode / symbolColorRenderingMode /
//     Color.ResolvedHDR / containerCornerOffset / RectangleCornerInsets
//   • AppKit: NSGlassEffectView / NSGlassEffectContainerView /
//     NSBackgroundExtensionView / NSControl.BorderShape / NSTintProminence /
//     NSImage.SymbolConfiguration(variableValueMode:colorRenderingMode:)
//
// STILL NEEDS A GUARD at 26.0 (macOS 26.1 or 27.0):
//   • ToolbarItemVisibilityPriority.low/.high                     macOS 26.1
//   • ToolbarItemVisibilityPriority.init(lowerThan:/higherThan:)  macOS 27.0
//   • NSGlassEffectView.effectIsInteractive                       macOS 27.0
//   • NSViewCornerConfiguration / NSViewCornerRadius / NSViewCornerRadii
//     and NSView.cornerConfiguration/effectiveCornerRadii          macOS 27.0
//   • NSStatusItem.expandedInterfaceDelegate / expandedInterfaceSession macOS 27.0
//   • NSMenuItem.preferredImageVisibility                          macOS 27.0
//   • NSControl.Events new cases                                   macOS 27.0
//   • SwiftUI TabsPickerStyle (.tabs), List reorderable, swipeActions
//     onPresentationChanged, AnyNavigationTransition               macОS 27.0
//
// Build: swift build   (in this directory)
import SwiftUI
import AppKit

// MARK: - No-guard core (all macOS 26.0)

struct Surface26Glass: View {
    @Namespace private var namespace
    @State private var expanded = false

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Label("24-bit / 96 kHz", systemImage: "waveform")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.3)), in: Capsule())
                    .glassEffectID("fmt", in: namespace)

                if expanded {
                    Image(systemName: "speaker.wave.2.fill")
                        .frame(width: 32, height: 32)
                        .glassEffect()
                        .glassEffectID("vol", in: namespace)
                        .glassEffectTransition(.matchedGeometry)
                }

                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "xmark" : "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .glassEffectID("more", in: namespace)
            }
        }
        .buttonSizing(.fitted)
        .controlSize(.small)
    }
}

struct Surface26Shapes: View {
    var body: some View {
        VStack(spacing: 10) {
            Color.accentColor.opacity(0.2)
                .frame(height: 36)
                .clipShape(ConcentricRectangle(corners: .concentric))
            Color.accentColor.opacity(0.2)
                .frame(height: 36)
                .clipShape(ConcentricRectangle(corners: .fixed(12)))
            Color.accentColor.opacity(0.2)
                .frame(height: 36)
                .clipShape(
                    ConcentricRectangle(
                        uniformTopCorners: .fixed(12),
                        uniformBottomCorners: .concentric(minimum: .fixed(4))
                    )
                )
        }
        .padding(12)
        .containerShape(.rect(cornerRadius: 20))
        .containerCornerOffset(.horizontal)
    }
}

struct Surface26Chrome: View {
    var body: some View {
        ScrollView {
            LazyVStack { ForEach(0..<30, id: \.self) { Text("Row \($0)") } }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .scrollEdgeEffectHidden(false, for: .top)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            HStack {
                Text("夜航").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.glass)
            }
            .padding(8)
            .glassEffect()
        }
        .containerBackground(.thickMaterial, for: .window)     // macOS 15+
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar) // macOS 15+
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { } label: { Image(systemName: "gearshape") }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

// MARK: - Guarded macOS 26.1 gear
//
// NOTE: the whole `ToolbarItemVisibilityPriority` *type* is @available(macOS 26.1, *)
// — at a 26.0 deployment you cannot even name the type outside a 26.1 guard.

@available(macOS 26.1, *)
struct Surface26ToolbarPriority: View {
    var body: some View {
        Text("content").toolbar {
            ToolbarItem(placement: .automatic) {
                Button { } label: { Image(systemName: "ellipsis") }
            }
            .visibilityPriority(priority)
        }
    }

    private var priority: ToolbarItemVisibilityPriority {
        if #available(macOS 27.0, *) {
            return .init(higherThan: .automatic)   // 27.0
        } else {
            return .high                            // 26.1
        }
    }
}

struct Surface26ToolbarPriorityCallSite: View {
    var body: some View {
        if #available(macOS 26.1, *) {
            Surface26ToolbarPriority()
        } else {
            Text("content")
        }
    }
}

// MARK: - Guarded macOS 27 gear (compile-verified inside the guard)

@available(macOS 27.0, *)
struct Surface27GlassInteractivity: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = 14
        glass.effectIsInteractive = true        // macOS 27 only
        return glass
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {}
}

@available(macOS 27.0, *)
final class Surface27CornerView: NSView {
    override var cornerConfiguration: NSViewCornerConfiguration? {
        .uniformCorners(radius: .containerConcentric(8))
    }

    override func viewDidChangeEffectiveCornerRadii() {
        layer?.cornerRadius = effectiveCornerRadii?.topLeft ?? 0
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

@available(macOS 27.0, *)
final class Surface27StatusDelegate: NSObject, NSStatusItemExpandedInterfaceDelegate {
    func statusItem(
        _ statusItem: NSStatusItem,
        didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession
    ) {
        // Show the expanded interface window here.
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        // Hide it here.
    }
}

/// Runtime wiring at 26.0 deployment.
@MainActor
func surface26Wiring(statusItem: NSStatusItem, onShow: @escaping () -> Void, onHide: @escaping () -> Void) {
    if #available(macOS 27.0, *) {
        let delegate = Surface27StatusDelegate()
        objc_setAssociatedObject(statusItem, "purelisten.expandedDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        statusItem.expandedInterfaceDelegate = delegate
        statusItem.expandedInterfaceSession?.cancel()
        _ = onShow
        _ = onHide
    } else {
        // macOS 26: classic popover toggle via button target/action.
    }
}
