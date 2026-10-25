# PureListen × macOS 27 "Golden Gate" — SDK / API Cheat Sheet

**Scope:** the ≈50 SDK APIs we actually need to rebuild the PureListen UI as a
Liquid-Glass-native macOS 27 app (360×560 menu-bar popover + separate now-playing
window), with exact availability, compile-verified snippets, deployment-target
advice, and gotchas found while building against the real SDK.

**Ground truth:** everything below was read out of / compiled against the SDK
installed on this machine — **not** recalled from memory.

```
$SDK = /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk
```

| Fact | Measured value |
|---|---|
| macOS | **27.0.1** (build 26A434) |
| Xcode | **27.1** (build 27A9275) |
| Swift | **6.4** (`swiftlang-6.4.0.34.1`), default target `arm64-apple-macosx27.0.0` |
| SDK | `macosx27.0` = `MacOSX27.0.sdk`; default `MacOSX.sdk` also reports 27.0 |
| App manifest observed | `platforms: [.macOS("26.0")]` — a teammate already raised it from `.v13` (uncommitted on 2026-10-26 02:00). `build.sh` still writes `LSMinimumSystemVersion 13.0` (**inconsistent — see §15, gotcha 23**). |

**Companion package (all snippets compile-verified):**
[`docs/research/api-scratch/`](./api-scratch/) — three buildable packages:
`.macOS("27.0")` full surface, `.macOS(.v13)` guarded ladder, `.macOS("26.0")`
guard-free surface, plus `negative-tests/` with captured compiler errors.
Run `swift build` in each (see §16).

Evidence tags used below:
* **[SDK]** = declaration + `@available` read directly from the SDK
  (`swiftinterface` / AppKit header, with `file:line`).
* **[DOC]** = doc comment extracted from the SDK symbol graph
  (`swift-symbolgraph-extract`), i.e. Apple's own wording shipped in the SDK.
* **[COMPILED]** = snippet built by `swift build` in api-scratch.
* **[INFERRED]** = design/behaviour judgement, not directly provable from the SDK.

---

## 0. TL;DR — top recommended choices

**SwiftUI surface (popover + now-playing window)**

| # | API | One-line usage | Min macOS |
|---|---|---|---|
| 1 | `.glassEffect(_:in:)` | `.padding().glassEffect(.regular, in: .rect(cornerRadius: 14))` | 26.0 |
| 2 | `Glass.regular` | default; auto-adjusts content legibility over backdrop | 26.0 |
| 3 | `Glass.clear` | only over a deliberately dimmed backdrop (SDK says add dimming layer) | 26.0 |
| 4 | `Glass.tint(_:)` | `.glassEffect(.regular.tint(.accentColor.opacity(0.35)))` | 26.0 |
| 5 | `Glass.interactive()` | `.glassEffect(.regular.interactive())` on tappable glass | 26.0 |
| 6 | `GlassEffectContainer(spacing:)` | wrap one *cluster* of glass: `GlassEffectContainer(spacing: 10) { … }` | 26.0 |
| 7 | `.glassEffectID(_:in:)` | identity for morph animations (`@Namespace`) | 26.0 |
| 8 | `.glassEffectUnion(id:namespace:)` | merge several views into one glass shape (segmented pill) | 26.0 |
| 9 | `.glassEffectTransition(_:)` | `.matchedGeometry` / `.materialize` / `.identity` | 26.0 |
| 10 | `.buttonStyle(.glass)` / `.glassProminent` | secondary vs. primary action buttons | 26.0 |
| 11 | `ConcentricRectangle` | nested cards auto-match container corners | 26.0 |
| 12 | `Edge.Corner.Style` `.fixed/.concentric` | per-corner style; `.concentric(minimum:)` to clamp | 26.0 |
| 13 | `.containerShape(_: some RoundedRectangularShape)` | declare the container radius once; `ConcentricRectangle` children inherit it | 26.0 |
| 14 | `RoundedRectangularShapeCorners` | resolve actual corner radii via `shape.corners(in:)` | 26.0 |
| 15 | `containerCornerOffset(_:sizeToFit:)` | keep controls out of window/presentation corner insets | 26.0 |
| 16 | `backgroundExtensionEffect()` | extend artwork/gradient under titlebar/sidebar edges | 26.0 |
| 17 | `.scrollEdgeEffectStyle(.soft/.hard, for:)` | control the scroll-edge blur look | 26.0 |
| 18 | `.scrollEdgeEffectHidden(_:for:)` | hide edge effect when drawing your own fade | 26.0 |
| 19 | `.safeAreaBar(edge:)` | now-playing transport bar that also extends scroll edge effect | 26.0 |
| 20 | `.toolbarBackgroundVisibility(_, for: .windowToolbar)` | hide/show window toolbar background | 15.0 |
| 21 | `.containerBackground(_, for: .window)` | window-level background (only macOS placement) | 15.0 |
| 22 | `ToolbarSpacer(.fixed/.flexible)` | toolbar grouping/spacing | 26.0 |
| 23 | `.sharedBackgroundVisibility(.hidden)` (on ToolbarContent) | individual toolbar items without shared capsule | 26.0 |
| 24 | `.buttonSizing(.flexible/.fitted)` | full-width vs. fitted buttons | 26.0 |
| 25 | `.controlSize(.mini/.small/… )` + range form | compact popover controls; range = adaptive | 10.15 / 26.0 |
| 26 | `Material` variants + `.bar` | fallback/background translucency; `.bar` = bar material | 12.0 |
| 27 | `MaterialActiveAppearance` | `.materialActiveAppearance(.matchWindow)` so chrome dims with window | 15.0 |
| 28 | `Color.Resolved` | pre-resolved cheap color for album-art tint math | 14.0 |
| 29 | `Color.ResolvedHDR` | HDR highlight glow with `headroom` | 26.0 |
| 30 | `Color.mix(with:by:in:)` | generate tint variants from artwork color | 15.0 |
| 31 | `.symbolRenderingMode(.hierarchical/.palette/.multicolor)` | SF Symbols depth/colors | 12.0 |
| 32 | `.symbolEffect(_:options:isActive:/value:)` | pulse while playing, bounce on track change | 14.0 |
| 33 | `.contentTransition(.symbolEffect(.replace))` | animated play⇄pause icon swap | 14.0 |
| 34 | `Image(systemName:variableValue:)` | volume/battery-style variable symbols | 13.0 |
| 35 | `.symbolVariableValueMode(.draw/.color)` / `.symbolColorRenderingMode(.flat/.gradient)` | SF Symbols 8-style variable drawing & gradient layers | 26.0 |
| 36 | `Font.system(size:weight:design:)` + `.fontWidth/.fontDesign/.tracking/.monospacedDigit()` | native type in the popover | 11.0/13.0/12.0 |
| 37 | `@Environment(\.accessibilityReduceTransparency)` | disable decorative glass | 10.15 |
| 38 | `@Environment(\.colorSchemeContrast)` | Increase Contrast borders | 10.15 |

**AppKit side (menu bar / window / custom NSView chrome)**

| # | API | One-line usage | Min macOS |
|---|---|---|---|
| 39 | `NSGlassEffectView` | AppKit glass background (`contentView`, `cornerRadius`, `tintColor`, `style`) | 26.0 |
| 40 | `NSGlassEffectView.effectIsInteractive` | pointer/press response for AppKit glass | **27.0** |
| 41 | `NSGlassEffectContainerView` | merge descendant AppKit glass (`spacing`) | 26.0 |
| 42 | `NSBackgroundExtensionView` | AppKit version of background extension | 26.0 |
| 43 | `NSViewCornerRadius/.containerConcentric` + `NSViewCornerConfiguration` + `NSView.cornerConfiguration` override | custom NSView chrome that follows the *system* window radius | **27.0** |
| 44 | `NSStatusItem.expandedInterfaceDelegate` + `NSStatusItemExpandedInterfaceSession.cancel()` | correct menu-bar "expanded interface" (keyboard nav/menu tracking) | **27.0** |
| 45 | `NSVisualEffectView` materials | pre-26 / Reduce-Transparency fallback (`popover`, `menu`, `sidebar`, `hudWindow`, …) | 10.10 |
| 46 | `NSToolbarItem.Style` (.plain/.prominent), `backgroundTintColor`, `badge`/`NSItemBadge` | native toolbar item prominence + badges | 26.0 |
| 47 | `NSControl.BorderShape`, `NSTintProminence` | capsule/circle/rounded control shapes + tint hierarchy | 26.0 |
| 48 | `NSColor(…, exposure:)` / `linearExposure` / `standardDynamicRange` | AppKit HDR colors + SDR fallback | 26.0 |
| 49 | `NSImage.SymbolConfiguration(variableValueMode:/colorRenderingMode:)` | AppKit equivalents of #35 | 26.0 |
| 50 | `NSWorkspace.accessibilityDisplayShouldReduceTransparency/…IncreaseContrast/…ReduceMotion` | AppKit appearance detection | 10.10–10.12 |
| 51 | `NSPopover.hasFullSizeContent` | edge-to-edge popover content | 14.0 |
| 52 | `NSHostingView.sizingOptions/.safeAreaRegions`, `NSHostingController` | host SwiftUI in AppKit chrome | 13.0 |
| 53 | `NSWindow.beginSheet(content:)` / `endSheet(_:)` | SwiftUI content sheets without NSViewController boilerplate | 26.0 |

The full availability matrix with SDK line references is in **§13**.

---

## 1. Deployment-target decision (read this first)

### 1.1 What the SDK actually says

* **All SwiftUI Liquid Glass is macOS 26.0** — `.glassEffect`, `Glass`,
  `GlassEffectContainer`, `glassEffectID/Union/Transition`,
  `GlassButtonStyle`, `ConcentricRectangle`, `backgroundExtensionEffect`,
  `scrollEdgeEffect*`, `safeAreaBar`, `ToolbarSpacer`,
  `sharedBackgroundVisibility`, `buttonSizing`, symbol variable/color modes,
  `Color.ResolvedHDR`. **[SDK]** (e.g. `SwiftUICore…swiftinterface:3064`,
  `:16935`, `SwiftUI…swiftinterface:15832`, `:22856`)
