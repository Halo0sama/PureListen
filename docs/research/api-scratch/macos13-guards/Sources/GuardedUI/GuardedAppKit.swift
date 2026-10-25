// GuardedAppKit.swift — macOS 13 deployment: AppKit glass, view corners,
// window/popover chrome, and the macOS 27 status-item expanded-interface API.
//
// Availability ladder:
//   macOS 10.10+ (no guard): NSVisualEffectView + materials
//   macOS 10.15+ (no guard): NSHostingView / NSHostingController
//   macOS 11.0+ (no guard at 13): window.toolbarStyle(11), titlebarSeparatorStyle(11)
//   macOS 13.0+ (deployment): NSToolbarItem.badge? (26), NSWindow.collectionBehavior
//   macOS 14.0: NSPopover.hasFullSizeContent
//   macOS 15.0: (no AppKit item used here)
//   macOS 26.0: NSGlassEffectView, NSGlassEffectContainerView,
//               NSBackgroundExtensionView, NSControl.BorderShape,
//               NSTintProminence, NSImage.SymbolConfiguration(variableValueMode:)
//   macOS 27.0: NSGlassEffectView.effectIsInteractive,
//               NSViewCornerConfiguration/Radius/Radii,
//               NSStatusItem.expandedInterfaceDelegate/session,
//               NSMenuItem.preferredImageVisibility, AppKit control events
//
// Compile-verified with: swift build   (platforms: [.macOS(.v13)])

import SwiftUI
import AppKit

// MARK: - 1. NSGlassEffectView behind a macOS 26 guard

@available(macOS 26.0, *)
struct AppKitGlassBackground: NSViewRepresentable {
    var style: NSGlassEffectView.Style = .regular
    var cornerRadius: CGFloat = 14
    /// macOS 27 only — applied only after a nested availability check.
    var interactive: Bool = false

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.style = style
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = interactive
        }
        return glass
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.style = style
        if #available(macOS 27.0, *) {
            view.effectIsInteractive = interactive
        }
    }
}

/// Call-site guard for the AppKit glass background.
struct AdaptiveAppKitGlass<Content: View>: View {
    var cornerRadius: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            ZStack {
                AppKitGlassBackground(cornerRadius: cornerRadius)
                content
            }
        } else {
            ZStack {
                VisualEffectView(material: .popover)
                content
            }
        }
    }
}

// MARK: - 2. macOS 27 view corner configuration

@available(macOS 27.0, *)
final class ConcentricCornersPanel: NSView {
    override var cornerConfiguration: NSViewCornerConfiguration? {
        .uniformCorners(radius: .containerConcentric(10))
    }

    override func viewDidChangeEffectiveCornerRadii() {
        guard let radii = effectiveCornerRadii else { return }
        layer?.cornerRadius = radii.topLeft
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func invalidate() { invalidateCornerConfiguration() }
}

/// Factory with a version fallback: plain CALayer radius on macOS 13–26.
@MainActor
func makePanelView(cornerRadius: CGFloat) -> NSView {
    if #available(macOS 27.0, *) {
        let panel = ConcentricCornersPanel()
        panel.wantsLayer = true
        panel.layer?.cornerRadius = cornerRadius
        return panel
    } else {
        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.cornerRadius = cornerRadius
        panel.layer?.cornerCurve = .continuous
        panel.layer?.masksToBounds = true
        return panel
    }
}

// MARK: - 3. AppKit controls: macOS 26 additions

@available(macOS 26.0, *)
func configureGoldenGateControls(button: NSButton, slider: NSSlider, field: NSTextField) {
    button.borderShape = .capsule          // NSControl.BorderShape (26.0)
    button.tintProminence = .primary       // NSTintProminence (26.0)
    slider.tintProminence = .secondary
    slider.neutralValue = 0.5              // NSSlider.neutralValue (26.0)
    field.borderShape = .roundedRectangle
    field.placeholderStrings = ["搜索歌曲", "搜索歌手", "搜索专辑"]  // 26.0
}

func adaptiveControlTint(button: NSButton, slider: NSSlider) {
    if #available(macOS 26.0, *) {
        configureGoldenGateControls(button: button, slider: slider, field: NSTextField())
    } else {
        button.bezelStyle = .rounded
        slider.trackFillColor = .controlAccentColor
    }
}

// MARK: - 4. macOS 27: status item expanded-interface delegate

@available(macOS 27.0, *)
final class GuardedExpandedInterfaceDelegate: NSObject, NSStatusItemExpandedInterfaceDelegate {
    var onBegin: (NSStatusItemExpandedInterfaceSession) -> Void = { _ in }
    var onEnd: (Bool) -> Void = { _ in }

    func statusItem(
        _ statusItem: NSStatusItem,
        didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession
    ) {
        onBegin(expandedInterfaceSession)
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        onEnd(animated)
    }
}

@MainActor
final class AdaptiveStatusItem {
    private(set) var item: NSStatusItem?
    private var delegate: AnyObject?

    func install() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform",
                                           accessibilityDescription: "净听")
        statusItem.button?.image?.isTemplate = true
        item = statusItem

        if #available(macOS 27.0, *) {
            let expanded = GuardedExpandedInterfaceDelegate()
            expanded.onBegin = { _ in
                // show the expanded interface window
            }
            expanded.onEnd = { _ in
                // hide it
            }
            delegate = expanded
            statusItem.expandedInterfaceDelegate = expanded
        } else {
            // macOS 13–26: button target/action + NSPopover toggle.
        }
    }

    func dismissExpandedInterface() {
        if #available(macOS 27.0, *) {
            item?.expandedInterfaceSession?.cancel()
        }
    }
}

// MARK: - 5. Window & popover chrome (macOS 13-safe, with 14/26 upgrades)

@MainActor
func makeNowPlayingWindow<Content: View>(content: Content) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentViewController = NSHostingController(rootView: content)
    window.titlebarAppearsTransparent = true       // macOS 10.10
    window.titleVisibility = .hidden               // macOS 10.10
    window.toolbarStyle = .unifiedCompact          // macOS 11
    window.titlebarSeparatorStyle = .none          // macOS 11
    if #available(macOS 26.0, *) {
        // macOS 26 has no new NSWindow API — the visual upgrade arrives via
        // SwiftUI content (glass, concentric radii, backgroundExtensionEffect).
    }
    return window
}

@MainActor
func makePopover<Content: View>(content: Content) -> NSPopover {
    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 360, height: 560)
    if #available(macOS 14.0, *) {
        popover.hasFullSizeContent = true
    }
    popover.contentViewController = NSHostingController(rootView: content)
    return popover
}

// MARK: - 6. Appearance + accessibility (all versions)

@MainActor
func shouldSoftenGlass() -> Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
}

@MainActor
func isDarkAppearance(_ window: NSWindow) -> Bool {
    window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
}

@MainActor
func usesHighContrast(_ window: NSWindow) -> Bool {
    guard #available(macOS 10.14, *) else { return false }
    let match = window.effectiveAppearance.bestMatch(from: [
        .accessibilityHighContrastAqua,
        .accessibilityHighContrastDarkAqua,
        .aqua, .darkAqua
    ])
    return match == .accessibilityHighContrastAqua
        || match == .accessibilityHighContrastDarkAqua
}
