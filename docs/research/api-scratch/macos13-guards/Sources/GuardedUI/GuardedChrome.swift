// GuardedChrome.swift — macOS 13 deployment: guards for the macOS 14/15/26
// chrome APIs.
//
// Availability ladder actually needed at `platforms: [.macOS(.v13)]`:
//   macOS 13 (no guard): RoundedRectangle(.continuous), UnevenRoundedRectangle,
//                        RectangleCornerRadii, .tracking, .fontDesign, .fontWidth,
//                        Image(systemName:variableValue:), toolbar(.windowToolbar),
//                        NSHostingView.sizingOptions/.safeAreaRegions
//   macOS 14: containerBackground, symbolEffect, contentTransition(.symbolEffect),
//             NSPopover.hasFullSizeContent, Color.Resolved? (no: 14? keep guarded)
//   macOS 15: toolbarBackgroundVisibility, Color.mix, materialActiveAppearance
//   macOS 26: backgroundExtensionEffect, scrollEdgeEffectStyle/Hidden,
//             safeAreaBar, GlassEffectContainer, ConcentricRectangle, glassEffect,
//             ToolbarSpacer, sharedBackgroundVisibility, buttonSizing, SymbolValue
//   macOS 27: ToolbarItemVisibilityPriority init(lowerThan:/higherThan:),
//             NSStatusItem expanded interface, NSViewCornerConfiguration,
//             NSGlassEffectView.effectIsInteractive
//
// Compile-verified with: swift build   (platforms: [.macOS(.v13)])

import SwiftUI
import AppKit

// MARK: - 1. macOS 26 chrome (isolated behind @available)

@available(macOS 26.0, *)
struct GoldenGateChrome<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                HStack {
                    Text("正在播放")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Spacer()
                    Button { } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.glass)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
    }
}

@available(macOS 26.0, *)
struct GoldenGateBackground<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.backgroundExtensionEffect()
    }
}

// MARK: - 2. Guarded call sites

struct AdaptiveScrollChrome<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GoldenGateChrome { content }
        } else {
            content
                // macOS 13 fallback: no scroll edge effect style API; the
                // default scroll edge behavior is what the OS ships.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack {
                        Text("正在播放")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                        Spacer()
                        Button { } label: { Image(systemName: "play.fill") }
                            .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
        }
    }
}

/// containerBackground(_:for:) itself is macOS 14, BUT the only macOS placement
/// `.window` was introduced in macOS 15 — so at a macOS 13 deployment the guard
/// that matters is 15.0. (Verified: at a 14.0 guard the compiler says
/// "'window' is only available in macOS 15.0 or newer". There is no macOS
/// placement available on 14, so the whole call must sit in the 15 guard.)
struct AdaptiveContainerBackground<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(.thickMaterial, for: .window)
        } else {
            content.background(.thickMaterial)
        }
    }
}

/// toolbarBackgroundVisibility is macOS 15.
struct AdaptiveToolbarBackground<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

/// Color.mix / materialActiveAppearance are macOS 15.
@available(macOS 15.0, *)
struct DialedColorDemo: View {
    var body: some View {
        Color.accentColor
            .mix(with: .black, by: 0.25)
            .materialActiveAppearance(.matchWindow)
            .frame(height: 20)
    }
}

struct AdaptiveColorTweaks: View {
    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                DialedColorDemo()
            } else {
                Color.accentColor.opacity(0.85).frame(height: 20)
            }
        }
    }
}

// MARK: - 3. macOS 27-only toolbar ordering (nested inside the 26 guard)

struct ToolbarVisibilityOrdering<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 27.0, *) {
            content.toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { } label: { Image(systemName: "gearshape") }
                }
                .visibilityPriority(.init(higherThan: .automatic))
                .sharedBackgroundVisibility(.hidden)
            }
        } else if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { } label: { Image(systemName: "gearshape") }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content
        }
    }
}

// MARK: - 4. Fallback window chrome that works on macOS 13

struct LegacyPanelBackground<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                VisualEffectView(material: .popover)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

/// Minimal NSVisualEffectView bridge (macOS 10.10+, no guard needed).
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}