* **macOS 27 adds almost nothing to SwiftUI glass.** Grep of the whole
  macOS-27 availability set in SwiftUI/SwiftUICore yields document APIs,
  `TabsPickerStyle`, list reordering, `swipeActions(onPresentationChanged:)`,
  `AnyNavigationTransition`, `Preview(arguments:)`, toolbar content tuple
  conformances, and `ToolbarItemVisibilityPriority.init(lowerThan:/higherThan:)`.
  The only *design* macOS-27 SwiftUI additions worth using are:
  * conditional toolbar content: `EmptyView`/`TupleContent` now conform to
    `ToolbarContent` on 27.0 (`SwiftUI…swiftinterface:22171`, `:22178`) →
    `if`/`switch` inside `.toolbar {}` becomes legal;
  * `ToolbarItemVisibilityPriority` init forms (27.0);
  * `TabsPickerStyle` (`.tabs`, 27.0) if we ever want tab-strip pickers.
* **macOS 27's real Golden-Gate API delta is AppKit:** `effectIsInteractive`
  on `NSGlassEffectView`, the `NSViewCornerRadius`/`NSViewCornerConfiguration`/
  `NSViewCornerRadii` system, and `NSStatusItem` expanded-interface sessions.

### 1.2 Options

| Option | Guarantees | Guard clutter | Cost |
|---|---|---|---|
| **A. `platforms: [.macOS("27.0")]`** | full recommended surface incl. effectIsInteractive, view-corner config, expanded-interface session, toolbar priority init | **zero** | app only runs on macOS 27+ |
| **B. `platforms: [.macOS("26.0")]`** ← app's current value | glass core, ConcentricRectangle, chrome effects, AppKit glass/controls/symbols — all guard-free | only the ~6 macOS-27 extras need `if #available(macOS 27.0, *)`; `ToolbarItemVisibilityPriority` needs `26.1` guard | app runs on 26+ |
| **C. keep `platforms: [.macOS(.v13)]`** | nothing new guard-free | **huge** ladder: 14 (containerBackground, symbolEffect, hasFullSizeContent), 15 (Color.mix, materialActiveAppearance, toolbarBackgroundVisibility, `.window` placement), 26 (all glass/shape/chrome/AppKit glass), 27 (corner config, status session, interactivity) | supports 13+ but every glass surface needs a fallback |

**Recommendation [INFERRED, but grounded in the compile matrix]:**
keep the app at **`platforms: [.macOS("26.0")]`** (option B). It makes the whole
Liquid-Glass visual core guard-free and only isolates the macOS-27 extras; if a
27-only nicety isn't essential, skip it rather than raising the floor.
Raise to `.macOS("27.0")` only if the product decision is "Golden Gate-only".

