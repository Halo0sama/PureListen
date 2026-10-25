// SymbolsTypography.swift — §7: SF Symbols (incl. SF Symbols 8-era additions)
// and typography.
//
// Ground truth (SDK MacOSX27.0.sdk):
//   SwiftUICore …:11239  Image.init(systemName:)                                  (macOS 11)
//   SwiftUICore …:11249  Image.init(systemName:variableValue:)                    (macOS 13)
//   SwiftUICore …:8635   EnvironmentValues.symbolRenderingMode / View.symbolRenderingMode (macOS 12)
//   SwiftUI …:16513      View.symbolEffect(_:options:isActive:)                   (macOS 14)
//   SwiftUI …:16518      View.symbolEffect(_:options:value:)                      (macOS 14)
//   SwiftUI …:16672      ContentTransition.symbolEffect(_:options:)               (macOS 14)
//   SwiftUICore …:8643   SymbolVariableValueMode { .color, .draw }                (macOS 26)
//   SwiftUICore …:8670   SymbolColorRenderingMode { .flat, .gradient }            (macOS 26)
//   SwiftUICore …:8655   Image.symbolVariableValueMode(_:) / symbolColorRenderingMode(_:)
//   AppKit/NSImage.h:619 NSImage.SymbolConfiguration(variableValueMode:)          (macOS 26)
//   AppKit/NSImage.h:624 NSImage.SymbolConfiguration(colorRenderingMode:)         (macOS 26)
//
// Typography ground truth:
//   Font.system(size:weight:design:)                     macOS 11
//   .fontDesign(_:)                                       macOS 13
//   .fontWidth(_:)                                        macOS 13
//   .monospacedDigit()                                    macOS 12
//   .tracking(_:)                                         macOS 13
//   .controlSize(_:) single value                         macOS 10.15
//   NSFont.systemFont(ofSize:weight:width:)               macOS 13
//   NSFont.monospacedDigitSystemFont(ofSize:weight:)      macOS 10.11
//   NSFont.preferredFont(forTextStyle:)                   macOS 11
//   NSFontDescriptor.withDesign(.rounded)                 macOS 10.15

import SwiftUI
import AppKit

// MARK: - 7.1 SF Symbols rendering modes + variants

struct SymbolRenderingGallery: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                symbol("hierarchical", .hierarchical)
                symbol("palette", .palette)
                symbol("multicolor", .multicolor)
                symbol("monochrome", .monochrome)
            }

            // Variable-value symbols (macOS 13): drives the symbol's variable
            // layers, e.g. speaker waves for volume 0…1.
            Image(systemName: "speaker.wave.3.fill", variableValue: 0.66)
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)

            // macOS 26: variable value can be drawn (length) or colored.
            Image(systemName: "speaker.wave.3.fill", variableValue: 0.66)
                .font(.system(size: 22))
                .symbolVariableValueMode(.draw)

            // macOS 26: flat vs gradient color layers.
            Image(systemName: "cloud.sun.rain.fill")
                .font(.system(size: 22))
                .symbolColorRenderingMode(.gradient)

            // Weights/scale are controlled by font + symbol rendering.
            Image(systemName: "play.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
        }
        .padding(20)
    }

    private func symbol(_ name: String, _ mode: SymbolRenderingMode) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "cloud.sun.rain.fill")
                .font(.system(size: 20))
                .symbolRenderingMode(mode)
            Text(name).font(.caption2)
        }
    }
}

// MARK: - 7.2 Symbol effects + content transitions (playback polish)

struct SymbolEffectsDemo: View {
    @State private var isPlaying = true
    @State private var trackIndex = 0
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 16) {
            // Discrete effect triggered by a value change:
            Image(systemName: "backward.end.fill")
                .symbolEffect(.bounce, value: trackIndex)

            // Indefinite effect (pulse) while playing:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)

            // Replace transition when the symbol name changes:
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .contentTransition(.symbolEffect(.replace))
                .onTapGesture { withAnimation(.snappy) { isPlaying.toggle() } }

            // Draw-on effect (SF Symbols 7+; macOS 26): animate the path.
            Image(systemName: "music.note")
                .symbolEffect(.drawOn, isActive: pulse)
                .onTapGesture { pulse.toggle() }

            Button("下一首") { trackIndex += 1 }
                .buttonStyle(.glass)
        }
        .padding(20)
    }
}

// MARK: - 7.3 Typography: system styles, sizes, rounded/mono designs

struct TypographyDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("largeTitle").font(.largeTitle)
            Text("title").font(.title)
            Text("title2").font(.title2)
            Text("title3").font(.title3)
            Text("headline").font(.headline)
            Text("body").font(.body)
            Text("callout").font(.callout)
            Text("subheadline").font(.subheadline)
            Text("footnote").font(.footnote)
            Text("caption").font(.caption)
            Text("caption2").font(.caption2)

            Divider()

            // Compact-popover custom sizes (13/11/10 pt are macOS-native-ish).
            Text("净听")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("24-bit / 96 kHz · 无损")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("时间码 03:24 / 05:11")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()

            // Design/width/weight/tracking combinations.
            Text("Rounded + condensed + tracked")
                .font(.system(size: 12, weight: .semibold))
                .fontDesign(.rounded)
                .fontWidth(.condensed)
                .tracking(0.4)

            Text("Mono numerals 0123456789")
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
        }
        .padding(20)
    }
}

// MARK: - 7.4 AppKit-side symbols and fonts (for NSView/NSStatusItem chrome)

@MainActor
enum AppKitSymbolFont {
    /// Menu-bar item icon: template image so the system tints it for the
    /// menu-bar appearance automatically (NSStatusBarButton.h doc).
    static func statusItemImage() -> NSImage? {
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "净听")
        image?.isTemplate = true
        return image
    }

    /// Configured symbol image (point size / weight / scale).
    static func configuredSymbol() -> NSImage? {
        NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
    }

    /// macOS 26 symbol configuration additions.
    @available(macOS 26.0, *)
    static func configuredSymbol26() -> NSImage? {
        let image = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil)
        let draw = NSImage.SymbolConfiguration(variableValueMode: .draw)
        let gradient = NSImage.SymbolConfiguration(colorRenderingMode: .gradient)
        return image?.withSymbolConfiguration(draw)?.withSymbolConfiguration(gradient)
    }

    static func fonts() -> [NSFont] {
        [
            NSFont.systemFont(ofSize: 13, weight: .semibold),
            NSFont.systemFont(ofSize: 13, weight: .medium, width: .condensed),
            NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            NSFont.preferredFont(forTextStyle: .body),
            NSFont(descriptor: NSFont.systemFont(ofSize: 13)
                .fontDescriptor
                .withDesign(.rounded) ?? NSFont.systemFont(ofSize: 13).fontDescriptor,
                   size: 13) ?? NSFont.systemFont(ofSize: 13)
        ]
    }
}

// MARK: - 7.5 Icon-only glass control row (compile-checked recipe)

struct PlaybackTransportRow: View {
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 18) {
            Button { } label: {
                Image(systemName: "shuffle").font(.system(size: 13, weight: .medium))
            }
            Button { } label: {
                Image(systemName: "backward.fill").font(.system(size: 15))
            }
            Button { isPlaying.toggle() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)

            Button { } label: {
                Image(systemName: "forward.fill").font(.system(size: 15))
            }
            Button { } label: {
                Image(systemName: "repeat").font(.system(size: 13, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .padding(20)
    }
}
