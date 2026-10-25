import AppKit
import Carbon.HIToolbox

/// 播放控制媒体键接管: 拦截 播放/暂停、上一曲、下一曲, 驱动本 App 播放控制。
/// 音量键不拦截(由系统音量镜像联动)。需要"辅助功能"权限。
final class MediaKeyTap {
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onVolumeChange: ((Float) -> Void)?   // 正=增大
    var onMuteToggle: (() -> Void)?
    /// 事件时判断: 是否拦截音量键(播放中拦截, 防止系统重写硬件音量引发扬声器爆音)。
    var shouldInterceptVolume: (() -> Bool)?

    var isEnabled = false {
        didSet {
            if isEnabled { start() } else { stop() }
        }
    }

    private var eventTap: CFMachPort?

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
        guard Self.hasPermission() else {
            Self.requestPermission()
            return
        }
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
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0),
                           .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopSourceInvalidate(CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0))
            eventTap = nil
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout, let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return nil
        }
        // NX_SYSDEFINED = 14
        guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined, let sysInt = nsEvent.data1 as? Int else {
            return Unmanaged.passRetained(event)
        }
        let keyCode = sysInt & 0xFFFF
        let keyFlags = (sysInt >> 16) & 0xFFFF
        let keyDown = keyFlags == 0x0A   // NX_KEYDOWN

        // SOUND_DOWN=0 SOUND_UP=1 MUTE=7 PLAY=16 NEXT=17 PREVIOUS=18 FAST=19 REWIND=20
        if shouldInterceptVolume?() ?? false {
            let step: Float = 1.0 / 16.0
            switch keyCode {
            case 0:
                if keyDown { onVolumeChange?(-step) }
                return nil
            case 1:
                if keyDown { onVolumeChange?(step) }
                return nil
            case 7:
                if keyDown { onMuteToggle?() }
                return nil
            default:
                break
            }
        }
        switch keyCode {
        case 16:
            if keyDown { onPlayPause?() }
            return nil
        case 17, 19:
            if keyDown { onNext?() }
            return nil
        case 18, 20:
            if keyDown { onPrevious?() }
            return nil
        default:
            return Unmanaged.passRetained(event)
        }
    }
}

/// 系统静音控制(用 mute 而非音量归零: 百分比保留, 音量联动不受影响)。
enum SystemMute {
    static func setMuted(_ muted: Bool) {
        let script = NSAppleScript(source: "set volume output muted \(muted)")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
    }

    static func isMuted() -> Bool {
        guard let script = NSAppleScript(source: "output muted of (get volume settings)") else { return false }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error).stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output == "true"
    }
}