**Manifest syntax gotcha [COMPILED]:** with `// swift-tools-version:6.0` (the
app's current tools version) the symbol `.macOS(.v27)` is **unavailable**
(`PackageDescription 6.4`), so use the string form:

```swift
// swift-tools-version:6.0
let package = Package(
    name: "PureListen",
    platforms: [.macOS("26.0")],   // or "27.0" — verified to build with tools 6.0
    …
)
```
`.macOS(.v27)` only works after bumping to `// swift-tools-version:6.4`.

### 1.3 If we were to keep macOS 13 — exactly what needs guarding

Reference implementation: `api-scratch/macos13-guards/` (builds at
`platforms: [.macOS(.v13)]`):

```swift
// The copy-paste shape for every glass surface:
struct AdaptiveGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: ConcentricRectangle(corners: .concentric))
                .containerShape(.rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}
```

When keeping macOS 13, these all need guards **in this order** (guard the
highest requirement that a single call site needs):

| Min macOS | APIs used by our redesign |
|---|---|
| 14.0 | `.containerBackground`, `.symbolEffect`, `contentTransition(.symbolEffect)`, `NSPopover.hasFullSizeContent`, `Color.Resolved` |
| 15.0 | `Color.mix`, `.materialActiveAppearance`, `.toolbarBackgroundVisibility`, **`ContainerBackgroundPlacement.window` (the placement, not the modifier, is 15.0)** |
| 26.0 | glass APIs (#1–#10), `ConcentricRectangle`/`Edge.Corner.Style`/`containerShape(RoundedRectangularShape)`/`RoundedRectangularShapeCorners`/`containerCornerOffset`, `backgroundExtensionEffect`, `scrollEdgeEffect*`, `safeAreaBar`, `ToolbarSpacer`, `sharedBackgroundVisibility`, `buttonSizing`, `controlSize(range)`, `SymbolVariableValueMode`/`SymbolColorRenderingMode`, `Color.ResolvedHDR`, `NSGlassEffectView`/`NSGlassEffectContainerView`/`NSBackgroundExtensionView`, `NSControl.BorderShape`, `NSTintProminence`, `NSImage` symbol modes, `NSColor` exposure, `NSWindow.beginSheet(content:)` |
| 26.1 | `ToolbarItemVisibilityPriority` (the *type* itself) |
| 27.0 | `NSGlassEffectView.effectIsInteractive`, `NSViewCornerConfiguration`/`Radius`/`Radii` + `NSView` override hooks, `NSStatusItem.expandedInterfaceDelegate`/session, `NSMenuItem.preferredImageVisibility`, new `NSControl.Events`, `TabsPickerStyle`, list reordering |

Our macOS-13 reference package needed ~10 wrapper types + guarded call sites
just for the visual core; that is the clutter we avoid by targeting 26+.

**Build facts verified:** an untouched copy of the repo builds with SDK 27 at
`.v13`; the same copy builds at `.macOS("26.0")` and at `.macOS("27.0")` without
source changes; `swift build --triple arm64-apple-macosx27.0` also succeeds. The
built binary's `LC_BUILD_VERSION` follows the manifest (`minos 26.0` / `sdk 27.0`
after the 26.0 build). See §16.

---

## 2. SwiftUI Liquid Glass — the core

### 2.1 The modifier

```swift
// [SDK] SwiftUICore…swiftinterface:3064, macOS 26.0, visionOS unavailable
nonisolated public func glassEffect(
    _ glass: Glass = .regular,
    in shape: some Shape = DefaultGlassEffectShape()
) -> some View
```

```swift
// [COMPILED] api-scratch/Sources/APIScratch/GlassBasics.swift
Label("24-bit / 96 kHz", systemImage: "waveform")
    .padding(.horizontal, 10).padding(.vertical, 5)
    .glassEffect(.regular.tint(.accentColor.opacity(0.35)), in: Capsule())
```

Three rules from Apple's own doc comments **[DOC]**:
1. **The default shape is a capsule**, not a rounded rectangle:
   `DefaultGlassEffectShape` doc = *"The default shape applied by glass effects,
   a capsule."* (`SwiftUICore…:3069`). Pass an explicit shape for cards.
2. **Glass anchors to the view's bounds, including padding.** Doc: *"the
   physical glass material fills the entirety of the label's frame, which
   includes the padding."* So `.padding().glassEffect()` grows the glass, while
   `.glassEffect().padding()` keeps padding outside the glass.
3. **`Glass.regular` self-corrects legibility** (*"automatically maintains
   legibility of content by adjusting its content based on the luminosity of the
   content beneath the glass"*); `Glass.clear` does not: *"ensure content remains
   legible by adding a dimming layer or other treatment beneath the glass."*

### 2.2 `Glass` configuration

```swift
// [SDK] SwiftUICore…swiftinterface:7245, macOS 26.0
public struct Glass: Equatable, Sendable {
    public static var regular: Glass
    public static var clear: Glass
    public static var identity: Glass          // renders as if no glass
    public func tint(_ color: Color?) -> Glass
    public func interactive(_ isEnabled: Bool = true) -> Glass
}
```

Usage map for PureListen **[INFERRED design guidance]**:

| Where | Glass config |
|---|---|
| transport bar / floating playback controls over artwork | `.regular` (legibility first) or `.regular.tint(albumTint.opacity(0.3))` |
| tappable chips / icon buttons | `.regular.interactive()` (glass reacts to pointer/press) |
| segmented pill (playing/queue switch) | `.regular.tint(.accentColor)` + `.glassEffectUnion` |
| over bright album art where a glass chip looks milky | either put a `.black.opacity(0.2…0.35)` layer under it + `.clear`, or keep `.regular` |
| temporarily disable glass for snapshot/preview/reduce transparency | `.identity` |
| cards/bottom bars at the edges of a window | glass + `ConcentricRectangle` (see §5) |

### 2.3 What interaction does **not** do

`.interactive()` is a *Glass configuration*, not a button style: it adds the
press/pointer response to the material but does not make non-buttons tappable.
Use `.contentShape(...)` + `onTapGesture` or put a `Button` with
`.buttonStyle(.plain)` on top.

### 2.4 iOS/visionOS availability

`.glassEffect`, `GlassEffectContainer`, `glassEffectID/Union/Transition` and
`Glass` are marked **`@available(visionOS, unavailable)`** **[SDK]** — irrelevant
today, but do not put these in shared cross-platform code.

---

## 3. `GlassEffectContainer` — merging and morphing

```swift
// [SDK] SwiftUICore…swiftinterface:11523, macOS 26.0, visionOS unavailable
@MainActor public struct GlassEffectContainer<Content: View>: View {
    public init(spacing: CGFloat? = nil, @ContentBuilder content: () -> Content)
}
```

**[DOC]** *"combines multiple glass shapes into a single shape that can morph
individual shapes into one another … As shapes near one another, their paths
start to blend into one another. The higher the spacing, the sooner blending
begins as glass approaches each other."*

```swift
// [COMPILED] api-scratch/Sources/APIScratch/GlassMorphing.swift
GlassEffectContainer(spacing: 10) {
    HStack(spacing: 10) {
        Image(systemName: "speaker.wave.2.fill")
            .frame(width: 36, height: 36)
            .glassEffect()
            .glassEffectID("volume", in: namespace)

        if isExpanded {
            Image(systemName: "list.bullet")
                .frame(width: 36, height: 36)
                .glassEffect()
                .glassEffectID("queue", in: namespace)
                .glassEffectTransition(.matchedGeometry)   // morph on insert/remove
        }
    }
}
```

Companion modifiers **[SDK]**:

| API | Availability | Meaning |
|---|---|---|
| `.glassEffectID(_ id: (some Hashable & Sendable)?, in: Namespace.ID)` | 26.0 | identity used for morphing (`SwiftUICore…:22411`) |
| `.glassEffectUnion(id:namespace:)` | 26.0 | several views → one glass shape, same id/shape/glass (`:12644`) |
| `.glassEffectTransition(_:)` | 26.0 | `.matchedGeometry`, `.materialize`, `.identity` (`:3512`, `:3498`) |

`GlassEffectTransition` docs **[DOC]**:
* `.matchedGeometry` — derives geometry from a nearby shape in the container;
  when using `Animation.default` it also applies extra scale/offset, so provide
  an explicit animation (e.g. `.spring`) to opt out.
* `.materialize` — fade content + animate material in/out, no geometry matching.
* `.identity` — no transition.

Rules for our UI **[INFERRED]**:
* one `GlassEffectContainer` per **cluster** (transport row, chip row, segmented
  pill); do **not** wrap the whole popover in one container — everything inside
  would merge.
* `spacing: 0` still batches rendering (performance) without merging;
  `spacing: 4…12` is where morphing starts for our control sizes.
* Only views that live inside the container can morph between each other; the
  `Namespace` must be the same `@Namespace` property.

---

## 4. Buttons & control sizing

```swift
// [COMPILED] api-scratch/Sources/APIScratch/GlassButtons.swift
Button("Glass") {}.buttonStyle(.glass)                  // secondary
Button("Play")  {}.buttonStyle(.glassProminent)         // primary
Button { } label: { Image(systemName: "play.fill") }
    .buttonStyle(.glass)
    .controlSize(.large)
```

| API | Availability |
|---|---|
| `.buttonStyle(.glass)` → `GlassButtonStyle` | 26.0 (`SwiftUI…swiftinterface:1480`) |
| `.buttonStyle(.glassProminent)` → `GlassProminentButtonStyle` | 26.0 (`:4465`) |
| `.buttonSizing(.automatic/.flexible/.fitted)` | 26.0 (`ButtonSizing` `SwiftUICore…:4316`) |
| `.controlSize(_:)` single value | 10.15 |
| `.controlSize(_ range:)` | 26.0 (`SwiftUICore…:7816`) |
| `ToolbarSpacer(.fixed/.flexible, placement:)` | 26.0, macOS-only (`SwiftUI…:29510`) |

`ButtonSizing` doc **[DOC]**: *"Many built-in controls that display as a button
adapt … you can make certain styles of Button, Picker, ControlGroup, and Toggle
flexible by applying this modifier"* — use `.buttonSizing(.flexible)` for the
big "播放全部" style action and keep `.fitted` for transport icons.

**Popover rule [INFERRED]:** `.controlSize(.small/.mini)` for chips and toolbar
icons, `.regular` for the main transport controls; glass buttons rendered at
`.small` match the density of the 360×560 surface.

---

## 5. Concentric radii — `ConcentricRectangle` & friends

### 5.1 What it is

```swift
// [SDK] SwiftUICore…swiftinterface:16935, macOS 26.0
public struct ConcentricRectangle: Shape, Animatable {
    public init()
    public init(corners: Edge.Corner.Style, isUniform: Bool = false)
    public init(topLeadingCorner:…, topTrailingCorner:…,
                bottomLeadingCorner:…, bottomTrailingCorner:…)
    public init(uniformTopCorners:…, uniformBottomCorners:…)
    // + 4 more uniform* combinations
}
```

**[DOC]** *"A shape whose corners you configure, individually or uniformly, to be
squared, rounded, or concentric relative to a container shape's corners. … System
-provided elements like sheets and popovers do this automatically."*

### 5.2 The radius math (SDK definition)

`Edge.Corner.Style.concentric` doc **[DOC]**:

> *"the system calculates the corner radius to equal the container shape's corner
> radius minus the distance between corners. When the system calculates a zero
> radius, the corner is square."*

So for a child inset by **d** from a container of radius **R**:

```
r_child = max(0, R − d)                       // per corner, per edge distance
```

* If `d ≥ R` → square corner.
* `.concentric(minimum: .fixed(x))` clamps to at least `x` **[DOC]**
  (`Edge.Corner.Style.concentric(minimum:)`, `SwiftUICore…:24792`).
* `ConcentricRectangle(corners: .concentric, isUniform: true)` computes the
  radius per corner then applies the **largest** to all four to keep symmetry
  **[DOC]** (`rect(corners:isUniform:)`).
* `RoundedRectangularShapeCorners` (`SwiftUICore…:17043`) exposes
  `.fixed(_:)`, `.concentric`, `.concentric(minimum:)` and can be read back via
  `shape.corners(in: CGSize) -> RoundedRectangularShapeCorners?`
  (`RoundedRectangularShape` protocol, `SwiftUICore…:17037`).

### 5.3 Declaring the container: `.containerShape(_: some RoundedRectangularShape)`

```swift
// [SDK] SwiftUICore…swiftinterface:17082 (macOS 26.0) — NEW overload
nonisolated public func containerShape(_ shape: some RoundedRectangularShape) -> some View
// old overload: containerShape<T: InsettableShape>(_:) — macOS 12.0
```
**[DOC]** *"Any ConcentricRectangle within the content will match the corners to
be concentric to the container corners."*

```swift
// [COMPILED] api-scratch/Sources/APIScratch/ConcentricRadii.swift
VStack(spacing: 10) {
    header
    playlistCard
}
.padding(12)
.containerShape(.rect(cornerRadius: 14))       // declare container radius ONCE
.background(.ultraThinMaterial,
            in: ConcentricRectangle(corners: .concentric))
```

**Verified compile error [COMPILED]:** `ConcentricRectangle` does **not** conform
to `RoundedRectangularShape`, so you cannot pass it to `.containerShape(...)`:

```
error: instance method 'containerShape' requires that 'ConcentricRectangle'
conform to 'RoundedRectangularShape'
```
Pass `RoundedRectangle`/`Capsule`/`Circle`/`UnevenRoundedRectangle` to
`containerShape`; use `ConcentricRectangle` *inside*.

### 5.4 Per-corner and mixed styles

```swift
// [COMPILED] api-scratch/Sources/APIScratch/ConcentricRadii.swift
ConcentricRectangle(corners: .fixed(12))
ConcentricRectangle(corners: .concentric, isUniform: true)
ConcentricRectangle(topLeadingCorner: .fixed(8), topTrailingCorner: .fixed(8),
                    bottomLeadingCorner: .concentric,
                    bottomTrailingCorner: .concentric)
ConcentricRectangle(uniformTopCorners: .fixed(10),
                    uniformBottomCorners: .concentric(minimum: .fixed(4)))
.clipShape(.rect(corners: .fixed(16)))          // static factory form
```

### 5.5 Recommended radius system for PureListen **[INFERRED]**

No numeric radius guidance ships in the SDK; the API is the guidance ("system
radius minus inset"). Use one 4-pt-grid scale and derive with `containerShape`:

| Surface | Radius | How |
|---|---|---|
| popover / borderless window content root | 14–16 | `.containerShape(.rect(cornerRadius: 15))` (NSPopover's own radius is OS-drawn; this value only drives internal concentric math) |
| first-level card flush-ish inside root (8 pt inset) | `.concentric(minimum: .fixed(8))` | resolves ≈ root − 8 |
| interior cards (12–16 pt inset) | `.fixed(10…12)` or `.concentric(minimum: .fixed(10))` | beyond one inset level, concentric hits 0–4 pt and looks wrong — use the minimum |
| artwork tile in now-playing window (240×240) | 16 fixed | `.rect(cornerRadius: 16)` |
| mini artwork in popover (44×44) | 10 fixed | continuous style |
| chips / pills | `Capsule()` | |
| icon-only transport buttons | `.circle` | 36–44 pt |
| toolbar / bottom bar | 0 (edge-to-edge) or concentric with window | `ConcentricRectangle(uniformTopCorners: .concentric, uniformBottomCorners: .fixed(0))` if flush to the bottom edge |

For a **custom AppKit** view that must follow the system's macOS-27 window
radius, don't hard-code: use `NSViewCornerRadius.containerConcentric`
(§10.3).

### 5.6 Corner insets / safe-area-like offsets

```swift
// [SDK] macOS 26.0: SwiftUICore…:22153, :3087, :3102
func containerCornerOffset(_ edges: Edge.Set, sizeToFit: Bool = false) -> some View
struct RectangleCornerInsets { topLeading/topTrailing/bottomLeading/bottomTrailing: CGSize }
extension EdgeInsets { func inset(by corners: RectangleCornerInsets,
                                  edges: Edge.Set = .all) -> EdgeInsets }
```
**[DOC]** `containerCornerOffset`: *"Corner insets may include pieces of system UI
as well as the corner radii for windows and presentations."* Use it for any
control pinned to a window corner (e.g. close/overflow button in the now-playing
window) instead of guessing the window radius. `sizeToFit: true` shrinks the
view into the remaining space instead of only moving it.

### 5.7 Pre-26 fallback for per-corner radii

`RectangleCornerRadii` (macOS 10.15) + `UnevenRoundedRectangle` (macOS 13) ——
still the right tool when targeting < 26:

```swift
// [COMPILED] api-scratch/Sources/APIScratch/ConcentricRadii.swift
UnevenRoundedRectangle(
    cornerRadii: RectangleCornerRadii(
        topLeading: 12, bottomLeading: 12,
        bottomTrailing: 4, topTrailing: 4
    ),
    style: .continuous
)
```

---

## 6. Window / popover chrome effects

### 6.1 `backgroundExtensionEffect` — extend artwork under chrome

```swift
// [SDK] SwiftUI…swiftinterface:15832/15835, macOS 26.0
func backgroundExtensionEffect() -> some View
func backgroundExtensionEffect(isEnabled: Bool) -> some View
```
**[DOC]** *"The view will be duplicated into mirrored copies which will be placed
around the view on any edge with available safe area. Additionally, a blur
effect will be applied on top to blur out the copies. … This modifier will clip
the view to prevent copies from overlapping. … Apply this modifier with
discretion. This should often be used with only a single instance of background
content."*

```swift
// [COMPILED] api-scratch/Sources/APIScratch/ChromeEffects.swift
LinearGradient(colors: [.indigo.opacity(0.75), .blue.opacity(0.35), .clear],
               startPoint: .top, endPoint: .bottom)
    .backgroundExtensionEffect()
    .frame(minWidth: 320, minHeight: 400)
```

Use exactly once per surface (now-playing window backdrop, popover artwork/header).
Needs available safe area to extend into; if the view already fills its
container edge-to-edge the effect has nothing to do **[DOC + INFERRED]**.
Disable it when Reduce Transparency is on (`isEnabled:` form).

### 6.2 Scroll edge effects (macOS 26)

```swift
// [SDK] SwiftUI…swiftinterface:15907/15926/15930, macOS 26.0
struct ScrollEdgeEffectStyle { static var automatic/hard/soft }
func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View
func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> some View
```
**[DOC]** *"By default, a scroll view renders an automatic edge effect."*
`.hard`/`.soft` change the look; hide it when you draw your own gradient mask.
Use `.soft` for the playlist scroll under the popover header; `.hard` for a
now-playing window with a full-bleed backdrop.

### 6.3 `safeAreaBar` — the new now-playing bar (macOS 26)

```swift
// [SDK] SwiftUI…swiftinterface:22856/22859, macOS 26.0
func safeAreaBar(edge: VerticalEdge, alignment: HorizontalAlignment = .center,
                 spacing: CGFloat? = nil, @ContentBuilder content: () -> some View) -> some View
func safeAreaBar(edge: HorizontalEdge, …) -> some View
```
**[DOC]** *"Similar to safeAreaInset … Additionally, it extends the edge effect of
any scroll views affected by the inset safe area."*

```swift
// [COMPILED] api-scratch/Sources/APIScratch/ChromeEffects.swift
ScrollView { … }
    .safeAreaBar(edge: .bottom, spacing: 0) {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("夜航").font(.system(size: 12, weight: .semibold))
                Text("净听 · 24bit/96kHz")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { } label: { Image(systemName: "play.fill") }
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
```
Prefer this over `safeAreaInset` for the persistent transport bar — it keeps the
scroll-edge effect coherent. (At < 26, `safeAreaInset` + `.background(.bar)` is
the fallback.)

### 6.4 Toolbar / window background visibility

```swift
// [SDK] toolbarBackgroundVisibility: SwiftUI…:12820, macOS 15.0
.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
// [SDK] containerBackground: SwiftUI…:16336, macOS 14.0; .window placement macOS 15.0
.containerBackground(.thickMaterial, for: .window)
.containerBackground(for: .window) { MyGradientView() }
```

**Verified platform limit [COMPILED]:** on macOS the **only**
`ContainerBackgroundPlacement` is `.window`. `.navigation`,
`.navigationSplitView`, `.tabView` are explicitly `@available(macOS, unavailable)`
→ compile errors. And `.window` itself is macOS **15.0**, not 14.0. This bites
twice when keeping a macOS-13 deployment (see §1.3 and gotcha 8).

`ToolbarPlacement.windowToolbar` (macOS-only) is the correct target for
`toolbarBackgroundVisibility` in the now-playing window; `.automatic` also works
but is less explicit.

### 6.5 Toolbar composition additions

```swift
// [COMPILED] api-scratch/Sources/APIScratch/ChromeEffects.swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { } label: { Image(systemName: "gearshape") }
    }
    .visibilityPriority(.init(higherThan: .automatic))   // macOS 27.0
    .sharedBackgroundVisibility(.hidden)                 // macOS 26.0

    ToolbarSpacer(.fixed)                                // macOS 26.0
    ToolbarSpacer(.flexible, placement: .automatic)
}
```
* `sharedBackgroundVisibility` and `visibilityPriority` are declared on
  **`ToolbarContent`**, not `View`/`Button` **[SDK]**
  (`SwiftUI…swiftinterface:7320`, `:13362`).
* `.toolbar(id:)` (customizable) requires **every element** to conform to
  `CustomizableToolbarContent`; `sharedBackgroundVisibility` returns plain
  `ToolbarContent`, so keep those two demos in separate toolbar builders
  **[COMPILED]**.
* `ToolbarItemVisibilityPriority` type is macOS **26.1**; the
  `init(lowerThan:)`/`init(higherThan:)` are macOS **27.0** **[SDK]**
  (`SwiftUI…:13362–13390`).

---

## 7. Materials & color

### 7.1 Materials (macOS 12+)

`Material` (`SwiftUICore…:7987`) variants: `.ultraThin`, `.thin`, `.regular`,
`.thick`, `.ultraThick`, plus `.bar` (macOS 12, tvOS/watchOS unavailable).
Use `.background(.regularMaterial, in: shape)` for fallbacks and chrome that
should **not** be glass (e.g. window-level backgrounds, list rows).

**No new material names were added in macOS 26/27** — the `Material` struct still
exposes exactly the five thickness variants + `.bar`; `NSVisualEffectView`
materials are unchanged since macOS 10.14 (§10.6). Likewise there is **no**
`.glassBackgroundEffect` in this SDK (0 occurrences in both SwiftUI and
SwiftUICore interfaces): the glass API is `.glassEffect` / `NSGlassEffectView`
only. The Liquid-Glass-era "material" additions are the symbol/render modes and
`Color.ResolvedHDR`, not new `Material` cases.

### 7.2 `MaterialActiveAppearance` (macOS 15+)

```swift
// [SDK] SwiftUICore…:8070 / :8088 / :8100 / :8119, macOS 15.0
Text("…").materialActiveAppearance(.matchWindow)   // View modifier
.regularMaterial.materialActiveAppearance(.active) // Material (ShapeStyle) method
@Environment(\.materialActiveAppearance)
```
Values: `.automatic`, `.active`, `.inactive`, `.matchWindow`.
For custom chrome use `.matchWindow` so it dims when the app is inactive
(`.inactive` for always-dimmed surfaces inside inactive windows).
**Gotcha [COMPILED]:** `Color.blue.materialActiveAppearance(.matchWindow)` is
ambiguous (`Color` is both `View` and `ShapeStyle`) — apply it to a container
View or to a `Material` value, not to `Color` directly.

### 7.3 Color / album-art tinting

**`Color(.systemRed)` vs `Color(nsColor:)`:** the *unlabeled* `Color(_ color: NSColor)`
initializer still works (verified compile), but it is **deprecated** since
macOS 10.15 with the message *"Use Color(nsColor:) when converting a NSColor,
or create a standard Color directly"* (`SwiftUICore…:25204–25217`). Always use
the labeled form, or a SwiftUI semantic color directly.

```swift
// [COMPILED] api-scratch/Sources/APIScratch/MaterialsColors.swift
Color(nsColor: .labelColor)
Color(nsColor: .secondaryLabelColor)
Color(nsColor: .separatorColor)
Color(nsColor: .controlAccentColor)
Color(nsColor: .selectedContentBackgroundColor)
Color(nsColor: .windowBackgroundColor)
Color.Resolved(red: 0.20, green: 0.55, blue: 1.0, opacity: 1.0)   // macOS 14.0
Color.ResolvedHDR(base, headroom: 2.0)                           // macOS 26.0
Color.blue.mix(with: .red, by: 0.35)                              // macOS 15.0
Color.orange.brightness(0.05).saturation(0.9).contrast(1.05).colorMultiply(.white)
```

Album-art tinting recipe for PureListen **[INFERRED design, uses SDK types]**:
1. Compute the artwork's dominant color once when the track changes
   (CoreImage `CIAreaAverage` on a downsampled CGImage → `Color.Resolved`).
2. Store **`Color.Resolved`** (macOS 14+) instead of `Color` to avoid repeated
   environment resolution in the hot path.
3. Apply as a **low-opacity wash** behind glass: `tint.opacity(0.18…0.30)`, and
   a `LinearGradient` from tint → clear behind artwork.
4. Derive hover/pressed variants with `Color.mix(with:by:)` (macOS 15) rather
   than hard-coding hexes.
5. Keep text `.primary/.secondary` — never use the album tint for text contrast.
6. HDR glow only on artwork highlights and only when
   `NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1`
   (`Color.ResolvedHDR` / `NSColor(…, exposure:)`, §10.4).

Semantic hierarchy rules: `.primary` → `.secondary` → `.tertiary` →
`.quaternary`; separators `.separator`; fills `.quaternary`; accent via
`Color(nsColor: .controlAccentColor)`/`.tint`.

---

## 8. SF Symbols & typography

### 8.1 Symbols

| API | Availability | Use |
|---|---|---|
| `Image(systemName:)` | macOS 11.0 | all icons |
| `Image(systemName:variableValue:)` | macOS 13.0 | volume bars, signal-strength style |
| `.symbolRenderingMode(.monochrome/.hierarchical/.palette/.multicolor)` | macOS 12.0 | depth/color treatment |
| `.symbolEffect(.bounce/.pulse/.variableColor…, value:/isActive:)` | macOS 14.0 | press/track-change/playing feedback |
| `.contentTransition(.symbolEffect(.replace))` | macOS 14.0 | play⇄pause morph |
| `.symbolVariableValueMode(.draw/.color)` | macOS 26.0 | SF Symbols 8 variable drawing |
| `.symbolColorRenderingMode(.flat/.gradient)` | macOS 26.0 | layered color style |
| `NSImage(systemSymbolName:accessibilityDescription:)` | macOS 11.0 | menu-bar/AppKit icons |
| `NSImage.SymbolConfiguration(pointSize:weight:)` | macOS 11.0 | AppKit icon metrics |
| `NSImage.SymbolConfiguration(variableValueMode:/colorRenderingMode:)` | macOS 26.0 | AppKit equivalents of the 26 modes |

```swift
// [COMPILED] api-scratch/Sources/APIScratch/SymbolsTypography.swift
Image(systemName: "speaker.wave.3.fill", variableValue: 0.66)
    .font(.system(size: 22))
    .symbolVariableValueMode(.draw)

Image(systemName: isPlaying ? "pause.fill" : "play.fill")
    .contentTransition(.symbolEffect(.replace))

Image(systemName: "waveform")
    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
```
Menu-bar icon must be a **template image** so the system tints it for the menu
bar (NSStatusBarButton.h doc): `image.isTemplate = true` **[SDK DOC]**.

### 8.2 Typography

| API | Availability |
|---|---|
| `.font(.system(size:weight:design:))` | macOS 11.0 |
| `.fontDesign(.rounded/.monospaced/.serif)` | macOS 13.0 |
| `.fontWidth(.condensed/.expanded/.standard)` | macOS 13.0 |
| `.monospacedDigit()` | macOS 12.0 |
| `.tracking(_:)` | macOS 13.0 |
| `NSFont.systemFont(ofSize:weight:width:)` | macOS 13.0 |
| `NSFont.monospacedDigitSystemFont(ofSize:weight:)` | macOS 10.11 |
| `NSFont.preferredFont(forTextStyle:)` | macOS 11.0 |
| `NSFontDescriptor.withDesign(.rounded)` | macOS 10.15 |

Recommended PureListen ramp **[INFERRED]** (13 pt body is the macOS-native
density for a compact popover):

```swift
Text("夜航").font(.system(size: 15, weight: .semibold, design: .rounded))
Text("24-bit / 96 kHz · 无损")
    .font(.system(size: 11, weight: .medium, design: .monospaced))
    .foregroundStyle(.secondary)
Text("03:24 / 05:11")
    .font(.system(size: 11, weight: .medium))
    .monospacedDigit()                    // stable timecode width
Text("Rounded + condensed")
    .font(.system(size: 12, weight: .semibold))
    .fontDesign(.rounded).fontWidth(.condensed).tracking(0.4)
```

Numbers: time counters → `.monospacedDigit()` always; metadata → 10–11 pt
`.secondary`; headline → 13–15 pt semibold; now-playing title → 22–24 pt bold
rounded; do not import iOS dynamic-type sizes into a 360 pt popover.

---

## 9. Accessibility & appearance — Reduce Transparency etc.

### 9.1 Detection

| Signal | SwiftUI | AppKit |
|---|---|---|
| Reduce Transparency | `@Environment(\.accessibilityReduceTransparency)` (macOS 10.15) | `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` (10.10) |
| Increase Contrast | `@Environment(\.colorSchemeContrast)` → `.increased` | `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` (10.10) |
| Differentiate w/o color | — | `…accessibilityDisplayShouldDifferentiateWithoutColor` (10.10) |
| Reduce Motion | `@Environment(\.accessibilityReduceMotion)` | `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (10.12) |
| Raise events | — | `NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification` (10.10) |
| High-contrast appearance | — | `NSAppearance.Name.accessibilityHighContrastAqua/.…DarkAqua` via `bestMatch(from:)` (10.14) |
| Vibrancy support | — | `NSAppearance.allowsVibrancy` (10.10) |

AppKit declarations live in **`NSAccessibility.h:94–106,121`**, not `NSWorkspace.h`
(so grepping `NSWorkspace.h` for them fails — it also means no new 26/27 API
was added for this).

```swift
// [COMPILED] api-scratch/Sources/APIScratch/AccessibilityAppearance.swift
@MainActor
final class AccessibilityDisplayObserver: ObservableObject {
    @Published private(set) var shouldReduceTransparency = false
    private var cancellable: AnyCancellable?

    init() {
        refresh()
        cancellable = NotificationCenter.default
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        shouldReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}
```
(The Swift overlay also offers the newer
`.accessibilityDisplayOptionsDidChange` message identifier — macOS 26.0,
`AppKit.swiftinterface:1181`.)

### 9.2 Degradation rules for glass

```swift
// [COMPILED] api-scratch/Sources/APIScratch/AccessibilityAppearance.swift
struct GlassAwareCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
        }
    }
}
```
Rules **[INFERRED, standard a11y practice]**:
* Reduce Transparency → replace glass with **opaque** `windowBackgroundColor`
  (or `.regularMaterial` if the OS still wants translucency) and keep layout
  identical (no size shifts).
* Increase Contrast → strengthen the stroke (0.5 → 1.5 pt), use full-opacity
  label colors, never rely on shadow alone for affordance.
* Reduce Motion → skip `matchedGeometry`/spring morphs; use
  `.glassEffectTransition(.identity)` or `nil` animation.
* Never animate glass tint with a repeating animation when Reduce Motion is on.

### 9.3 macOS 27 "Liquid Glass diffusion/transparency" setting

The brief mentions macOS 27's global Liquid Glass transparency/diffusion slider.
**SDK finding:** there is **no public API** for it in the 27.0 SDK. The AppKit
binary (`AppKit.tbd`) exports `_NSGlassEffectDiffusionDidChangeNotification`,
`NSGlassEffectViewMaterialContext`, and `_NSGlassEffectViewMaterialContext` —
but **none is declared in any public header/swiftinterface**. Treat them as SPI:
the OS applies the user's diffusion preference to system glass automatically; our
glass should simply not hard-code opacity/blur values that would fight it.
**[INFERRED + verified absence from headers]**

---

## 10. AppKit Liquid Glass & macOS 27 corner API

### 10.1 `NSGlassEffectView` (macOS 26) / `NSGlassEffectView.effectIsInteractive` (macOS 27)

`AppKit/NSGlassEffectView.h` **[SDK]**
```objc
API_AVAILABLE(macos(26.0))
@interface NSGlassEffectView: NSView
@property (nullable, strong) __kindof NSView *contentView;
@property CGFloat cornerRadius;
@property (nullable, copy) NSColor *tintColor;
@property NSGlassEffectViewStyle style;              // .regular / .clear
@property BOOL effectIsInteractive API_AVAILABLE(macos(27.0));   // default NO
@end
```
Header notes **[SDK DOC]**: `contentView` is the only view guaranteed inside the
glass ("arbitrary subviews aren't guaranteed specific behavior with regard to
z-order"); `effectIsInteractive` should be enabled when the glass is the
background of / container for interactive controls.

### 10.2 `NSGlassEffectContainerView` (macOS 26)

```objc
API_AVAILABLE(macos(26.0))
@interface NSGlassEffectContainerView: NSView
@property (nullable, strong) __kindof NSView *contentView;
@property CGFloat spacing;   // default 0 = batching only, no merging
@end
```
Doc **[SDK DOC]**: it elevates descendant glass above contentView, merges
descendants "if the views are sufficiently similar and within the proximity
specified in spacing", and batches rendering. Same semantics as SwiftUI's
container: 0 for performance only, >0 for merging.

### 10.3 macOS 27 view-corner system (new)

Headers: `NSViewCornerRadius.h`, `NSViewCornerConfiguration.h`,
`NSViewCornerRadii.h`; `NSView.h:611–625`.

```swift
// [SDK] macOS 27.0
NSViewCornerRadius.fixed(_ radius: CGFloat)
NSViewCornerRadius.containerConcentric(_ minimumRadius: CGFloat)
NSViewCornerRadius.containerConcentric

NSViewCornerConfiguration.corners(radius:)
NSViewCornerConfiguration.corners(topLeftRadius:topRightRadius:bottomLeftRadius:bottomRightRadius:)
NSViewCornerConfiguration.capsule / .capsule(maximumRadius:)
NSViewCornerConfiguration.uniformCorners(radius:)
NSViewCornerConfiguration.uniformCorners(radius:topLeftRadius:topRightRadius:bottomLeftRadius:bottomRightRadius:)
NSViewCornerConfiguration.uniformEdges(topRadius:bottomRadius:) / .uniformEdges(leftRadius:rightRadius:)
NSViewCornerConfiguration.uniformTopRadius(_:bottomLeftRadius:bottomRightRadius:)
NSViewCornerConfiguration.uniformBottomRadius(_:topLeftRadius:topRightRadius:)
NSViewCornerConfiguration.uniformLeftRadius(_:topRightRadius:bottomRightRadius:)
NSViewCornerConfiguration.uniformRightRadius(_:topLeftRadius:bottomLeftRadius:)
```

`NSView` additions (**get-only**):

```swift
// [SDK] NSView.h:611-625, macOS 27.0
@available(macOS 27.0, *)
extension NSView {
    var cornerConfiguration: NSViewCornerConfiguration? { get }   // readonly!
    var effectiveCornerRadii: NSViewCornerRadii? { get }
    func viewDidChangeEffectiveCornerRadii()                     // override hook
    func invalidateCornerConfiguration()
}
```

**The only way to supply a configuration is to override the getter** — verified
by compiler:

```
error: cannot assign to property: 'cornerConfiguration' is a get-only property
```

```swift
// [COMPILED] api-scratch/Sources/APIScratch/AppKitGlassViews.swift
@available(macOS 27.0, *)
final class ConcentricPanelView: NSView {
    override var cornerConfiguration: NSViewCornerConfiguration? {
        .uniformTopRadius(.fixed(20),
                          bottomLeftRadius: .containerConcentric,
                          bottomRightRadius: .containerConcentric)
    }
    override func viewDidChangeEffectiveCornerRadii() {
        guard let radii = effectiveCornerRadii else { return }
        layer?.cornerRadius = radii.topLeft       // AppKit resolved the real radii
    }
    func refreshCorners() { invalidateCornerConfiguration() }
}
```
This is how a custom AppKit-rendered card follows macOS 27's **system window
radius** without hard-coding it: `containerConcentric` resolves against the
window/presentation radius, honouring the OS's tightened uniform radius.

### 10.4 `NSBackgroundExtensionView` (macOS 26)

`AppKit/NSBackgroundExtensionView.h` **[SDK]**: `contentView`,
`automaticallyPlacesContentView` (default YES) — AppKit version of
`backgroundExtensionEffect`, for NSView hierarchy based chrome.

### 10.5 AppKit controls & symbols on 26

| API | Header | Availability |
|---|---|---|
| `NSControl.BorderShape` `.automatic/.capsule/.roundedRectangle/.circle` | `NSControl.h:152` | 26.0 |
| `NSButton.borderShape`, `NSButton.tintProminence` | `NSButton.h:179`, `:124` | 26.0 |
| `NSSlider.tintProminence`, `NSSlider.neutralValue` | `NSSlider.h:33`, `:24` | 26.0 |
| `NSTextField.borderShape`, `.placeholderStrings` | `NSTextField.h:46`, `:70` | 26.0 |
| `NSTintProminence` `.automatic/.none/.primary/.secondary` | `NSTintProminence.h` | 26.0 |
| `NSToolbarItem.Style` `.plain/.prominent`, `backgroundTintColor`, `badge`/`NSItemBadge` | `NSToolbarItem.h:25`, `:142`, `:200` | 26.0 |
| `NSImage.SymbolConfiguration(variableValueMode:)`, `(colorRenderingMode:)` | `NSImage.h:619`, `:624` | 26.0 |
| `NSColor(…, exposure:)`, `(…, linearExposure:)`, `linearExposure`, `standardDynamicRange` (Swift name) | `NSColor.h:164`, `:167`, `:376` | 26.0 |
| `NSSplitViewItem` top/bottom accessory VCs, `automaticallyAdjustsSafeAreaInsets` | `NSSplitViewItem.h:140–155` | 26.0 |
| `NSView.LayoutRegion` / `NSViewLayoutRegion.h` | — | 26.0 |
| `NSScreen.CGDirectDisplayID` | `NSScreen.h:73` | 26.0 |
| `NSWindow.beginSheet(content:)` / `endSheet(_:)` (SwiftUI) | `SwiftUI…:32533–32534` | 26.0 |

### 10.6 `NSVisualEffectView` (fallback + non-glass surfaces)

Materials unchanged since 10.14 (`NSVisualEffectView.h`): `.titlebar`,
`.selection`, `.menu`, `.popover`, `.sidebar`, `.headerView`, `.sheet`,
`.windowBackground`, `.hudWindow`, `.fullScreenUI`, `.toolTip`,
`.contentBackground`, `.underWindowBackground`, `.underPageBackground`.
Use `.popover` for the pre-26 popover fallback, `.underWindowBackground` for a
custom now-playing window, `.selection` for selected rows. `.bar` (SwiftUI
Material) is the toolbar equivalent.

---

## 11. AppKit window / popover / menu-bar chrome

### 11.1 There is **no** `NSWindow.cornerRadius`

Confirmed: `NSWindow.h` contains **no** new macOS 26/27 API at all (grep for
`macos(26.0)|macos(27.0)` = 0 hits), and there is no corner-radius property.
System windows and `NSPopover` get their radius from the OS (macOS 27 tightened
it uniformly). For custom chrome:

* **SwiftUI borderless window content**: `window.isOpaque = false;
  backgroundColor = .clear; hasShadow = true`, then clip the SwiftUI root with
  `ConcentricRectangle`/`RoundedRectangle(style: .continuous)` and use
  `.containerShape(...)` for nested concentric cards.
* **AppKit custom view**: `NSViewCornerConfiguration` (macOS 27, §10.3) or
  `layer.cornerRadius` + `cornerCurve = .continuous` (pre-27).
* For control placement near corners use `.containerCornerOffset(...)` (§5.6),
  which is corner-inset-aware.

### 11.2 Menu-bar panel window (expanded interface)

```swift
// [COMPILED] api-scratch/Sources/APIScratch/AppKitWindowChrome.swift
let panel = NSWindow(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless, .fullSizeContentView],
    backing: .buffered, defer: false
)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.level = .statusBar
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
panel.animationBehavior = .utilityWindow
panel.hidesOnDeactivate = true
panel.isReleasedWhenClosed = false
panel.contentView = NSHostingView(rootView: AnyView(content))
```
Use `NSPopover` instead when the UI is popover-shaped and transient (it gets
system radius/material/animation for free); with `hasFullSizeContent = true`
(macOS 14) you can bleed the artwork edge-to-edge and read safe-area insets.

Borderless windows cannot become key by default — subclass and override
`canBecomeKey` (compiled in `AppKitWindowChrome.swift`) when the popover contains
a search field.

### 11.3 `NSPopover` (macOS 13+)

`behavior = .transient`, `hasFullSizeContent = true` (macOS 14+),
`contentViewController = NSHostingController(rootView:)`,
`contentSize = NSSize(width: 360, height: 560)`, `appearance` for forced
light/dark, `animates`.

### 11.4 `NSStatusItem` — with the macOS 27 expanded-interface session

Classic setup (all versions):

```swift
// [COMPILED] api-scratch/Sources/APIScratch/AppKitStatusItem.swift
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.autosaveName = "PureListen.MenuBarItem"
item.behavior = [.removalAllowed]
item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "净听")
item.button?.image?.isTemplate = true
```

macOS 27 proper lifecycle (`NSStatusItem.h:27–84`, header doc quoted verbatim):

> *"Status items which do not use an NSMenu but instead position other windows
> ('expanded interface') relative to the item should begin showing their expanded
> interface upon receipt of this message. This method should be used instead of
> manually toggling your interface by target/action handling on the button or
> item. … This allows the status item to participate in keyboard navigation and
> menu tracking behaviors."*

```swift
// [COMPILED] api-scratch/Sources/APIScratch/AppKitStatusItem.swift
@available(macOS 27.0, *)
final class ExpandedInterfaceDelegate: NSObject, NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem,
                    didBegin session: NSStatusItemExpandedInterfaceSession) { showWindow() }
    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem,
                                                  animated: Bool) { hideWindow(animated: animated) }
}
statusItem.expandedInterfaceDelegate = delegate
// when dismissing by other user action (outside click/Escape/action that closes):
statusItem.expandedInterfaceSession?.cancel()
```
Rules **[SDK DOC + INFERRED]**:
* If `statusItem.menu` is non-nil, AppKit handles the menu and the 27 delegate
  callbacks are **not** delivered.
* The delegate owns showing/hiding the window; call `session.cancel()` if the
  UI was dismissed by other means.
* Below macOS 27, keep the classic button target/action + `NSPopover` toggle.

### 11.5 Menu items in macOS 27

New default: **menu-item images are hidden** unless requested.
`NSMenuItem.h:95` doc **[SDK DOC]**:

> *"in macOS 27 and later, AppKit determines the visibility of menu item images,
> and will typically hide images. Use the `preferredImageVisibility` property
> with the `.visible` constant to specify that an image should always be
> visible."*

→ Any status-item menu entries with icons must set
`.preferredImageVisibility = .visible` (macOS 27) or accept hidden images.

---

## 12. macOS 27-only additions relevant to a polished UI

| API | Availability | Why it matters |
|---|---|---|
| `NSGlassEffectView.effectIsInteractive` | 27.0 | AppKit glass reacts to pointer/press |
| `NSViewCornerConfiguration` / `NSViewCornerRadius` / `NSViewCornerRadii` + `NSView` overrides | 27.0 | custom AppKit chrome follows system (tightened) window radius, concentric by default |
| `NSStatusItem.expandedInterfaceDelegate` / `expandedInterfaceSession` + `NSStatusItemExpandedInterfaceSession.cancel()` | 27.0 | correct menu-bar popover lifecycle, keyboard nav/menu tracking, Escape/outside-click handling |
| `ToolbarItemVisibilityPriority.init(lowerThan:/higherThan:)` | 27.0 | control toolbar overflow order (`SwiftUI…:13378`) |
| `EmptyView`/`TupleContent` conform to `ToolbarContent` | 27.0 | `if`/`switch` inside `.toolbar {}` (`SwiftUI…:22171/22178`) |
| `NSMenuItem.preferredImageVisibility` + `NSMenuItem.ImageVisibility` | 27.0 | macOS 27 hides menu item images by default |
| `NSControl.Event` new cases (`trackingRepeated`, `valueChanged`, `primaryActionTriggered`, `menuActionTriggered`) | 27.0 | richer control event handling (`NSControl.h:168–194`) |
| `NSScreen.touchCapabilities` | 27.0 | multi-touch capability detection (`NSScreen.h:75`) |
| `NSScrollView.touchScrollingEnabled` etc. + `NSRefreshController` | 27.0 | touch scrolling / pull-to-refresh |
| `NSApplicationPresentationDisableScreenCornerInteractions` | 27.0 | window behavior near screen corners |
| SwiftUI `TabsPickerStyle` (`.tabs`) | 27.0 | tab-strip picker |
| SwiftUI list `reorderable()`/`reorderContainer`/`reorderDestination` | 27.0 | native drag reorder for the playlist (27-only) |
| SwiftUI `swipeActions(…, onPresentationChanged:)`, `swipeActionsContainer()` | 27.0 | track swipe expansion |
| `AnyNavigationTransition` | 27.0 | erase navigation transitions |

**Not present (do not plan around them):**
* no new SwiftUI liquid-glass API on 27 (it's all 26);
* no public global "glass diffusion" API (`_NSGlassEffectDiffusionDidChangeNotification`
  is SPI, §9.3);
* no `NSWindow.cornerRadius`/`cornerConfiguration` API on 26 or 27;
* no `glassBackgroundEffect`, `RoundedRectangularShapeCorners`-as-Shape, or
  `NSViewCornerConfiguration` setter (get-only).

---

## 13. Full availability matrix (≈50 production APIs)

`S` = SwiftUI/SwiftUICore interface line, `A` = AppKit header line.
All paths relative to `$SDK`; `SwiftUI`/`SwiftUICore` = their `Modules/<module>.swiftmodule/arm64e-apple-macos.swiftinterface`.

### SwiftUI / SwiftUICore

| API | Min macOS | Evidence |
|---|---|---|
| `.glassEffect(_:in:)` | 26.0 | `SwiftUICore:3064` |
| `Glass`, `.regular/.clear/.identity`, `.tint`, `.interactive` | 26.0 | `SwiftUICore:7245` |
| `DefaultGlassEffectShape` (capsule) | 26.0 | `SwiftUICore:3069` |
| `GlassEffectContainer(spacing:)` | 26.0 | `SwiftUICore:11523` |
| `.glassEffectID(_:in:)` | 26.0 | `SwiftUICore:22411` |
| `.glassEffectUnion(id:namespace:)` | 26.0 | `SwiftUICore:12644` |
| `.glassEffectTransition(_:)` + `GlassEffectTransition` | 26.0 | `SwiftUICore:3498,3512` |
| `GlassButtonStyle` (`.glass`) | 26.0 | `SwiftUI:1480` |
| `GlassProminentButtonStyle` (`.glassProminent`) | 26.0 | `SwiftUI:4465` |
| `ConcentricRectangle` + inits | 26.0 | `SwiftUICore:16935` |
| `Edge.Corner`, `Edge.Corner.Style`, `.fixed/.concentric` | 26.0 | `SwiftUICore:24731–24813` |
| `RoundedRectangularShape`, `RoundedRectangularShapeCorners` | 26.0 | `SwiftUICore:17037,17043` |
| `.containerShape(some RoundedRectangularShape)` | 26.0 | `SwiftUICore:17082` |
| `.containerShape<T: InsettableShape>` (old) | 12.0 | `SwiftUICore:17954` |
| `.containerCornerOffset(_:sizeToFit:)` | 26.0 | `SwiftUICore:22153` |
| `RectangleCornerInsets`, `EdgeInsets.inset(by:)` | 26.0 | `SwiftUICore:3087,3102` |
| `backgroundExtensionEffect()` / `(isEnabled:)` | 26.0 | `SwiftUI:15832,15835` |
| `ScrollEdgeEffectStyle`, `.scrollEdgeEffectStyle`, `.scrollEdgeEffectHidden` | 26.0 | `SwiftUI:15907,15926,15930` |
| `.safeAreaBar(edge:…)` | 26.0 | `SwiftUI:22856,22859` |
| `.toolbarBackgroundVisibility(_, for:)` | 15.0 | `SwiftUI:12820` |
| `.containerBackground(_, for: .window)` | 15.0 (mod 14.0) | `SwiftUI:16336,16311` |
| `ToolbarSpacer`, `SpacerSizing` | 26.0 | `SwiftUI:29510`, `SwiftUI:286` |
| `.sharedBackgroundVisibility(_:)` (ToolbarContent) | 26.0 | `SwiftUI:7320,7328` |
| `ToolbarItemVisibilityPriority` (type + `.low/.high`) | 26.1 | `SwiftUI:13362` |
| `ToolbarItemVisibilityPriority.init(lowerThan:/higherThan:)` | 27.0 | `SwiftUI:13378,13383` |
| `.buttonSizing(_:)` / `ButtonSizing` | 26.0 | `SwiftUICore:4316` |
| `.controlSize(_:)` single / `.controlSize(range)` | 10.15 / 26.0 | `SwiftUICore:7816` |
| `Material` variants, `Material.bar` | 12.0 | `SwiftUICore:7987,8033` |
| `MaterialActiveAppearance` + env + modifiers | 15.0 | `SwiftUICore:8070–8119` |
| `Color.Resolved`, `Color(_:)` | 14.0 | `SwiftUICore:2726` |
| `Color.ResolvedHDR`, `Color.init(ResolvedHDR)` | 26.0 | `SwiftUICore:10020,17225` |
| `Color.mix(with:by:in:)` | 15.0 | `SwiftUICore:21231` |
| `.symbolRenderingMode` | 12.0 | `SwiftUICore:8635` |
| `.symbolEffect(_:options:isActive:/value:)` | 14.0 | `SwiftUICore:16513,16518` |
| `.contentTransition(_:)` / `.contentTransition(.symbolEffect(_:))` | 13.0 / 14.0 | `SwiftUICore:20454`, `:16735` |
| `Image(systemName:)` / `(systemName:variableValue:)` | 11.0 / 13.0 | `SwiftUICore:11239,11249` |
| `SymbolVariableValueMode` + `.symbolVariableValueMode` | 26.0 | `SwiftUICore:8641–8655` |
| `SymbolColorRenderingMode` + `.symbolColorRenderingMode` | 26.0 | `SwiftUICore:8665–8690` |
| `Font.system(size:weight:design:)`, `.fontDesign`, `.fontWidth`, `.monospacedDigit`, `.tracking` | 11/13/12/13 | `SwiftUICore:21662,21653,21644,21668` |
| `@Environment(\.accessibilityReduceTransparency)` | 10.15 | `SwiftUICore:23459` |
| `@Environment(\.colorSchemeContrast)` | 10.15 | `SwiftUICore:23916` |
| `TabsPickerStyle` (`.tabs`) | 27.0 | `SwiftUI:16653` |
| `AnyNavigationTransition` | 27.0 | `SwiftUI:11402` |
| `EmptyView`/`TupleContent` : `ToolbarContent` | 27.0 | `SwiftUI:22171,22178` |

### AppKit

| API | Min macOS | Evidence |
|---|---|---|
| `NSGlassEffectView` (contentView/cornerRadius/tintColor/style) | 26.0 | `A:NSGlassEffectView.h:24` |
| `NSGlassEffectView.effectIsInteractive` | 27.0 | `A:NSGlassEffectView.h:45` |
| `NSGlassEffectContainerView` (contentView/spacing) | 26.0 | `A:NSGlassEffectView.h:53` |
| `NSBackgroundExtensionView` | 26.0 | `A:NSBackgroundExtensionView.h:23` |
| `NSViewCornerConfiguration` factories | 27.0 | `A:NSViewCornerConfiguration.h` |
| `NSViewCornerRadius.fixed/.containerConcentric` | 27.0 | `A:NSViewCornerRadius.h` |
| `NSViewCornerRadii` (read-only) | 27.0 | `A:NSViewCornerRadii.h` |
| `NSView.cornerConfiguration/effectiveCornerRadii/viewDidChangeEffectiveCornerRadii/invalidateCornerConfiguration` | 27.0 | `A:NSView.h:611–625` |
| `NSStatusItem.expandedInterfaceDelegate` / `.expandedInterfaceSession` | 27.0 | `A:NSStatusItem.h:80,84` |
| `NSStatusItemExpandedInterfaceDelegate` / `…Session.cancel()` | 27.0 | `A:NSStatusItem.h:27–36`, `NSStatusItemExpandedInterfaceSession.h` |
| `NSVisualEffectView` + materials | 10.10 | `A:NSVisualEffectView.h:92` |
| `NSPopover.hasFullSizeContent` | 14.0 | `A:NSPopover.h:159` |
| `NSWindow` style/transparency/toolbar APIs | 10.10–11.0 | `A:NSWindow.h:306–517,644` |
| `NSHostingView.sizingOptions` / `.safeAreaRegions` | 13.0 | `SwiftUI:12074–12089` |
| `NSHostingController` same | 13.0 | `SwiftUI:1045–1071` |
| `NSWindow.beginSheet(content:)` / `endSheet(_:)` | 26.0 | `SwiftUI:32540+` |
| `NSControl.BorderShape` / `NSButton.borderShape` / `NSTextField.borderShape` | 26.0 | `A:NSControl.h:152`, `NSButton.h:179`, `NSTextField.h:46` |
| `NSTintProminence` + button/slider `tintProminence` | 26.0 | `A:NSTintProminence.h`, `NSButton.h:124`, `NSSlider.h:33` |
| `NSSlider.neutralValue` | 26.0 | `A:NSSlider.h:24` |
| `NSTextField.placeholderStrings` | 26.0 | `A:NSTextField.h:70` |
| `NSToolbarItem.Style`/`backgroundTintColor`/`badge`/`NSItemBadge` | 26.0 | `A:NSToolbarItem.h:25,142,200` |
| `NSMenuItem.preferredImageVisibility` | 27.0 | `A:NSMenuItem.h:101`, doc `:95` |
| `NSColor(…, exposure:)`/`linearExposure`/`standardDynamicRange` | 26.0 | `A:NSColor.h:164,167,376` |
| `NSImage.SymbolConfiguration(variableValueMode:/colorRenderingMode:)` | 26.0 | `A:NSImage.h:619,624` |
| `NSWorkspace.accessibilityDisplayShouldReduceTransparency/…IncreaseContrast/…ReduceMotion` + notification | 10.10/10.12 | `A:NSAccessibility.h:94–106,121` |
| `NSAppearance` high-contrast names + `bestMatch(from:)` | 10.14 | `A:NSAppearance.h:76–79` |
| `NSScreen` EDR values | 10.11/10.15 | `A:NSScreen.h:89–97` |
| `NSScreen.touchCapabilities` / `CGDirectDisplayID` | 27.0 / 26.0 | `A:NSScreen.h:73,75` |
| `NSApplicationPresentationDisableScreenCornerInteractions` | 27.0 | `A:NSApplication.h:178` |
| `NSSplitViewItem` accessory VCs + safe area adjust | 26.0 | `A:NSSplitViewItem.h:140–155` |
| `NSScrollView` touch scrolling + `NSRefreshController` | 27.0 | `A:NSScrollView.h:137–151,184` |
| `NSControl.Event` new cases | 27.0 | `A:NSControl.h:168–198` |

---

## 14. Reference recipes (drop-in for PureListen)

All snippets are taken from the compiled scratch package; see the file named per
recipe for the full compiling context.

### 14.1 360×560 popover skeleton

```
┌──────────────────────────────────────────┐  ← system popover material + radius (OS-drawn)
│  [art 44]  夜航                    [ ⋯ ] │  ← glass chips + glass icon buttons
│            净听 · 24bit/96kHz       [♡]  │
│  ┌───────────────────────────────────┐   │  ← .containerShape(.rect(cornerRadius: 14))
│  │ art 240 + concentric corner 16    │   │     first-level card: ConcentricRectangle(.concentric)
│  └───────────────────────────────────┘   │
│  ┌───────────────────────────────────┐   │  ← interior card: .fixed(10…12)
│  │ playlist rows…                    │   │     scrollEdgeEffectStyle(.soft, for: .all)
│  └───────────────────────────────────┘   │
│  ═══ safeAreaBar(edge: .bottom) ═══════  │  ← persistent transport bar (glass)
│  [shuffle] [prev] [ ▶ ] [next] [repeat]  │
└──────────────────────────────────────────┘
```

```swift
// [COMPILED] api-scratch/Sources/APIScratch/ChromeEffects.swift (adapted)
struct PureListenPopoverRoot: View {
    @Namespace private var glassNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                nowPlayingHeader
                artworkCard
                playlistCard
            }
            .padding(12)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .containerShape(.rect(cornerRadius: 14))          // macOS 26
        .safeAreaBar(edge: .bottom, spacing: 0) {         // macOS 26
            GlassEffectContainer(spacing: 12) {            // macOS 26
                HStack(spacing: 18) {
                    transportButton("shuffle")
                    transportButton("backward.fill")
                    Button { } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
                    .glassEffectID("play", in: glassNamespace)
                    transportButton("forward.fill")
                    transportButton("repeat")
                }
                .buttonStyle(.glass)                      // macOS 26
                .controlSize(.small)
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 12)
        }
    }

    private func transportButton(_ symbol: String) -> some View {
        Button { } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        }
    }

    private var nowPlayingHeader: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("夜航").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("净听 · 24bit/96kHz")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
                .glassEffect(.regular.interactive(), in: .circle)
        }
    }

    private var artworkCard: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [.indigo.opacity(0.55), .black.opacity(0.25)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(maxWidth: .infinity).frame(height: 220)
            .overlay(alignment: .bottomLeading) {
                GlassChipBadge(text: "FLAC 24/96")
                    .padding(10)
            }
            .containerShape(.rect(cornerRadius: 16))
    }

    private var playlistCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("播放队列")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { i in Text("曲目 \(i + 1)") }
        }
        .padding(12)
        .background(.regularMaterial,
                    in: ConcentricRectangle(corners: .concentric(minimum: .fixed(8))))
    }
}
```
(The `GlassChipBadge` helper is a `Label` + `.glassEffect(.regular.tint(...), in: Capsule())`
— compile-verified in `GlassBasics.swift`.)

### 14.2 Now-playing window (separate NSWindow)

```swift
// [COMPILED] api-scratch/Sources/APIScratch/AppKitWindowChrome.swift
let hosting = NSHostingController(rootView: NowPlayingView())
let window = NSWindow(contentViewController: hosting)
window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
window.title = "正在播放"
window.titlebarAppearsTransparent = true
window.titleVisibility = .hidden
window.toolbarStyle = .unifiedCompact
window.titlebarSeparatorStyle = .none
window.isReleasedWhenClosed = false
window.setContentSize(NSSize(width: 420, height: 560))
```
Content root: `.backgroundExtensionEffect()` on the album-art gradient
(macOS 26), `.containerShape(.rect(cornerRadius: 20))`, artwork
`.rect(cornerRadius: 16)`, toolbar via `.toolbar { ToolbarItem(...) }` +
`ToolbarSpacer(.fixed)`/`.flexible`, control buttons `.buttonStyle(.glass)`.
If custom AppKit chrome is needed, use `NSViewCornerConfiguration` (27) so
corners track the system window radius.

### 14.3 Menu-bar status item (26 vs 27)

```swift
// [COMPILED] api-scratch/Sources/APIScratch/AppKitStatusItem.swift
// 26 and earlier: classic toggle
func install(popover: NSPopover) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "净听")
    item.button?.image?.isTemplate = true
    item.button?.target = self; item.button?.action = #selector(togglePopover)
}
// 27: let AppKit drive the lifecycle
if #available(macOS 27.0, *) {
    statusItem.expandedInterfaceDelegate = expandedDelegate   // show/hide the panel in callbacks
}
// dismissing by other means:
if #available(macOS 27.0, *) {
    statusItem.expandedInterfaceSession?.cancel()
}
```

### 14.4 Reduce Transparency fallback

```swift
// [COMPILED] api-scratch/Sources/APIScratch/GlassFallbacks.swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
content
    .background {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        } else {
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(.regularMaterial)
        }
    }
    .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
        .strokeBorder(borderColor, lineWidth: borderWidth))
