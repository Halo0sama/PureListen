// AppKitGlassViews.swift — §9: AppKit Liquid Glass views (macOS 26) and the
// macOS 27 view-corner API.
//
// Ground truth (SDK MacOSX27.0.sdk, AppKit headers):
//   NSGlassEffectView.h
//     NSGlassEffectView                                    macOS 26.0
//       contentView: NSView?
//       cornerRadius: CGFloat
//       tintColor: NSColor?
//       style: NSGlassEffectView.Style { .regular, .clear }
//       effectIsInteractive: Bool                          macOS 27.0  ← only 27 API here
//     NSGlassEffectContainerView                           macOS 26.0
//       contentView: NSView? ; spacing: CGFloat
//   NSBackgroundExtensionView.h                            macOS 26.0
//       contentView ; automaticallyPlacesContentView
//   NSVisualEffectView.h                                   macOS 10.10 (unchanged in 26/27)
//       material: NSVisualEffectMaterial {.titlebar,.selection,.menu,.popover,
//         .sidebar,.headerView,.sheet,.windowBackground,.hudWindow,.fullScreenUI,
//         .toolTip,.contentBackground,.underWindowBackground,.underPageBackground}
//       blendingMode, state, emphasized, maskImage
//   NSView.h (NSViewCornerConfigurations)                  macOS 27.0
//       readonly var cornerConfiguration: NSViewCornerConfiguration?
//       readonly var effectiveCornerRadii: NSViewCornerRadii?
//       func viewDidChangeEffectiveCornerRadii()          (override hook)
//       func invalidateCornerConfiguration()
//   NSViewCornerConfiguration.h / NSViewCornerRadius.h / NSViewCornerRadii.h
//       NSViewCornerRadius: .fixed(_:) / .containerConcentric(_:) / .containerConcentric
//       NSViewCornerConfiguration: .corners(radius:), .corners(topLeftRadius:…),
//         .capsule, .capsule(maximumRadius:), .uniformCorners(radius:),
//         .uniformEdges(topRadius:bottomRadius:), .uniformTopRadius(_:…), etc.
//       NSViewCornerRadii: readonly CGFloat topLeft/topRight/bottomLeft/bottomRight
//
// GOTCHA (verified by compiling): `NSView.cornerConfiguration` is a *get-only*
// property in Swift as well ("cannot assign to property: 'cornerConfiguration'
// is a get-only property"). The supported way to provide a configuration is to
// override the getter in an NSView subclass; AppKit then calls
// `viewDidChangeEffectiveCornerRadii()` when the resolved radii change.
//
// Note: AppKit.tbd also exports NSGlassEffectViewMaterialContext and
// NSGlassEffectDiffusionDidChangeNotification, but neither is declared in any
// public 27.0 SDK header — treat as SPI, do not link against them.

import SwiftUI
import AppKit

// MARK: - 9.1 NSGlassEffectView bridged into SwiftUI

@available(macOS 26.0, *)
struct GlassEffectBackground: NSViewRepresentable {
    var style: NSGlassEffectView.Style = .regular
    var cornerRadius: CGFloat = 16
    var tintColor: NSColor?
    /// macOS 27-only: visual response for interactive containers.
    /// On macOS 26 this stays false.
    var isInteractive: Bool = false

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        view.tintColor = tintColor
        view.style = style
        if #available(macOS 27.0, *) {
            view.effectIsInteractive = isInteractive
        }
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.tintColor = tintColor
        view.style = style
        if #available(macOS 27.0, *) {
            view.effectIsInteractive = isInteractive
        }
    }
}

/// The AppKit glass *background* with SwiftUI content inside. On macOS 26 use
/// the SwiftUI `.glassEffect` instead; this exists for cases that must embed
/// NSView hierarchies (e.g. NSStatusItem popover window content).
@available(macOS 26.0, *)
struct AppKitGlassHost<Content: View>: NSViewRepresentable {
    var style: NSGlassEffectView.Style = .regular
    var cornerRadius: CGFloat = 14
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.style = style
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = hosting
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        glass.cornerRadius = cornerRadius
        glass.style = style
        (glass.contentView as? NSHostingView<Content>)?.rootView = content
    }
}

