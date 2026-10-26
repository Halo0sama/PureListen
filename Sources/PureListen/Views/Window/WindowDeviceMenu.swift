import AppKit
import SwiftUI

/// 透明原生菜单按钮覆盖整张设备卡片，保留 SwiftUI 的多行设备信息与完整点击区域。
@MainActor
struct WindowDeviceMenu: NSViewRepresentable {
    let state: AppState
    let deviceName: String

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isTransparent = true
        button.isBordered = false
        button.identifier = NSUserInterfaceItemIdentifier("window-output-device-menu")
        let menu = NSMenu(title: "输出设备")
        menu.autoenablesItems = false
        menu.delegate = context.coordinator
        button.menu = menu
        context.coordinator.menuNeedsUpdate(menu)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.state = state
        button.setAccessibilityLabel("切换输出设备，当前\(deviceName)")
        button.setAccessibilityHelp("选择输出设备；切换后暂停，点击播放继续")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 136, height: proposal.height ?? 64)
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var state: AppState
        init(state: AppState) { self.state = state }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            menu.addItem(withTitle: "输出设备", action: nil, keyEquivalent: "") // 下拉按钮标题项。
            let automatic = NSMenuItem(title: "自动选择", action: #selector(selectAutomatic), keyEquivalent: "")
            automatic.target = self
            automatic.state = state.autoDevice ? .on : .off
            menu.addItem(automatic)
            menu.addItem(.separator())
            if state.devices.isEmpty {
                let empty = NSMenuItem(title: "暂无可用输出设备", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            }
            for device in state.devices {
                let item = NSMenuItem(title: device.name, action: #selector(selectDevice(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device.uid
                item.state = !state.autoDevice && state.selectedDevice?.uid == device.uid ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let refresh = NSMenuItem(title: "刷新设备列表", action: #selector(refreshDevices), keyEquivalent: "")
            refresh.target = self
            menu.addItem(refresh)
            let hint = NSMenuItem(title: "切换后暂停，点击播放继续", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        @objc private func selectAutomatic() { state.autoDevice = true }
        @objc private func selectDevice(_ sender: NSMenuItem) {
            guard let uid = sender.representedObject as? String,
                  let device = state.devices.first(where: { $0.uid == uid }) else { return }
            state.selectDevice(device)
        }
        @objc private func refreshDevices() { state.refreshDevices() }
    }
}