```
Plus `NSWindow.isOpaque/backgroundColor` swap from
`AppKitFallbackChrome.applyAccessibilityAppearance(to:)`.

---

## 15. Gotchas (verified unless marked otherwise)

1. **The default glass shape is a Capsule, not a rounded rectangle.**
   `DefaultGlassEffectShape` doc says "a capsule". Pass `.rect(cornerRadius:)`
   explicitly for card-shaped glass. **[SDK DOC]**
2. **Glass is anchored to bounds including padding.** `.padding().glassEffect()`
   vs `.glassEffect().padding()` produce visibly different glass sizes. **[SDK DOC]**
3. **`Glass.clear` requires you to add dimming.** Apple: "ensure content remains
   legible by adding a dimming layer or other treatment beneath the glass."
   **[SDK DOC]**
4. **macOS 27 does not add SwiftUI glass APIs.** Everything glass/shape/chrome in
   SwiftUI is macOS 26.0; the 27 delta is AppKit. **[SDK]**
5. **`ConcentricRectangle` does not conform to `RoundedRectangularShape`**, so it
   cannot be passed to `.containerShape(...)`. Declare the container with
   `RoundedRectangle`/`Capsule`; let `ConcentricRectangle` children inherit.
   **[COMPILED error]**
6. **Concentric radius = container radius − inset distance; may become 0 → square
   corner.** Use `.concentric(minimum: .fixed(x))` or, beyond the first inset
   level, fixed radii. **[SDK DOC]**
7. **`sharedBackgroundVisibility` / `visibilityPriority` live on
   `ToolbarContent`, not `View`.** Apply to `ToolbarItem`, not its `Button`.
   **[COMPILED error]**
8. **`.toolbar(id:)` requires every element to be `CustomizableToolbarContent`.**
   Mixing plain-`ToolbarContent`-only modifiers into it breaks the builder; use two
   separate toolbar builders. **[COMPILED error]**
9. **`ContainerBackgroundPlacement.window` is macOS 15.0, not 14.0**, and it is
   the *only* macOS placement — `.navigation`/`.navigationSplitView`/`.tabView`
   are unavailable on macOS. A macOS-13 deployment therefore needs a 15.0 guard,
   not 14.0. **[COMPILED errors]**
10. **`Color`'s `materialActiveAppearance` is ambiguous** (Color is both View and
    ShapeStyle). Apply on a container View or on a `Material`. **[COMPILED error]**
11. **`ToolbarItemVisibilityPriority` type is 26.1** — at a 26.0 deployment even
    naming the type requires `if #available(macOS 26.1, *)`; `init(lowerThan:)`
    and `init(higherThan:)` are 27.0. **[SDK / COMPILED]**
