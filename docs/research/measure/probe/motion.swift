import AppKit
import SwiftUI
import QuartzCore

setvbuf(stdout, nil, _IONBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class Log {
    var samples: [(Double, CGFloat)] = []
    var recording = false
}
let LOG = Log()
var SETX: ((CGFloat) -> Void)?
var CURRENT_ANIM: Animation = .default
var NOANIM = false

struct LoggingOffset: ViewModifier, Animatable {
    var x: CGFloat
    var animatableData: CGFloat {
        get { x }
        set {
            x = newValue
            if LOG.recording { LOG.samples.append((CACurrentMediaTime(), newValue)) }
        }
    }
    func body(content: Content) -> some View { content.offset(x: x) }
}

struct MotionView: View {
    @State private var x: CGFloat = 0
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.blue)
            .frame(width: 40, height: 40)
            .modifier(LoggingOffset(x: x))
            .frame(width: 420, height: 100, alignment: .leading)
            .onAppear {
                SETX = { v in
                    if NOANIM { x = v } else {
                        withAnimation(CURRENT_ANIM) { x = v }
                    }
                }
            }
    }
}

final class D: NSObject, NSApplicationDelegate {
    var win: NSWindow!
    var queue: [(String, Animation)] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        win = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 440, height: 140),
                       styleMask: [.titled], backing: .buffered, defer: false)
        win.title = "motion probe"
        win.contentView = NSHostingView(rootView: MotionView())
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        queue = [
            ("default", .default),
            ("linear0.25", .linear(duration: 0.25)),
            ("easeInOut", .easeInOut),
            ("easeOut0.2", .easeOut(duration: 0.2)),
            ("smooth", .smooth),
            ("smooth0.6", .smooth(duration: 0.6)),
            ("snappy", .snappy),
            ("snappy0.5", .snappy(duration: 0.5)),
            ("bouncy", .bouncy),
            ("bouncy0.6", .bouncy(duration: 0.6)),
            ("spring0.35_0.8", .spring(response: 0.35, dampingFraction: 0.8)),
            ("interactiveSpring", .interactiveSpring()),
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.runNext() }
    }

    func runNext() {
        guard !queue.isEmpty else {
            print("DONE"); fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
            return
        }
        let (name, anim) = queue.removeFirst()
        NOANIM = true
        SETX?(0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            NOANIM = false
            CURRENT_ANIM = anim
            LOG.samples = []
            LOG.recording = true
            SETX?(320)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                LOG.recording = false
                self.report(name, LOG.samples)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.runNext() }
            }
        }
    }

    func report(_ name: String, _ s: [(Double, CGFloat)]) {
        guard let first = s.first, let last = s.last else { print("\(name): NO SAMPLES"); return }
        let target: CGFloat = 320
        var settleIdx = s.count - 1
        for i in stride(from: s.count - 1, through: 0, by: -1) {
            if abs(s[i].1 - target) > 0.5 { settleIdx = min(i + 1, s.count - 1); break }
        }
        let dur = s[settleIdx].0 - first.0
        let overshoot = s.map { $0.1 }.max()! - target
        let firsts = s.prefix(10).map { String(format: "%.0f", $0.1) }.joined(separator: ",")
        let tails = s.suffix(6).map { String(format: "%.1f", $0.1) }.joined(separator: ",")
        print(String(format: "%-18@ n=%3d settle=%.3fs overshoot=%+.2fpt  first:%@  tail:%@", name as NSString, s.count, dur, overshoot, firsts, tails))
    }
}
let d = D()
app.delegate = d
app.run()