// MARK: - 9.2 NSGlassEffectContainerView (merging glass descendants)

@available(macOS 26.0, *)
final class GlassClusterView: NSView {
    private let containerView = NSGlassEffectContainerView()

    init(spacing: CGFloat) {
        super.init(frame: .zero)
        containerView.spacing = spacing
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Put NSGlassEffectView (or plain NSView) descendants into this view.
    func setContent(_ view: NSView) {
        containerView.contentView = view
    }
}

// MARK: - 9.3 NSBackgroundExtensionView (AppKit counterpart of the SwiftUI effect)

@available(macOS 26.0, *)
final class BackgroundExtensionHost: NSView {
    let extensionView = NSBackgroundExtensionView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        extensionView.translatesAutoresizingMaskIntoConstraints = false
        extensionView.automaticallyPlacesContentView = true
        addSubview(extensionView)
        NSLayoutConstraint.activate([
            extensionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            extensionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            extensionView.topAnchor.constraint(equalTo: topAnchor),
            extensionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func setContent(_ view: NSView) {
        extensionView.contentView = view
    }
}

// MARK: - 9.4 NSVisualEffectView materials (the pre-26 path, still valid)

@available(macOS 10.10, *)
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
    }
}

/// All semantic materials available on macOS 27 (unchanged since 10.14).
enum VisualEffectMaterials {
    static let all: [NSVisualEffectView.Material] = [
        .titlebar, .selection, .menu, .popover, .sidebar,
        .headerView, .sheet, .windowBackground, .hudWindow,
        .fullScreenUI, .toolTip, .contentBackground,
        .underWindowBackground, .underPageBackground
    ]
}

// MARK: - 9.5 macOS 27: view corner configuration (override-based)

@available(macOS 27.0, *)
final class ConcentricPanelView: NSView {
    /// Override the read-only property to publish a corner configuration.
    override var cornerConfiguration: NSViewCornerConfiguration? {
        .uniformTopRadius(
            .fixed(20),
            bottomLeftRadius: .containerConcentric,
            bottomRightRadius: .containerConcentric
        )
    }

    /// AppKit calls this whenever the resolved radii change (window moves to
    /// another screen, container resizes, user changes global radius, …).
    override func viewDidChangeEffectiveCornerRadii() {
        guard let radii = effectiveCornerRadii else { return }
        layer?.cornerRadius = radii.topLeft
        // For per-corner shapes: build a CGPath from the four radii.
        _ = (radii.topRight, radii.bottomLeft, radii.bottomRight)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Call after changing anything the configuration depends on.
    func refreshCorners() {
        invalidateCornerConfiguration()
    }
}

/// All documented builders of NSViewCornerConfiguration — compile coverage.
@available(macOS 27.0, *)
enum ViewCornerConfigurationCatalog {
    static func all() -> [NSViewCornerConfiguration] {
        let fixed = NSViewCornerRadius.fixed(12)
        let concentric = NSViewCornerRadius.containerConcentric(8)
        let bareConcentric: NSViewCornerRadius = .containerConcentric

        return [
            .corners(radius: fixed),
            .corners(topLeftRadius: fixed, topRightRadius: concentric,
                     bottomLeftRadius: bareConcentric, bottomRightRadius: nil),
            .capsule,
            .capsule(maximumRadius: 24),
            .uniformCorners(radius: fixed),
            .uniformCorners(radius: fixed, topLeftRadius: concentric,
                            topRightRadius: nil, bottomLeftRadius: nil, bottomRightRadius: nil),
            .uniformEdges(topRadius: fixed, bottomRadius: concentric),
            .uniformEdges(leftRadius: fixed, rightRadius: concentric),
            .uniformTopRadius(fixed, bottomLeftRadius: concentric, bottomRightRadius: nil),
            .uniformBottomRadius(fixed, topLeftRadius: nil, topRightRadius: concentric),
            .uniformLeftRadius(fixed, topRightRadius: concentric, bottomRightRadius: nil),
            .uniformRightRadius(fixed, topLeftRadius: nil, bottomLeftRadius: concentric)
        ]
    }
}