12. **`NSView.cornerConfiguration` is get-only.** Configure by overriding the
    getter in an `NSView` subclass; AppKit calls
    `viewDidChangeEffectiveCornerRadii()` when resolved radii change; call
    `invalidateCornerConfiguration()` after changing inputs. **[COMPILED error]**
13. **`NSGlassEffectDiffusionDidChangeNotification` / `NSGlassEffectViewMaterialContext`
    are exported in `AppKit.tbd` but have no public header** in the 27.0 SDK.
    Treat as SPI; the OS applies the user's diffusion preference itself.
    **[verified: grep of all AppKit headers + tbd symbols]**
14. **No `NSWindow.cornerRadius` API exists in 26 or 27.** `NSWindow.h` has zero
    new 26/27 API. Clip SwiftUI content or use `NSViewCornerConfiguration` (27);
    system windows/popovers use OS-defined radii. **[SDK]**
15. **`NSStatusItem` with a non-nil `menu` never receives the macOS-27 expanded
    interface callbacks** — pick one mechanism. The delegate must show/hide the
    window and `session.cancel()` on out-of-band dismissal. **[SDK DOC]**
16. **macOS 27 hides menu-item images by default.** Set
    `preferredImageVisibility = .visible` for status-item menu icons. **[SDK DOC]**
