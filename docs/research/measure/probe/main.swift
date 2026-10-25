import AppKit
import SwiftUI
import CoreText

// ---------- helpers ----------
func dumpFontMetrics() {
    print("== NSFont metrics per text style (pt) ==")
    let styles: [(String, NSFont.TextStyle)] = [
        ("largeTitle", .largeTitle), ("title1", .title1), ("title2", .title2), ("title3", .title3),
        ("headline", .headline), ("body", .body), ("callout", .callout), ("subheadline", .subheadline),
        ("footnote", .footnote), ("caption1", .caption1), ("caption2", .caption2)
    ]
    for (n, s) in styles {
        let f = NSFont.preferredFont(forTextStyle: s)
        print(String(format: "%-11@ size=%4.1f asc=%5.2f desc=%5.2f lead=%5.2f cap=%4.2f xh=%4.2f lineH=%5.2f font=%@",
                     n as NSString, f.pointSize, f.ascender, f.descender, f.leading, f.capHeight, f.xHeight,
                     f.ascender - f.descender + f.leading, f.fontName))
    }
    print("== SF system font metrics ==")
    for size in [11.0, 12.0, 13.0, 15.0, 17.0, 22.0, 26.0] {
        let f = NSFont.systemFont(ofSize: size)
        print(String(format: "size=%5.1f asc=%5.2f desc=%5.2f lead=%5.2f lineH=%5.2f", size, f.ascender, f.descender, f.leading, f.ascender - f.descender + f.leading))
    }
    print("== monospacedDigit system font ==")
    let m = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    print("monospacedDigit 13:", m.fontName, "fixedPitch:", m.isFixedPitch)
    let sfmono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    print("monospaced 12:", sfmono.fontName)
}

// ---------- SwiftUI measurement ----------
@MainActor
func measureHosting<V: View>(_ name: String, _ view: V) {
    let host = NSHostingView(rootView: view)
    host.layoutSubtreeIfNeeded()
    let f = host.fittingSize
    print(String(format: "%-52@ fittingSize = %.2f x %.2f", name as NSString, f.width, f.height))
}

