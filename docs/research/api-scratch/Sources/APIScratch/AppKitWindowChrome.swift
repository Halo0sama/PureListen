// AppKitWindowChrome.swift — §10: NSWindow / NSPopover chrome for a menu-bar
// app and the separate now-playing window.
//
// Ground truth (SDK MacOSX27.0.sdk, AppKit headers):
//   NSWindow.h
//     styleMask (.borderless, .fullSizeContentView, .titled, …)        macOS 10.0
//     isOpaque / backgroundColor / hasShadow                          macOS 10.0
//     titlebarAppearsTransparent                                       macOS 10.10
//     titleVisibility: NSWindowTitleVisibility (.hidden)               macOS 10.10
//     toolbarStyle: NSWindowToolbarStyle {.automatic,.expanded,
//        .preference,.unified,.unifiedCompact}                         macOS 11.0
//     titlebarSeparatorStyle: NSTitlebarSeparatorStyle                 macOS 11.0
//     level: NSWindow.Level (.normal/.floating/.statusBar/.popUpMenu…) macOS 10.0
//     collectionBehavior (.canJoinAllSpaces, .fullScreenAuxiliary,
//        .transient, .ignoresCycle)                                   macOS 10.5/10.6
//     animationBehavior (.utilityWindow/.alertPanel/.documentWindow)   macOS 10.7
//     hidesOnDeactivate / isMovableByWindowBackground / isReleasedWhenClosed
//   NSPopover.h
//     behavior: .transient/.semitransient/.applicationDefined         macOS 10.7
//     hasFullSizeContent                                                macOS 14.0
//     contentSize / appearance / animates / contentViewController
//     show(relativeTo:of:preferredEdge:) / close()
//   IMPORTANT: There is NO public NSWindow.cornerRadius / corner-radius API in
//   the 27.0 SDK — NSWindow.h has zero new macOS 26/27 API. System windows and
//   popovers get their radius from the OS (macOS 27 tightened it uniformly).
//   For custom borderless windows: clear background + shadow + clip the
//   SwiftUI content (ConcentricRectangle / RoundedRectangle) or draw an
//   NSView with NSViewCornerConfiguration (macOS 27, see AppKitGlassViews).
//
// SwiftUI interop (SwiftUI …swiftinterface):
//   NSHostingView(rootView:)       macOS 10.15
//     .sizingOptions: NSHostingSizingOptions      macOS 13
//     .safeAreaRegions: SafeAreaRegions           macOS 13
//   NSHostingController(rootView:) macOS 10.15
//   @available(macOS 26.0, *) NSWindow.beginSheet(content:) / endSheet(_:)  ← SwiftUI content
//
// POPOVER GOTCHA: `.glassEffect` inside an NSPopover renders against the
// popover's own vibrant backdrop (the popover itself is an NSVisualEffectView
// with `.popover` material under the hood). Result: the glass reads *milky*
// and loses its edge highlight unless you either (a) put the glass over your
// own saturated content/artwork, or (b) use NSPopover.hasFullSizeContent with
// a full-bleed backdrop you control. This is a rendering/behavior observation
// (marked "inferred" in the cheat sheet where it is not directly provable from
// headers); the compile side is covered here.

import SwiftUI
import AppKit

// MARK: - 10.1 Transparent borderless panel positioned under the status item

/// The macOS-26/27-safe way to build a menu-bar "expanded interface" window if
/// you are not using NSPopover. Content corners are clipped in SwiftUI.
@MainActor
final class MenuBarPanels {
    private var panel: NSWindow?
    private var hosting: NSHostingView<AnyView>?

    func window(content: some View, size: CGSize) -> NSWindow {
        let panel = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true

        // Borderless windows don't get titlebar treatment; for titled variants:
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.toolbarStyle = .unifiedCompact
        panel.titlebarSeparatorStyle = .none
        panel.appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(rootView: AnyView(content))
        host.sizingOptions = [.intrinsicContentSize]
        host.safeAreaRegions = []
        panel.contentView = host

        self.panel = panel
        self.hosting = host
        return panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
    }
}

// MARK: - 10.2 NSPopover configuration (the classic menu-bar popover)

@MainActor
final class PureListenPopover {
    private let popover = NSPopover()

    func configure<Content: View>(content: Content) {
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        popover.contentSize = NSSize(width: 360, height: 560)
        popover.hasFullSizeContent = true                 // macOS 14+
        popover.contentViewController = NSHostingController(rootView: content)
    }

    func show(relativeTo statusButton: NSView) {
        popover.show(relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
    }

    func close() {
        popover.close()
    }

    var isShown: Bool { popover.isShown }
}

// MARK: - 10.3 Separate now-playing window with native titlebar

@MainActor
func makeNowPlayingWindow<Content: View>(content: Content) -> NSWindow {
    let hosting = NSHostingController(rootView: content)
    let window = NSWindow(contentViewController: hosting)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.title = "正在播放"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.toolbarStyle = .unifiedCompact
    window.titlebarSeparatorStyle = .none
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.fullScreenPrimary]
    window.setContentSize(NSSize(width: 420, height: 560))
    window.center()
    return window
}

// MARK: - 10.4 SwiftUI content inside AppKit sheets (macOS 26)

@MainActor
final class SheetPresenter {
    var representation: NSWindow.HostingSheetRepresentation<AnyView>?

    func present(on window: NSWindow, @ViewBuilder content: () -> some View) {
        let rep = window.beginSheet { AnyView(content()) }
        representation = rep
    }

    func dismiss(on window: NSWindow) {
        guard let rep = representation else { return }
        window.endSheet(rep)
        representation = nil
    }
}

// MARK: - 10.5 HDR / display capability queries for artwork glow (optional)

@MainActor
enum DisplayCapabilities {
    static func maxEDR(in window: NSWindow) -> CGFloat {
        window.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0
    }

    static func currentEDR(in window: NSWindow) -> CGFloat {
        window.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0
    }

    /// Only turn on HDR artwork glow on screens that actually report EDR > 1.
    static func supportsHDR(in window: NSWindow) -> Bool {
        maxEDR(in: window) > 1.0
    }
}

// MARK: - 10.6 Keyboard / focus behavior hints for menu-bar windows

/// A borderless NSWindow does not become key by default. Subclass it to accept
/// key status (and thus text fields/keyboard shortcuts inside the popover).
final class MenuBarKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - 10.7 The pre-26 window appearance recipe (for the fallback path)

/// On macOS 13–15 the same visual target is: NSVisualEffectView behind a
/// `RoundedRectangle(cornerRadius: style: .continuous)` clip plus a hairline
/// border. Compiles on all versions; the macOS 26 path replaces the effect
/// view with `.glassEffect`.
struct LegacyWindowChrome<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(VisualEffectBackground(material: .popover))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }
}