17. **Glass inside `NSPopover` reads milky/low-contrast** because the popover
    backdrop is itself a vibrant `.popover` material. Put glass over saturated
    content/artwork, add a dim layer, or use a full-size-content popover with a
    controlled backdrop. **[INFERRED — behavior not provable from headers]**
18. **`NSGlassEffectView.contentView` is the only guaranteed subview inside the
    glass**; arbitrary subviews may render outside/behind the glass. **[SDK DOC]**
19. **`NSGlassEffectContainerView.spacing` default 0 batches but does not merge**;
    merging also requires similar glass views. **[SDK DOC]**
20. **`backgroundExtensionEffect` mirrors/blurs copies, clips them, and should be
    used once per surface**; it needs available safe area to extend into.
    **[SDK DOC]**
21. **`.safeAreaBar` supersedes `safeAreaInset`** when you want the scroll-edge
    effect to continue behind the bar. **[SDK DOC]**
22. **`Image(systemName:variableValue:)` is macOS 13**, its draw/color modes are
    macOS 26; AppKit equivalents are 26-only. **[SDK]**
23. **`build.sh` writes `LSMinimumSystemVersion 13.0` while the manifest now says
    26.0.** Keep them in sync (raise Info.plist to 26.0) or Finder/LaunchServices
    advertises a wrong minimum OS. **[verified by reading build.sh]**