setvbuf(stdout, nil, _IONBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class Delegate: NSObject, NSApplicationDelegate {
    var win: NSWindow!
    var popover: NSPopover!
    var keepAlive: [NSWindow] = []
    func applicationDidFinishLaunching(_ n: Notification) {
        dumpFontMetrics()

        print("\n== SwiftUI control fitting sizes (macOS 27, 2x screen) ==")
        measureHosting("Button(.borderedProminent) regular", Button("Play") {}.buttonStyle(.borderedProminent).controlSize(.regular))
        measureHosting("Button(.borderedProminent) small", Button("Play") {}.buttonStyle(.borderedProminent).controlSize(.small))
        measureHosting("Button(.borderedProminent) large", Button("Play") {}.buttonStyle(.borderedProminent).controlSize(.large))
        measureHosting("Button(.borderedProminent) extraLarge", Button("Play") {}.buttonStyle(.borderedProminent).controlSize(.extraLarge))
        measureHosting("Button(.bordered) regular", Button("Play") {}.buttonStyle(.bordered).controlSize(.regular))
        measureHosting("Button(.bordered) small", Button("Play") {}.buttonStyle(.bordered).controlSize(.small))
        measureHosting("Button(.borderless)", Button("Play") {}.buttonStyle(.borderless))
        measureHosting("Button(.plain)", Button("Play") {}.buttonStyle(.plain))
        measureHosting("Button(.borderedProminent) icon+label", Button { } label: { Label("Play", systemImage: "play.fill") }.buttonStyle(.borderedProminent))
        measureHosting("Button(.borderedProminent) icon only", Button { } label: { Image(systemName: "play.fill") }.buttonStyle(.borderedProminent))
        measureHosting("Toggle(.switch) regular", Toggle("Switch", isOn: .constant(true)).toggleStyle(.switch))
        measureHosting("Toggle(.switch) small", Toggle("Switch", isOn: .constant(true)).toggleStyle(.switch).controlSize(.small))
        measureHosting("Toggle(.checkbox)", Toggle("Checkbox", isOn: .constant(true)).toggleStyle(.checkbox))
        measureHosting("TextField(.roundedBorder)", TextField("Search", text: .constant("")).textFieldStyle(.roundedBorder))
        measureHosting("TextField(.squareBorder)", TextField("Search", text: .constant("")).textFieldStyle(.squareBorder))
        measureHosting("Slider", Slider(value: .constant(0.5)).frame(width: 200))
        measureHosting("ProgressView linear", ProgressView(value: 0.5).frame(width: 200))
        measureHosting("ProgressView circular regular", ProgressView().controlSize(.regular))
        measureHosting("Picker(.segmented)", Picker("Mode", selection: .constant(0)) { Text("One").tag(0); Text("Two").tag(1) }.pickerStyle(.segmented).labelsHidden())
        measureHosting("Picker(.menu)", Picker("Mode", selection: .constant(0)) { Text("One").tag(0); Text("Two").tag(1) }.pickerStyle(.menu))
        measureHosting("Stepper", Stepper("", value: .constant(1), in: 0...10))
        measureHosting("Label(13pt)", Label("Now Playing", systemImage: "music.note"))
        measureHosting("Text(.body)", Text("Body text"))
        measureHosting("Text(.caption2)", Text("Caption2").font(.caption2))
        measureHosting("Glass card 200x120 r16", Color.clear.frame(width: 200, height: 120).glassEffect(.regular, in: .rect(cornerRadius: 16)))
        measureHosting("Glass capsule", Color.clear.frame(width: 120, height: 32).glassEffect(.regular, in: .capsule))

        // ---------- mode ----------
        let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "window"
        print("MODE=\(mode)")

        // standard titled window (no toolbar) metrics
        let plain = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        plain.title = "plain"
        plain.contentView?.layoutSubtreeIfNeeded()
        print("PLAIN titled window: contentLayoutRect=", plain.contentLayoutRect, "frame=", plain.frame, "chrome=", plain.frame.height - plain.contentLayoutRect.height)
        keepAlive.append(plain)

        // unified toolbar window: measure chrome height for each toolbarStyle
        let styleList: [(String, NSWindow.ToolbarStyle)] = [("unified", .unified), ("unifiedCompact", .unifiedCompact), ("expanded", .expanded), ("preference", .preference)]
        for (styleName, style) in styleList {
            let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 400),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            let t = NSToolbar(identifier: "t")
            w.toolbar = t
            w.toolbarStyle = style
            w.title = "t"
            let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
            w.contentView = contentView
            contentView.layoutSubtreeIfNeeded()
            w.toolbar?.validateVisibleItems()
            let chrome = w.frame.height - w.contentLayoutRect.height
            print("TOOLBAR style=\(styleName) raw=\(style.rawValue) windowH=\(w.frame.height) contentLayoutH=\(w.contentLayoutRect.height) chromeH=\(chrome)")
            keepAlive.append(w)
        }

        // Window + toolbar
        let content = NSHostingView(rootView: ProbeContent())
        win = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 860, height: 620),
                       styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                       backing: .buffered, defer: false)
        win.title = "PureListen Design Probe"
        win.toolbarStyle = .unified
        let tb = NSToolbar(identifier: "probe")
        tb.displayMode = .iconOnly
        win.toolbar = tb
        win.contentView = content
        win.center()

        if mode == "window" {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                print("\n== window geometry ==")
                print("window.frame:", self.win.frame)
                print("contentLayoutRect:", self.win.contentLayoutRect)
                print("contentView.frame:", self.win.contentView?.frame ?? .zero)
                print("titlebar container height:", self.win.frame.height - self.win.contentLayoutRect.height)
                if let cv = self.win.contentView, let sv = cv.superview {
                    print("frameView:", type(of: sv), sv.frame)
                    for sub in sv.subviews { print("  themeFrame subview:", type(of: sub), sub.frame) }
                }
                print("screen:", self.win.screen?.frame ?? .zero, "backing:", self.win.backingScaleFactor)
                self.printOwnWindows()
            }
        } else if mode == "popover" {
            win.setContentSize(NSSize(width: 40, height: 40))
            win.title = "anchor"
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            let popContent = NSHostingView(rootView: PopoverContent())
            let vc = NSViewController()
            vc.view = popContent
            self.popover = NSPopover()
            self.popover.contentSize = NSSize(width: 360, height: 560)
            self.popover.behavior = .applicationDefined
            self.popover.animates = false
            self.popover.contentViewController = vc
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let cv = self.win.contentView {
                    self.popover.show(relativeTo: NSRect(x: 0, y: 0, width: 1, height: 1), of: cv, preferredEdge: .maxX)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    print("\n== popover ==")
                    print("popover contentSize:", self.popover.contentSize, "vc view frame:", self.popover.contentViewController?.view.frame ?? .zero)
                    for w in NSApp.windows { print("NSApp.window:", type(of: w), w.frame, "class:", w.className) }
                    self.printOwnWindows()
                }
            }
        } else if mode == "menu" {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                print("\n== menu geometry ==")
                let menu = NSMenu(title: "Track")
                let items: [(String, String)] = [
                    ("play", "Play"), ("pause", "Pause"), ("forward", "Next Track"),
                    ("backward", "Previous Track"), ("speaker.wave.2", "Volume"),
                ]
                for (sym, title) in items {
                    let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    mi.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)
                    menu.addItem(mi)
                }
                menu.addItem(.separator())
                let sub = NSMenu(title: "Output Device")
                sub.addItem(NSMenuItem(title: "MacBook Pro Speakers", action: nil, keyEquivalent: ""))
                sub.addItem(NSMenuItem(title: "External DAC (USB)", action: nil, keyEquivalent: ""))
                let subItem = NSMenuItem(title: "Output Device", action: nil, keyEquivalent: "")
                subItem.submenu = sub
                menu.addItem(subItem)
                menu.popUp(positioning: nil, at: NSPoint(x: 200, y: 500), in: self.win.contentView)
                self.printOwnWindows()
            }
        }
    }

    func printOwnWindows() {
        let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        if let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
            for w in infos where (w[kCGWindowOwnerName as String] as? String ?? "").contains("probe") {
                print("WINDOW id=\(w[kCGWindowNumber as String] ?? -1) name=\(w[kCGWindowName as String] ?? "") bounds=\(w[kCGWindowBounds as String] ?? [:]) layer=\(w[kCGWindowLayer as String] ?? -1)")
            }
        }
        fflush(stdout)
    }
}

