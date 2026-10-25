import AppKit
import SwiftUI
setvbuf(stdout, nil, _IONBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

func measureHosting<V: View>(_ name: String, _ view: V) {
    let host = NSHostingView(rootView: view)
    host.layoutSubtreeIfNeeded()
    let f = host.fittingSize
    print(String(format: "%-46@ fittingSize = %.2f x %.2f", name as NSString, f.width, f.height))
}
measureHosting("Button(.glass) regular", Button("Play") {}.buttonStyle(.glass))
measureHosting("Button(.glass) small", Button("Play") {}.buttonStyle(.glass).controlSize(.small))
measureHosting("Button(.glassProminent)", Button("Play") {}.buttonStyle(.glassProminent))
measureHosting("Button(.glass) icon+label", Button { } label: { Label("Play", systemImage: "play.fill") }.buttonStyle(.glass))
measureHosting("Button(.glassProminent) icon only", Button { } label: { Image(systemName: "play.fill") }.buttonStyle(.glassProminent))
measureHosting("Menu(.menuStyle) button", Menu("Options") { Button("A"){}; Button("B"){} })
measureHosting("Toggle(.switch) large", Toggle("Switch", isOn: .constant(true)).toggleStyle(.switch).controlSize(.large))
measureHosting("Toggle(.switch) extraLarge", Toggle("Switch", isOn: .constant(true)).toggleStyle(.switch).controlSize(.extraLarge))
measureHosting("Slider regular", Slider(value: .constant(0.5)).frame(width: 200))
measureHosting("Slider small", Slider(value: .constant(0.5)).frame(width: 200).controlSize(.small))
measureHosting("TextField(.roundedBorder) large", TextField("x", text: .constant("")).textFieldStyle(.roundedBorder).controlSize(.large))
measureHosting("ProgressView linear large", ProgressView(value: 0.5).frame(width: 200).controlSize(.large))
measureHosting("Image(sf, 13pt)", Image(systemName: "play.fill").font(.system(size: 13)))
measureHosting("Image(sf, 17pt)", Image(systemName: "play.fill").font(.system(size: 17)))
measureHosting("Image(sf, 26pt)", Image(systemName: "play.fill").font(.system(size: 26)))
measureHosting("Label 13 w/ symbol", Label("Now Playing", systemImage: "music.note").font(.system(size: 13)))
measureHosting("Text title3 semibold", Text("夜曲").font(.title3.weight(.semibold)))
measureHosting("Text body 13", Text("Body").font(.body))
measureHosting("Text caption2", Text("01:23").font(.caption2).monospacedDigit())
measureHosting("HStack 3 icon buttons 28x28", HStack(spacing: 8) { ForEach(0..<3) { _ in Button{} label:{ Image(systemName:"play.fill").frame(width:28,height:28)}.buttonStyle(.plain) } })
// AppKit control intrinsic sizes
for cs in [NSControl.ControlSize.regular, .small, .large, .mini] {
    let b = NSButton(title: "Play", target: nil, action: nil)
    b.controlSize = cs
    b.bezelStyle = .rounded
    print("NSButton size=\(cs.rawValue) fitting=\(b.fittingSize)")
}
print("NSStatusItem square length:", NSStatusItem.squareLength, "variable:", NSStatusItem.variableLength)
print("NSToolbar heights? standard window chrome measured separately")