24. **`platforms: [.macOS("27.0")]` vs `.v27`:** the enum symbol needs
    tools-version 6.4; with the app's tools 6.0 the string form is required
    (verified building with both `.v13`→`.macOS("26.0")` and `.macOS("27.0")`).
    **[COMPILED]**
25. **`glassEffect` is unavailable on visionOS** (and container/ID/union); only
    relevant if code is ever shared. **[SDK]**
26. **Menu-bar borderless windows need `canBecomeKey` override** to accept
    keyboard input (search field, Space to play). Otherwise NSPanel/NSPopover.
    **[INFERRED + compiled sample]**
27. **Prefer `regularMaterial` (or opaque window color) for window-level
    backgrounds** — do not stack glass on glass for large areas: the SDK exposes
    glass as a *material for controls/chrome*, and nested glass over glass loses
    contrast and costs render passes. **[INFERRED]**
28. **HDR color is only meaningful on EDR displays**: gate `Color.ResolvedHDR` /
    `NSColor(…, exposure:)` on `NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1`
    and never use HDR for text. **[SDK + INFERRED]**

---

## 16. Verification appendix

### 16.1 Environment commands (measured)

```sh
$ sw_vers
ProductName: macOS   ProductVersion: 27.0.1   BuildVersion: 26A434
$ xcodebuild -version
Xcode 27.1 / Build version 27A9275
$ swift --version
Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.0.0
$ xcrun --show-sdk-path
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
$ xcrun --show-sdk-version
27.0
```

