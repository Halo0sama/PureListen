# api-scratch — compile-verified macOS 27 design-API samples

Scratch package for **task-2** of the PureListen Golden-Gate redesign: every API
recommended in [`../sdk-api-cheatsheet.md`](../sdk-api-cheatsheet.md) is proven
to compile against the real SDK on *this* machine.

> **This package is research-only.** It is not part of the app target, has no
> dependency on app sources, and never runs audio code. Nothing here is
> imported by `Sources/` or by the app's `Package.swift`.

## Environment (measured 2026-10-26)

| Fact | Value |
|---|---|
| macOS | 27.0.1 (build 26A434) |
| Xcode | 27.1 (27A9275) |
| Swift | 6.4 (`swiftlang-6.4.0.34.1`), default target `arm64-apple-macosx27.0.0` |
| Xcode toolchain SDK dir | `…/SDKs/MacOSX27.0.sdk` (macosx27.0) |
| Default SDK for `swift build` | `MacOSX.sdk` → reports version **27.0** (`xcrun --show-sdk-version` = `27.0`) |
| Host arch | arm64 |
| App manifest at time of writing | `platforms: [.macOS("26.0")]` (a teammate raised it from `.v13`; uncommitted) |

## The three verification packages

| Directory | `platforms:` | What it proves |
|---|---|---|
| `.` (root) | `.macOS("27.0")` | Full recommended surface compiles with **zero `#available` guards**: SwiftUI glass, ConcentricRectangle, chrome effects, AppKit glass + macOS 27 view-corner API + status-item expanded interface. |
| `macos13-guards/` | `.macOS(.v13)` | Every guarded pattern needed **if the app stays at macOS 13**: exact `if #available(macOS 14/15/26/27)` ladders with fallbacks. |
| `macos26-surface/` | `.macOS("26.0")` | What compiles unguarded at **macOS 26.0** (the manifest's current value), and exactly which 26.1/27 APIs still need guards. |

Root package manifest is `// swift-tools-version:6.0` with the platform spelled
`.macOS("27.0")`: the `.macOS(.v27)` *symbol* requires tools-version 6.4, the
string form works with the app's 6.0 manifest (verified).

## Verify everything

```sh
cd docs/research/api-scratch
swift build                                  # macOS 27 surface (release-ready snippets)

cd macos13-guards
swift build                                  # macOS 13 + #available guards

cd ../macos26-surface
swift build                                  # macOS 26 guard-free surface
```

All three are expected to print `Build complete!` with **no errors and no
warnings** (verified).

### Negative tests (the "what breaks" proofs)

`negative-tests/` holds small files that must **fail** to compile; the captured
compiler output is stored next to each one as `*.expected-error.txt`.

```sh
SDK=$(xcrun --show-sdk-path)

xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-macosx13.0 \
  negative-tests/unguarded-glass-effect.swift
# error: 'glassEffect(_:in:)' is only available in macOS 26.0 or newer

xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-macosx13.0 \
  negative-tests/unguarded-concentric-rectangle.swift
# error: 'ConcentricRectangle' is only available in macOS 26.0 or newer

xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-macosx14.0 \
  negative-tests/unguarded-container-background-window.swift
# error: 'window' is only available in macOS 15.0 or newer

xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-macosx27.0 \
  negative-tests/container-background-navigation-macos.swift
# error: 'navigation' is unavailable in macOS

xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-macosx27.0 \
  negative-tests/nsview-corner-configuration-setter.swift
# error: cannot assign to property: 'cornerConfiguration' is a get-only property

xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-macosx13.0 \
  negative-tests/glass-effect-unguarded-13.swift
# error: 'NSGlassEffectView' is only available in macOS 26.0 or newer
```

## File map

| File | Cheat-sheet section | Contents |
|---|---|---|
| `Sources/APIScratch/GlassBasics.swift` | §2 | `.glassEffect(_:in:)`, four `Glass` variants, tint, interactive, shapes, bounds/anchor rules |
| `Sources/APIScratch/GlassMorphing.swift` | §3 | `GlassEffectContainer(spacing:)`, `glassEffectID`, `glassEffectUnion`, all three `GlassEffectTransition`s |
| `Sources/APIScratch/GlassButtons.swift` | §4 | `.buttonStyle(.glass/.glassProminent)`, `buttonSizing`, control-size range |
| `Sources/APIScratch/ConcentricRadii.swift` | §5 | `ConcentricRectangle`, `Edge.Corner.Style`, `containerShape`, `RoundedRectangularShapeCorners`, `RectangleCornerRadii` fallback, `containerCornerOffset`, `RectangleCornerInsets` |
| `Sources/APIScratch/ChromeEffects.swift` | §6 | `backgroundExtensionEffect`, `scrollEdgeEffectStyle/Hidden`, `toolbarBackgroundVisibility`, `containerBackground(for: .window)`, `safeAreaBar`, `ToolbarSpacer`, `sharedBackgroundVisibility`, `ToolbarItemVisibilityPriority` |
| `Sources/APIScratch/MaterialsColors.swift` | §7 | `Material` variants, `MaterialActiveAppearance`, semantic `NSColor`s, `Color.mix`, `Color.Resolved/HDR`, AppKit HDR colors |
| `Sources/APIScratch/SymbolsTypography.swift` | §8 | SF Symbols rendering/effects/variable value, macOS 26 symbol modes, font styles/sizes, `NSFont`/`NSImage.SymbolConfiguration` recipes |
| `Sources/APIScratch/AccessibilityAppearance.swift` | §9 | Reduce Transparency / Increase Contrast / Reduce Motion (SwiftUI env + `NSWorkspace` + notifications), `NSAppearance` high-contrast matching, fallback surfaces |
| `Sources/APIScratch/AppKitGlassViews.swift` | §10 | `NSGlassEffectView` (+27 `effectIsInteractive`), `NSGlassEffectContainerView`, `NSBackgroundExtensionView`, `NSVisualEffectView` materials, macOS 27 `NSViewCornerConfiguration` (override pattern) |
| `Sources/APIScratch/AppKitWindowChrome.swift` | §11 | menu-bar `NSWindow`/`NSPanel` chrome, `NSPopover` config, `NSHostingView/Controller`, SwiftUI `beginSheet/endSheet`, EDR queries, key-window behavior |
| `Sources/APIScratch/AppKitStatusItem.swift` | §12 | `NSStatusItem` setup + macOS 27 `expandedInterfaceDelegate`/session lifecycle, menu-based alternative |
| `Sources/APIScratch/GlassFallbacks.swift` | §13 | pre-26 material fallbacks, adaptive surfaces, availability helpers |
| `macos13-guards/` | §14 | guard ladders for every 14/15/26/27 API, verified at `platforms: [.macOS(.v13)]` |
| `macos26-surface/` | §15 | guard-free macOS 26 surface + guarded 26.1/27 bits, verified at `.macOS("26.0")` |
|  `negative-tests/` + captured `*.expected-error.txt` | §16 | deliberate compile failures that justify each gotcha |

## App-level checks performed (read-only, in `/tmp` copies)

* `swift build` on an untouched copy of the repo (manifest `.macOS(.v13)`) — **succeeds** with SDK 27.
* Copy with `platforms: [.macOS("26.0")]` — **succeeds**.
* Copy with `platforms: [.macOS("27.0")]` — **succeeds** (existing sources have no API that breaks when raising the deployment target).
* Built product's `LC_BUILD_VERSION` follows the manifest: `minos 26.0 / sdk 27.0` after the 26.0 build, `minos 27.0 / sdk 27.0` after the 27.0 build.
* `swift build --triple arm64-apple-macosx27.0` on the unmodified manifest — **succeeds**.
