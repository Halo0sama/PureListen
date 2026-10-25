import AppKit
import SwiftUI

setvbuf(stdout, nil, _IONBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

struct GlassSpecimen<V: View>: View {
    let name: String
    let size: CGSize
    let effect: V
    var body: some View {
        effect
            .frame(width: size.width, height: size.height)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                print("FRAME \(name) x=\(r.minX) y=\(r.minY) w=\(r.width) h=\(r.height)")
            }
    }
}

struct GlassContent: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    Color.white
                    Color.black
                }
                VStack(spacing: 0) {
                    row("regular", .regular, y: 0)
                    row("clear", .clear, y: 0)
                    row("tinted", .regular, y: 0, tint: true)
                    materialRow
                    Spacer()
                }
                .padding(.top, 20)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { s in print("CONTENT size w=\(s.width) h=\(s.height)") }
        }
    }

    func row(_ name: String, _ g: Glass, y: CGFloat, tint: Bool = false) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 500)
            Color.clear.frame(width: 500)
        }
        .overlay(
            HStack(spacing: 60) {
                chip("\(name)-white", g, tint: tint)
                chip("\(name)-black", g, tint: tint)
            }
        )
        .frame(height: 120)
    }

    func chip(_ name: String, _ g: Glass, tint: Bool) -> some View {
        let effect = Group {
            if tint { Color.clear.glassEffect(g.tint(.blue), in: .rect(cornerRadius: 20)) }
            else { Color.clear.glassEffect(g, in: .rect(cornerRadius: 20)) }
        }
        return effect
            .frame(width: 220, height: 96)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                print("FRAME \(name) x=\(r.minX) y=\(r.minY) w=\(r.width) h=\(r.height)")
            }
    }

    var materialRow: some View {
        HStack(spacing: 40) {
            mat("ultraThin", AnyShapeStyle(.ultraThinMaterial))
            mat("thin", AnyShapeStyle(.thinMaterial))
            mat("regularMat", AnyShapeStyle(.regularMaterial))
            mat("thick", AnyShapeStyle(.thickMaterial))
        }
        .frame(height: 120)
        .overlay(Text("materials").font(.caption).foregroundStyle(.secondary).offset(y: 50))
    }

    func mat(_ name: String, _ style: AnyShapeStyle) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(style)
            .frame(width: 180, height: 96)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                print("FRAME \(name) x=\(r.minX) y=\(r.minY) w=\(r.width) h=\(r.height)")
            }
    }
}

final class D: NSObject, NSApplicationDelegate {
    var win: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        let light = CommandLine.arguments.contains("light")
        win = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1000, height: 860),
                       styleMask: [.titled, .closable, .resizable],
                       backing: .buffered, defer: false)
        win.title = "Glass Specimen \(light ? "light" : "dark")"
        win.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        win.contentView = NSHostingView(rootView: GlassContent())
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            print("WINDOW frame=\(self.win.frame) contentLayout=\(self.win.contentLayoutRect)")
            let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
            if let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
                for w in infos where (w[kCGWindowOwnerName as String] as? String ?? "") == "glassprobe" {
                    print("WINDOW id=\(w[kCGWindowNumber as String] ?? -1) bounds=\(w[kCGWindowBounds as String] ?? [:])")
                }
            }
        }
    }
}
let d = D()
app.delegate = d
app.run()