`swift build` therefore defaults to the macOS 27 SDK (`MacOSX.sdk` = 27.0,
`MacOSX27.sdk` symlinks to it). Deployment target still comes from the package
manifest (`-target arm64-apple-macosx<manifest value>` appears in the compile
command lines).

### 16.2 Package builds (all `Build complete!`, no warnings)

```sh
cd docs/research/api-scratch            && swift build   # .macOS("27.0")
cd docs/research/api-scratch/macos13-guards   && swift build   # .macOS(.v13)
cd docs/research/api-scratch/macos26-surface  && swift build   # .macOS("26.0")
```

### 16.3 App-level checks (read-only; done in `/tmp/purelisten-check` copies)

| Check | Result |
|---|---|
| `swift build` untouched repo (manifest `.v13`), SDK 27 | **Build complete (18.0 s, 168 tasks)** |
| copy with `platforms: [.macOS("26.0")]` | **Build complete (18.0 s)** |
| copy with `platforms: [.macOS("27.0")]` | **Build complete (0.4 s incremental)** |
| `swift build --triple arm64-apple-macosx27.0` on unmodified manifest | **Build complete (11.0 s)** |
| built binary after 26.0 build | `LC_BUILD_VERSION minos 26.0 sdk 27.0` |
| built binary after 27.0 build | `LC_BUILD_VERSION minos 27.0 sdk 27.0` |

No audio code was executed; only compiles were run. The app itself was never
launched, and `hogtest`/`apitest` were never run.

### 16.4 Negative tests (captured compiler errors)

Files in `api-scratch/negative-tests/`, each with `*.expected-error.txt`:

| File | Target | Error |
|---|---|---|
| `unguarded-glass-effect.swift` | macosx13.0 | `'glassEffect(_:in:)' is only available in macOS 26.0 or newer` |
| `unguarded-concentric-rectangle.swift` | macosx13.0 | `'ConcentricRectangle' is only available in macOS 26.0 or newer` |
| `glass-effect-unguarded-13.swift` | macosx13.0 | `'NSGlassEffectView' is only available in macOS 26.0 or newer` |
| `unguarded-container-background-window.swift` | macosx14.0 | `'window' is only available in macOS 15.0 or newer` |
| `container-background-navigation-macos.swift` | macosx27.0 | `'navigation' is unavailable in macOS` |
| `nsview-corner-configuration-setter.swift` | macosx27.0 | `cannot assign to property: 'cornerConfiguration' is a get-only property` |

### 16.5 Symbol-graph/doc extraction commands used

```sh
SDK=$(xcrun --show-sdk-path)
TOOL=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-symbolgraph-extract
$TOOL -module-name SwiftUI     -target arm64-apple-macos27.0 -sdk "$SDK" \
      -output-dir /tmp/sg/swiftui -minimum-access-level public
$TOOL -module-name SwiftUICore -target arm64-apple-macos27.0 -sdk "$SDK" \
      -output-dir /tmp/sg/core -minimum-access-level public
$TOOL -module-name AppKit      -target arm64-apple-macos27.0 -sdk "$SDK" \
      -output-dir /tmp/sg/appkit -minimum-access-level public
```
Doc comments in this cheat sheet marked **[DOC]** come from those `.symbols.json`
files; availability markings come from the `*.swiftinterface` files and AppKit
headers directly.
