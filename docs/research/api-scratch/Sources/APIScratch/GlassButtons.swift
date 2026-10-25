// GlassButtons.swift — §3: Liquid Glass button styles + sizing/control size.
//
// Ground truth (SDK MacOSX27.0.sdk, SwiftUI …swiftinterface):
//    1471/1480  @available(iOS 26.0, macOS 26.0, …) GlassButtonStyle
//    4457/4465  @available(iOS 26.0, macOS 26.0, …) GlassProminentButtonStyle
//    29510      @available(iOS 26.0, macOS 26.0, *) ToolbarSpacer
//    7286       @available(iOS 26.0, macOS 26.0, …) ButtonSizing
//    17082      @available(iOS 26.0, macOS 26.0, …) containerShape(_: some RoundedRectangularShape)
//    (`.controlSize(_ range:)` range form is macOS 26.0; single-value form macOS 10.15.)
//
// Buttons: `.buttonStyle(.glass)` is a PrimitiveButtonStyle; use it for
// secondary actions, `.glassProminent` for the one main action per surface.

import SwiftUI

// MARK: - 3.1 Glass button styles

struct GlassButtonStyleGallery: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("Glass") {}
                .buttonStyle(.glass)

            Button("Glass prominent") {}
                .buttonStyle(.glassProminent)

            Button {
                // primary playback action
            } label: {
                Label("播放", systemImage: "play.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)

            // Glass button inside a glass effect: enable interactive glass on
            // the *background*, not just the button.
            HStack(spacing: 10) {
                Button { } label: { Image(systemName: "backward.end.fill") }
                Button { } label: { Image(systemName: "play.fill") }
                Button { } label: { Image(systemName: "forward.end.fill") }
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Button("不会可用") {}
                .buttonStyle(.glass)
                .disabled(true)
        }
        .padding(20)
    }
}

// MARK: - 3.2 Button sizing (macOS 26) — flexible/fitted

struct ButtonSizingDemo: View {
    @Environment(\.buttonSizing) private var sizing

    var body: some View {
        VStack(spacing: 12) {
            Button("打开文件…") {}
                .buttonStyle(.glass)
                .buttonSizing(.flexible)

            Button("刷新") {}
                .buttonStyle(.glass)
                .buttonSizing(.fitted)

            // Custom style can read the environment (SDK doc example).
            Button("自定义") {}
                .buttonStyle(FullWidthGlassStyle())
        }
        .padding(20)
    }

    private struct FullWidthGlassStyle: ButtonStyle {
        @Environment(\.buttonSizing) private var buttonSizing

        private var maxWidth: CGFloat? {
            switch buttonSizing {
            case .flexible: .infinity
            default: nil
            }
        }

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .frame(maxWidth: maxWidth)
                .padding(.vertical, 8)
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: 12)
                )
                .opacity(configuration.isPressed ? 0.75 : 1)
        }
    }
}

// MARK: - 3.3 Control size (single value = macOS 10.15; range = macOS 26)

struct ControlSizeDemo: View {
    var body: some View {
        VStack(spacing: 12) {
            Button("mini") {}.buttonStyle(.glass).controlSize(.mini)
            Button("small") {}.buttonStyle(.glass).controlSize(.small)
            Button("regular") {}.buttonStyle(.glass).controlSize(.regular)
            Button("large") {}.buttonStyle(.glass).controlSize(.large)
            // Range form: lets AppKit/SwiftUI pick within the range.
            HStack {
                Button("范围 1") {}
                Button("范围 2") {}
            }
            .buttonStyle(.glass)
            .controlSize(.small ... .large)
        }
        .padding(20)
    }
}

// MARK: - 3.4 Toggle / Picker with glass-adjacent styles

struct GlassControlsDemo: View {
    @State private var enabled = true
    @State private var quality = 1

    var body: some View {
        VStack(spacing: 12) {
            Toggle("独占输出", isOn: $enabled)
                .toggleStyle(.switch)
                .controlSize(.small)

            Picker("质量", selection: $quality) {
                Text("无损").tag(0)
                Text("Hi-Res").tag(1)
                Text("空间音频").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(20)
    }
}
