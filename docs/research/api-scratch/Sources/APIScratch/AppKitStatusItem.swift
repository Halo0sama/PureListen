// AppKitStatusItem.swift — §11: NSStatusItem + the macOS 27 expanded-interface
// session API (the modern menu-bar popover lifecycle).
//
// Ground truth (SDK MacOSX27.0.sdk, AppKit headers):
//   NSStatusItem.h
//     statusItem(withLength:) with NSStatusItem.variableLength
//     button: NSStatusBarButton?  (image, appearsDisabled, toolTip, target/action)
//     menu: NSMenu?               (if set, AppKit handles the "expanded menu")
//     behavior: [.removalAllowed, .terminationOnRemoval]        macOS 10.12
//     autosaveName: NSStatusItemAutosaveName                    macOS 10.12
//     visible / isVisible                                       macOS 10.12
//     expandedInterfaceDelegate: NSStatusItemExpandedInterfaceDelegate?   macOS 27.0
//     expandedInterfaceSession: NSStatusItemExpandedInterfaceSession?     macOS 27.0
//   NSStatusItemExpandedInterfaceDelegate.h (part of NSStatusItem.h)      macOS 27.0
//     -statusItem:didBeginExpandedInterfaceSession:
//     -statusItemDidEndExpandedInterfaceSession:animated:
//   NSStatusItemExpandedInterfaceSession.h
//     -cancel
//
// Header doc comment (NSStatusItem.h, macOS 27.0), worth quoting because it is
// exactly PureListen's use case:
//   "Status items which do not use an NSMenu but instead position other windows
//    ('expanded interface') relative to the item should begin showing their
//    expanded interface upon receipt of this message. This method should be
//    used instead of manually toggling your interface by target/action handling
//    on the button or item. ... This allows the status item to participate in
//    keyboard navigation and menu tracking behaviors."
//
// Practical rule:
//   macOS 27 → set expandedInterfaceDelegate and show/hide the NSWindow/NSPanel
//              from the delegate callbacks; cancel the session when the user
//              dismisses the UI by other means.
//   macOS 13–26 → keep the classic button target/action + NSPopover toggle.
//   A status item with a non-nil `menu` never receives the 27 callbacks.

import SwiftUI
import AppKit

// MARK: - 11.1 Status item creation (works on every deployment target)

@MainActor
final class StatusItemController {
    private(set) var statusItem: NSStatusItem?
    private var popover: NSPopover?
    /// macOS 27: retained delegate for the expanded-interface session.
    private var expandedDelegate: ExpandedInterfaceDelegate?

    func install(popover: NSPopover, target: AnyObject, action: Selector) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "PureListen.MenuBarItem"
        item.behavior = [.removalAllowed]
        if let button = item.button {
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "净听")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "净听 PureListen"
            button.target = target
            button.action = action
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
        self.popover = popover
    }

    var button: NSStatusBarButton? { statusItem?.button }

    /// Classic toggle path — required for macOS 13–26.
    func togglePopover() {
        guard let popover, let button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: macOS 27 expanded-interface session

    /// Wire the macOS 27 delegate; no-op on macOS 26 and earlier.
    func installExpandedInterface(onShow: @escaping () -> Void, onHide: @escaping (Bool) -> Void) {
        if #available(macOS 27.0, *) {
            let delegate = ExpandedInterfaceDelegate(onShow: onShow, onHide: onHide)
            expandedDelegate = delegate
            statusItem?.expandedInterfaceDelegate = delegate
        }
    }

    /// Call when the user dismisses the expanded UI by any other route
    /// (outside click, Escape, transport action that should close the window).
    func cancelExpandedInterface() {
        if #available(macOS 27.0, *) {
            statusItem?.expandedInterfaceSession?.cancel()
        }
    }
}

// MARK: - 11.2 macOS 27 delegate conformance (compiled behind a guard)

@available(macOS 27.0, *)
final class ExpandedInterfaceDelegate: NSObject, NSStatusItemExpandedInterfaceDelegate {
    private let onShow: () -> Void
    private let onHide: (Bool) -> Void

    init(onShow: @escaping () -> Void, onHide: @escaping (Bool) -> Void) {
        self.onShow = onShow
        self.onHide = onHide
    }

    func statusItem(
        _ statusItem: NSStatusItem,
        didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession
    ) {
        onShow()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        onHide(animated)
    }
}

// MARK: - 11.3 Menu-based alternative (no popover window at all)

/// If the UI is small enough to fit an NSMenu, this is the lowest-effort native
/// path: AppKit draws the menu with current system materials automatically.
@MainActor
enum StatusItemMenuBuilder {
    static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "显示/隐藏窗口", action: nil, keyEquivalent: "w")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出净听", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }
}
