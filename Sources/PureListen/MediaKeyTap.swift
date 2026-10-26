import AppKit
import Carbon.HIToolbox
import PureListenCore

final class MediaKeyTap {
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onVolumeChange: ((Float) -> Void)?   // 正=增大
    var onMuteToggle: (() -> Void)?
    /// 事件时判断: 是否拦截音量键(播放中拦截, 防止系统重写硬件音量引发扬声器爆音)。
    var shouldInterceptVolume: (() -> Bool)?
    var shouldInterceptPlayback: (() -> Bool)?

    struct KeyEvent: Equatable {
        let code: Int
        let isDown: Bool
        init?(data1: Int, subtype: Int) {
            guard subtype == 8 else { return nil }
            let state = (data1 >> 8) & 0xFF
            guard state == 0x0A || state == 0x0B else { return nil }
            code = (data1 >> 16) & 0xFFFF
            isDown = state == 0x0A
        }
    }

    var isEnabled = false {
        didSet {
            if isEnabled { start() } else { stop() }
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    static func hasPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func start() {
        guard eventTap == nil else { return }
        // 没有辅助功能权限时静默跳过（不主动弹系统授权窗，授权入口在设置页）。
        guard Self.hasPermission() else { return }
        let mask = 1 << NX_SYSDEFINED
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
            let mySelf = Unmanaged<MediaKeyTap>.fromOpaque(refcon!).takeUnretainedValue()
            return mySelf.handle(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
                CFRunLoopSourceInvalidate(runLoopSource)
            }
            CFMachPortInvalidate(tap)
            runLoopSource = nil
            eventTap = nil
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if (type == .tapDisabledByTimeout || type == .tapDisabledByUserInput), let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return nil
        }
        // NX_SYSDEFINED = 14
        guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              let key = KeyEvent(data1: nsEvent.data1, subtype: Int(nsEvent.subtype.rawValue)) else {
            return Unmanaged.passUnretained(event)
        }
        return handleKey(key) ? nil : Unmanaged.passUnretained(event)
    }

    @discardableResult
    func handleKey(_ key: KeyEvent) -> Bool {
        let keyCode = key.code
        let keyDown = key.isDown

        if shouldInterceptVolume?() ?? false {
            let step: Float = 1.0 / 16.0
            switch keyCode {
            case 0:
                if keyDown { onVolumeChange?(step) }
                return true
            case 1:
                if keyDown { onVolumeChange?(-step) }
                return true
            case 7:
                if keyDown { onMuteToggle?() }
                return true
            default:
                break
            }
        }
        guard shouldInterceptPlayback?() ?? true else { return false }
        switch keyCode {
        case 16:
            if keyDown { onPlayPause?() }
            return true
        case 17, 19:
            if keyDown { onNext?() }
            return true
        case 18, 20:
            if keyDown { onPrevious?() }
            return true
        default:
            return false
        }
    }
}