struct ProbeContent: View {
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Color.white
                Color(white: 0.5)
                Color.black
            }
            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    Text("glass regular r16").padding(.horizontal, 14).padding(.vertical, 9)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    Text("glass clear r16").padding(.horizontal, 14).padding(.vertical, 9)
                        .glassEffect(.clear, in: .rect(cornerRadius: 16))
                    Text("glass tinted r16").padding(.horizontal, 14).padding(.vertical, 9)
                        .glassEffect(.regular.tint(.blue), in: .rect(cornerRadius: 16))
                }
                .padding(.top, 16)
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Title 2 heading").font(.title2)
                    Text("Body 13 / secondary").font(.body).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Play") {}.buttonStyle(.borderedProminent)
                        Button("Pause") {}.buttonStyle(.bordered)
                        Button("Plain") {}.buttonStyle(.plain)
                        Toggle("Switch", isOn: .constant(true)).toggleStyle(.switch).labelsHidden()
                        Toggle("Check", isOn: .constant(true)).toggleStyle(.checkbox)
                    }
                    HStack(spacing: 10) {
                        TextField("Search", text: .constant("")).textFieldStyle(.roundedBorder).frame(width: 140)
                        Picker("", selection: .constant(0)) { Text("One").tag(0); Text("Two").tag(1) }.pickerStyle(.segmented).labelsHidden().frame(width: 130)
                        Picker("", selection: .constant(0)) { Text("Menu").tag(0); Text("Two").tag(1) }.pickerStyle(.menu).labelsHidden()
                    }
                    HStack(spacing: 10) {
                        Slider(value: .constant(0.4)).frame(width: 140)
                        ProgressView(value: 0.5).frame(width: 100)
                        ProgressView().controlSize(.small)
                        Image(systemName: "play.fill").font(.system(size: 17))
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 13))
                    }
                    HStack(spacing: 10) {
                        Button("B") {}.buttonStyle(.borderedProminent).controlSize(.small)
                        Button("B") {}.buttonStyle(.borderedProminent).controlSize(.regular)
                        Button("B") {}.buttonStyle(.borderedProminent).controlSize(.large)
                        Button("B") {}.buttonStyle(.borderedProminent).controlSize(.extraLarge)
                    }
                    Divider()
                    List {
                        ForEach(0..<4) { i in
                            HStack { Image(systemName: "music.note"); Text("Track \(i)"); Spacer(); Text("3:4\(i)").monospacedDigit() }
                        }
                    }
                    .frame(height: 130)
                }
                .padding(18)
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PopoverContent: View {
    @State private var progress: Double = 0.35
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.42, blue: 0.35), Color(red: 0.05, green: 0.12, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 14) {
                HStack {
                    Text("净听").font(.headline)
                    Spacer()
                    Image(systemName: "gearshape").font(.system(size: 13))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 240, height: 240)
                    .overlay(Image(systemName: "music.note").font(.system(size: 64)).foregroundStyle(.white.opacity(0.85)))

                VStack(spacing: 4) {
                    Text("夜曲").font(.title3.weight(.semibold))
                    Text("周杰伦 · 十一月的萧邦").font(.subheadline).foregroundStyle(.secondary)
                }
                ProgressView(value: progress).frame(width: 250)
                HStack {
                    Text("01:23").font(.caption2).monospacedDigit()
                    Spacer()
                    Text("03:45").font(.caption2).monospacedDigit()
                }.frame(width: 250).foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    Image(systemName: "backward.fill").font(.system(size: 17))
                    Image(systemName: "play.fill").font(.system(size: 26))
                    Image(systemName: "forward.fill").font(.system(size: 17))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 26)
                .glassEffect(.regular.interactive(), in: .capsule)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 360, height: 560)
    }
}

let delegate = Delegate()
app.delegate = delegate
app.run()
