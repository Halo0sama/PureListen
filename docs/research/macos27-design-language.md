# macOS 27 "Golden Gate" design language — implementation brief for PureListen (净听)

**Status:** research complete, v1 · **Date:** 2026-10-26 · **Author:** design-researcher (Agent Teams)
**Deliverable for:** PureListen UI redesign (SwiftUI menu-bar app, 360×560 popover)
**Companion:** `docs/research/sdk-api-cheatsheet.md` (compile-verified API availability, maintained separately) · visual refs in `docs/research/refs/`

---

## 0. How to read this document

Every non-obvious number below is labelled with how it was established:

| Label | Meaning |
|---|---|
| **[MEASURED]** | Captured/queried directly on this machine: macOS **27.0.1** (build **26A434**), Xcode **27.1** (27A9275), Swift **6.4**, SDK **macOS 27.0**, 1470×956 pt display @2×. Capture/analysis scripts live in `docs/research/measure/`; refs in `docs/research/refs/`. |
| **[CITED]** | Stated in an Apple or press source; URL given inline. |
| **[INFERRED]** | My design judgement / extrapolation. Not measured, not stated by Apple. Treat as a recommendation to validate. |

Method summary (details in Appendix A): window-id `screencapture` of standard system apps + purpose-built local SwiftUI/AppKit probes compiled against the macOS 27 SDK; pixel analysis with numpy/Pillow (alpha-mask radius fitting, per-pixel colour sampling); AppKit/SwiftUI introspection for fonts, semantic colours, control fitting sizes, window-chrome heights; frame-sampled animation timing via an `Animatable` modifier. No audio was played, no system settings were changed, no personal documents were captured (the one capture that exposed an account name was redacted; personal folder listings were discarded).

**The single most important finding:** macOS 27 is not "more Liquid Glass" — it is **measurably more restrained and more uniform** than macOS 26 Tahoe. The radius gets tighter (16 pt), the glass gets more diffused and more opaque, sidebars go edge-to-edge, toolbars unify, and coloured icons return. A UI that was beautiful in 2023/2024 (custom translucent panels, floating inset sidebars, 20+ pt corner radii, 0.2 s eases everywhere) now reads as "old macOS". Sections 1–3 give the replacement system; §4 maps it onto PureListen; §5 is the checklist.

---

## 1. Evidence: what actually changed in macOS 27

### 1.1 Apple's own description

> "Updates to Liquid Glass ensure exceptional readability with more uniform refraction and improved contrast. Uniform toolbars, edge-to-edge sidebars, and updated window shapes and menu bar icons deliver a more refined design. And a new slider lets you easily customize how Liquid Glass looks, from ultra-clear to fully tinted."
> — Apple, quoted in MacRumors' launch coverage ([MacRumors, 2026-06-08](https://www.macrumors.com/2026/06/08/apple-announces-macos-golden-gate/)) and repeated verbatim by [9to5Mac](https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/)

Apple's macOS 27 release-notes page describes the same change as "Even more refined design": *"Updates to Liquid Glass improve readability, and a new slider lets you customize how it looks, from ultra-clear to fully tinted. Uniform toolbars, edge-to-edge sidebars, and more detailed app icons further elevate the design."* ([Apple Support 127257](https://support.apple.com/en-us/127257))

From WWDC26 sessions:

- **What's new in SwiftUI** (session [269](https://developer.apple.com/videos/play/wwdc2026/269/)): *"Apps automatically adopt the updated Liquid Glass appearance on 2027 OS releases without code changes"*, covering "refreshed Liquid Glass look and feel", "interactive Liquid Glass elements", toolbar overflow/pinned placements, and minimise-on-scroll.
- **Modernize your AppKit app** (session [289](https://developer.apple.com/videos/play/wwdc2026/289/), chapter "Design updates", 14:09): *"Liquid Glass continues to evolve in macOS 27… Sidebars, scroll edge effects, and toolbar items all receive refinements, and a new interactive glass effect gives controls a physical sense of response when clicked."* The same chapter introduces **concentricity**: `NSViewCornerConfiguration` + `.containerConcentric` "lets views near a container's corners automatically match the container's corner radius".
- **Platforms State of the Union** (session [102](https://developer.apple.com/videos/play/wwdc2026/102/)): the Liquid Glass opt-out is gone — recompiling with Xcode 27 applies the new design automatically; the compatibility flag no longer has effect (see §1.3).
- **Principles of great design** (session [250](https://developer.apple.com/videos/play/wwdc2026/250/)): Craft = "uncompromising attention to detail… beautiful typography, responsive animations, solid performance". Useful framing for the redesign: the goal is *craft*, not decoration.

### 1.2 The five concrete design deltas (and why they matter)

| # | Delta | What changed vs. macOS 26 Tahoe | Evidence |
|---|---|---|---|
| 1 | **Global Liquid Glass slider** | New continuous slider in **System Settings ▸ Appearance ▸ Liquid Glass**. Defaults to the **middle** of the track. "ultra-clear → fully tinted"; can’t go fully opaque. Users may set it anywhere, so your UI must be legible at *both* ends. | [Apple Support 127257](https://support.apple.com/en-us/127257); [The Verge hands-on](https://www.theverge.com/tech/946567/apple-macos-27-golden-gate-dev-beta-hands-on) ("Golden Gate starts you in the middle of the slider by default"); [MacRumors](https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/); **[MEASURED]** slider knob at ≈52 % of track in the default state (§3.5, ref [06-settings-liquid-glass-section.png](refs/06-settings-liquid-glass-section.png)) |
| 2 | **Glass is more diffused, more contrast** | "more uniform refraction and improved contrast"; darker edge + brighter specular highlights; complex content behind glass is diffused harder. | Apple quote §1.1; [MacRumors "All the Liquid Glass Changes"](https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/) ("now diffuses complex content more effectively… a darkened edge and brighter specular highlights establish more depth and separation"); **[MEASURED]** transmission & rim numbers in §3.5 |
| 3 | **Uniform, tighter window shape** | Every standard window now shares **one** radius, and it is *less* rounded than Tahoe. Apps don't opt in; the system enforces it. | [9to5Mac](https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/) ("Apps no longer need to be updated… to have the same corner radius"); [MacRumors](https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/); **[MEASURED] 16 pt for Finder / System Settings / Preview** (identical alpha profiles, §3.1) |
| 4 | **Edge-to-edge sidebars, uniform toolbars, coloured sidebar icons back** | Sidebars are flush to the window edge again (no floating inset card); toolbars are unified with grouped glass pills and a clear separation line; sidebar icons regain colour; fewer menu-item icons; menu-bar (status) icons redrawn. | Apple quote; [9to5Mac](https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/); [MacRumors](https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/); [iThome hands-on](https://m.ithome.com/html/962168.htm); **[MEASURED]** toolbar pill 36 pt tall, sidebar flush to window edge (refs 03/04/08) |
| 5 | **HDR-flavoured system UI** | Apple uses HDR "for depth and dimension" in the Golden Gate interface (specular highlights can exceed SDR white on HDR displays). | [MacRumors](https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/) — **[INFERRED]** implementation impact, see §3.4 |

Two more press-confirmed refinements worth designing for: **"improved legibility across toolbar controls"** and **"more prominent active-window distinction"** (via sidebar design, opacity and window-shadow changes) — [9to5Mac](https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/), [MacRumors](https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/), [iThome](https://m.ithome.com/html/962168.htm).

### 1.3 What did *not* change (and traps)

- **You can no longer opt out.** `UIDesignRequiresCompatibility` is **ignored** when you build against macOS 27+ SDK: "The system ignores this key when you build for iOS 27 or later, iPadOS 27 or later, Mac Catalyst 27 or later, macOS 27 or later, or tvOS 27 or later." ([Apple docs: UIDesignRequiresCompatibility](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility)) → rebuilding PureListen with Xcode 27 will restyle it whether you plan for it or not; that is an argument to *design* the new look rather than inherit an accidental one.
- **Liquid Glass is still a functional layer, not a content style.** "Don't use Liquid Glass in the content layer. … Use standard materials for elements in the content layer." ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)) — a common failure mode in "glass everything" redesigns.
- **No Dynamic Type on macOS.** macOS has a fixed type ramp (still true in 27); use the system text styles for hierarchy, not user-scalable sizes. ([HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography): "macOS doesn't support Dynamic Type.")
- **The old menu-bar height guidance is stale.** HIG still says "The menu bar's height is 24 pt" ([HIG: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)), but on macOS 27 the menu bar is **[MEASURED] 33 pt** (WindowServer "Menubar" window = 1470×33 pt; `NSScreen.visibleFrame` inset = 33 pt). Design status items against 33 pt and don't hard-code 24.
- **"Fewer menu bar icons" ≠ fewer status items.** It refers to menu-item iconography inside menus ("more effective use of fewer icons in menus"). Your status item still needs to earn its place in a crowded 33 pt strip; HIG warns the system hides extras when space is tight ([HIG: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)).

---

## 2. Golden Gate signature moves — what makes an app read as macOS 27, not 2023

These are the ten moves that, together, make a screenshot instantly datable. Each has an implementation recipe.

| # | Signature move | Why it reads 2027 | Implementation recipe |
|---|---|---|---|
| **1** | **One uniform 16 pt radius, concentric children** | Tahoe's oversized/comic corners are gone; system windows are visibly tighter and *all the same*. Inner radii must share a common centre with the container corner, or the panel looks pasted on. | Window/panel: 16 pt. Nested surfaces: `r_inner = r_outer − inset`, or use `ConcentricRectangle` / `.containerShape(...)` / AppKit `.containerConcentric`. Never mix 8/12/20 radii in one panel. §3.1 |
| **2** | **Glass floats, content stays matte** | In 27 the "glass layer" is chrome (toolbar, sidebar, HUD controls, popover panel) and the content beneath is quiet and opaque. Glass-on-glass is the Tell-Tale Tahoe. | Glass only on: popover shell, floating control clusters, transient HUD, toolbars/sidebars. Track list, album-art background, lyric sheet = standard materials or solid fills. §3.5 |
| **3** | **Edge-to-edge chrome, no floating sidebar card** | Sidebars that float inset with their own shadow were the most-criticised Tahoe motif; macOS 27 returns to flush edge-to-edge with a hairline separation. | If you build a window: `NavigationSplitView`/`NSSplitViewController` with sidebar flush; no rounded inset, no outer shadow. Add a 1 px separator or scroll-edge effect instead. §4.3 |
| **4** | **Toolbar = grouped glass pills with 36 pt controls** | Unified toolbar with grouped, capsule-ish glass clusters (nav / title / view options / actions / search) and 36 pt control height is the most recognisable Golden Gate silhouette. | Standard `.toolbar` + `ToolbarItemGroup`s; if custom: capsule glass groups, 36 pt height, 8–10 pt gaps inside a group, 16–20 pt between groups. §3.2, refs 03/13 |
| **5** | **Diffused glass with a dark rim and a 1 pt specular top edge** | The measured look: regular glass compresses backdrop contrast into an appearance-dependent band, with a *darker* 1 pt edge and a brighter 1 pt inner highlight on the lit side. Flat 50 % blur panels read as 2023 frosted plastic. | Use `.glassEffect(.regular, in:)` / `NSGlassEffectView`; do **not** hand-roll blur+white 0.1 overlay. If you must hand-roll a highlight: inner stroke 1 pt, top/leading lighter, bottom/trailing darker. §3.5 |
| **6** | **Compact type, generous hit targets** | 13 pt body / 11 pt secondary is unchanged, but control heights step 20/24/28/36 pt and paddings grow; small 10 pt text is reserved for tertiary metadata. | Use the measured type ramp (§3.3) and control heights (§3.2). Minimum 44×44 pt hit region for anything that matters. |
| **7** | **Colour is an accent, not a surface** | Golden Gate surfaces are neutral; colour appears as accent tint, tinted glass, or the (returned) coloured sidebar icons. Coloured cards/headers scream 2020. | Neutral backgrounds; one accent per view; tinted glass only for the primary action; album-art wash ≤ 25–35 % opacity over a neutral base (§3.4). |
| **8** | **Slower, softer motion** | System motion in 26/27 is spring-based and *settles later* than the old 0.2–0.35 s eases: measured `.smooth` settling ≈ 0.75 s, `.snappy` ≈ 0.66 s, `.bouncy` ≈ 0.75 s (320 pt move, 60 Hz). Old `.easeInOut` (0.35 s) now feels clipped. | Animate structural changes with `.smooth`/`.snappy`; use `.interactiveSpring()` (measured 0.15 s) for press/hover; never `.linear` for UI. §3.6 |
| **9** | **Scroll-edge elegies, not header bars** | Content scrolls under a soft/hard edge fade rather than a solid header strip; separators appear only when content passes beneath. | `.scrollEdgeEffectStyle(.automatic/.soft/.hard, for: .top)` on custom scroll containers; system bars do it automatically. §3.5 |
| **10** | **Fewer, larger, better-weighted symbols** | SF Symbols at text weight, hierarchical rendering, restrained effects; 16–17 pt status-item glyphs; menu items icon-light. | `Image(systemName:).font(.system(size: 13–17, weight: .regular/.medium))`, `.symbolRenderingMode(.hierarchical)`; menu-bar icon at 16–17 pt template. §3.7 |
| **11** | **Legibility is a feature** | macOS 27's whole story is "readability + uniformity"; any text over glass must hit ≥ 4.5:1 at the slider's clear end. | Test with slider min/max, Reduce Transparency, Increase Contrast. Add a dimming layer under clear glass over bright art (HIG recommends 35 % black). §3.5 |

---

## 3. Design tokens

### 3.1 Corner radius system

#### Measured reality

| Element | Radius | How measured |
|---|---|---|
| **Standard window** (Finder, System Settings, Preview) | **16 pt** (fit 32.25 px @2×) | Alpha-mask corner fit on three different apps; identical profiles ⇒ uniform system shape. Ref [10-window-corner-radius-annotated.png](refs/10-window-corner-radius-annotated.png) |
| **NSPopover panel** | **≈ 19–20 pt** (circle fit 38.5 px @2× = 19.25 pt; use 20 pt) | 360×560 content popover captured over desktop, panel boundary fit. Ref [09-popover-360x560-panel.png](refs/09-popover-360x560-panel.png) |
| **Menu (NSMenu)** | **≈ 16 pt** (fit 31.75 px = 15.9 pt) | Probe menu over a known backdrop. Ref [14-menu-liquid-glass.png](refs/14-menu-liquid-glass.png) |
| **Bordered control (24 pt tall)** | **≈ 6–7 pt effective** (top-edge inset 8 px @2× ⇒ continuous-corner radius ~6 pt) | Blue `.borderedProminent` button in control gallery. Ref [13-controls-gallery-dark.png](refs/13-controls-gallery-dark.png) |
| **Capsule controls** (pills, segmented, status chips) | fully rounded (h/2) | macOS 27 toolbar pills, sliders, search field. Ref `06`, `03` |
| **Menu bar extra/status item** | n/a (template glyph) | — |

> **Apple's rule:** "Standard buttons, text fields, headers and footers have corner radii that are concentric with bar corners" — [HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars). And since macOS 27 the window shape is system-enforced, so *do not* paint your own window radius; only interior surfaces need concentric math.

#### The radius scale to use in PureListen **[INFERRED, anchored on measurements]**

| Token | Value | Use |
|---|---|---|
| `radius.window` | **16 pt** | Window / panel outer shape (system-drawn; never override) |
| `radius.popover` | **20 pt** | NSPopover panel (system-drawn for NSPopover; use 20 if you draw your own panel) |
| `radius.card` | **12 pt** | Grouped cards, album-art container, settings cards |
| `radius.control` | **7 pt** | 24 pt bordered buttons/fields; step to 8 pt at 28 pt, 9 pt at 36 pt |
| `radius.row` | **8–10 pt** | Selectable list/sidebar rows (capsule when height ≥ 28 pt) |
| `radius.chip` | h/2 (capsule) | Status chips, pills, "无损"/"SQ" badges, segmented controls |
| `radius.sheet` | **20 pt** | Sheets (Apple: "Sheets feature an increased corner radius" — [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)) |

#### Concentric formula (the rule that makes nesting look native)

```
r_inner = clamp(r_outer − inset, minInner, ∞)     // inset = gap between the two shapes
```

Examples: a 12 pt card inset 8 pt inside a 20 pt popover → inner radius 12 pt. A 24 pt button padded 6 pt inside a 12 pt card → 6 pt. If the result would be ≤ 0, the child corner should be **square** (don't fake it with 2 pt).

SwiftUI (macOS 26+; verified to type-check against SDK 27):

```swift
// 1) Let the system solve concentricity from the container shape
RoundedRectangle(cornerRadius: 12, style: .continuous)
    .fill(.background)
    .containerShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

// 2) Or use ConcentricRectangle directly (corners resolve against the container shape)
ConcentricRectangle()                                    // all corners concentric
ConcentricRectangle(corners: .concentric(minimum: 8))     // concentric, min 8 pt
ConcentricRectangle(uniformTopCorners: .fixed(12), uniformBottomCorners: .concentric)

// 3) In a bar whose corner radius you don't own, prefer a corner style that follows the container
.padding(8)
.background(.regularMaterial, in: .rect(cornerRadius: 16))
```

Notes established by compiling against the macOS 27 SDK:
- `ConcentricRectangle` **does not** conform to `RoundedRectangularShape`, so `.containerShape(ConcentricRectangle())` does *not* compile; use `RoundedRectangle`/`Capsule` for `containerShape`, then `ConcentricRectangle` inside it, or set the container shape from a real rounded rect.
- `ConcentricRectangle` + `RectangleCornerRadii` are macOS 26+; `NSViewCornerConfiguration` is macOS 27+.

AppKit (macOS 27+): override `cornerConfiguration` (it is a *get-only* property — set it by subclassing, per the WWDC 289 sample):

```swift
final class CardView: NSView {
    override var cornerConfiguration: NSViewCornerConfiguration? {
        get { .uniformCorners(radius: .containerConcentric(12)) }   // adapts to container
    }
}
// fixed radius:  .corners(radius: .fixed(12)) / .uniformCorners(radius: .fixed(12))
// capsule:       .capsule   or   .capsule(maximumRadius: 40)
```
API: `NSViewCornerRadius.fixed(_:)`, `.containerConcentric(_:)`, `.containerConcentric` ([NSViewCornerRadius.h in SDK 27](https://developer.apple.com/documentation/appkit/nsviewcornerconfiguration)).

**Do / don't**
- ✅ Use the *same* radius family per surface hierarchy; express hierarchy with size/padding, not radius jumps.
- ✅ Use `.continuous` corner style for anything ≥ 10 pt (macOS windows are continuous corners).
- ❌ Don't use 20–28 pt radii on cards inside a 360 pt popover — at that width they read as Tahoe "bubble UI".
- ❌ Don't put a 16 pt icon tile with a 4 pt radius inside a 16 pt card; either match the family or square the tile.

### 3.2 Layout, spacing, metrics

#### The grid

- **4 pt base grid.** All paddings, gaps and control heights in this document are multiples of 4 (the few 5/6 pt values are optical corrections around 13 pt text). **[INFERRED, conventional]**
- **8 pt is the working unit** for gaps inside a group; **12–16 pt** between groups; **16 pt** outer padding for a 360 pt-wide popover; **20 pt** for full windows.
- **Vertical rhythm:** 24 pt control row; SwiftUI `List` default row = **[MEASURED] 24 pt** with 13 pt text + symbol; music/track rows look better at 28 pt (room for two lines/waveform); 44 pt minimum hit target for primary actions.

#### Measured control heights (SwiftUI `.fittingSize`, macOS 27) **[MEASURED]**

| Control | small | **regular** | large | extraLarge |
|---|---|---|---|---|
| `Button` `.borderedProminent` / `.bordered` / `.glass` / `.glassProminent` | 20 pt | **24 pt** | 28 pt | 36 pt |
| icon-only prominent button | — | 36×21 pt | — | — |
| `Toggle` `.switch` | 20 | **24** | 28 | 36 |
| `Toggle` `.checkbox` | — | 17 | — | — |
| `TextField` `.roundedBorder` | — | **24** | 24 | — |
| `Picker` `.segmented` | — | **24** | — | — |
| `Picker` `.menu` | — | **24** | — | — |
| `Slider` | 14 | **16** | — | — |
| `ProgressView` linear | — | **20** | — | — |
| `ProgressView` circular | — | 32×32 | — | — |
| `Stepper` | — | **24** | — | — |
| `NSButton` `.rounded` (AppKit) | 20 | **24** | 28 (mini 16) | — |

Text sizes for reference: body `.fittingSize` height = 16 pt; `.caption2` = 13 pt; `.title3.semibold` = 19 pt. SF Symbol glyph boxes at font 13/17/26 pt = 12×13 / 15×16 / 23×26 pt.

**Recommended heights for PureListen:** play/pause cluster 36 pt circles (extraLarge tap area inside a 44 pt hit region via `.contentShape`), secondary transport 24–28 pt, settings rows 32 pt, list rows 28 pt, chips 20 pt, time labels 13 pt line box.

#### Window / chrome metrics **[MEASURED]**

| Element | Value | How |
|---|---|---|
| Plain titled window chrome | **32 pt** (frame 332 for 400×300 content) | NSWindow probe |
| Unified toolbar chrome (`NSToolbar` + `.fullSizeContentView`, `.unified`) | **52 pt** (`NSTitlebarContainerView` height = 52 pt; `contentLayoutRect.height` = window height − 52) | NSWindow probe |
| Other toolbar styles (offscreen probe, no items) | `.unifiedCompact` ≈ 40 pt, `.expanded` ≈ 48–88 pt (unreliable offscreen) | **use `.unified` and measure visually** |
| Menu bar | **33 pt** tall (WindowServer Menubar 1470×33 pt; visibleFrame top inset 33) | [MEASURED] |
| Traffic lights | ~12–13.5 pt diameter, **23 pt pitch**, first centre ≈ 25.75 pt from left / 25.75 pt from top | Finder capture |
| Finder toolbar control pill | **36 pt tall**, e.g. nav pill 71×35.5 pt | Finder capture |
| System Settings sidebar | **252 pt** wide in a 740 pt window | Settings capture |
| Slider (Settings, Liquid Glass) | track **6 pt**, knob **20 pt**, active fill #397BF7 (P3-rendered system blue), inactive #464646 | Settings capture |
| Status item glyphs | third-party **17×17 pt** and 15×14 pt; system glyph/text ~12–13.5 pt tall; all centred in the 33 pt bar | menu-bar capture |
| Popover content vs window | `_NSPopoverWindow` = content + **13 pt** ring on all sides (360×560 content → 386×586 window) | NSPopover probe |

#### PureListen 360×560 popover blueprint **[INFERRED]**

```
┌──────────────────────────────────────────────┐  ← NSPopover panel, system glass, 20 pt radius
│  16 pt top padding                           │
│  [icon 28] 净听 · 正在播放      [gear 24]   │  44 pt header strip (13 pt semibold title)
│  12 pt gap                                   │
│  ┌────────────────────────────────────────┐  │
│  │ album art 328×328, radius 12, shadow   │  │  ← content layer (no glass)
│  └────────────────────────────────────────┘  │
│  14 pt gap                                   │
│  夜曲             ← title3 15 pt semibold    │
│  周杰伦 · 十一月的萧邦 ← subheadline 11 pt secondary
│  ┌────────────────────────────────────────┐  │
│  │ progress 8 pt track, 12 pt knob        │  │  8 pt vertical padding
│  └────────────────────────────────────────┘  │
│  01:23                      03:45  ← caption2 10 pt monospacedDigit
│  16 pt gap                                   │
│  [  ⏮   ▶   ⏭  ]  ← 36 pt glass capsule     │
│  [ 无损独占 · 44.1 kHz ]  ← 20 pt capsule chip
│  16 pt bottom padding                        │
└──────────────────────────────────────────────┘
```
- Outer horizontal padding **16 pt** (content width 328 pt), vertical 16 pt top / 16 pt bottom.
- Default popover panel is system-drawn: **don't add your own `NSVisualEffectView`** background — Apple explicitly says to audit popovers and "remove those custom background views" ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)). If content needs a tinted wash, put it *inside* with low opacity.
- List of tracks (when shown) uses **28 pt rows**, 12 pt horizontal inset, selection = capsule 10 pt radius, no alternating row colours.

#### Spacing tokens (use these names in code)

| Token | Value | Typical use |
|---|---|---|
| `space.2` | 2 | optical nudge only |
| `space.4` | 4 | icon-to-label, badge inset |
| `space.8` | 8 | inside a control group; card inner padding (edges) |
| `space.12` | 12 | card padding, section gap inside a card |
| `space.16` | 16 | popover outer padding; gap between groups |
| `space.20` | 20 | window content padding |
| `space.24` | 24 | major section break |
| `space.32` | 32 | empty-state breathing room |

### 3.3 Typography

macOS has **one fixed type ramp** (no Dynamic Type). The table below is read directly from `NSFont.preferredFont(forTextStyle:)` on macOS 27 and matches the HIG specification table exactly — use it as ground truth. **[MEASURED, corroborated by [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)]**

| Text style | SwiftUI | Weight | Size | Line height | Ascender | Cap height | Emphasised weight |
|---|---|---|---|---|---|---|---|
| Large Title | `.largeTitle` | Regular | 26 pt | 32 | 25.14 | 18.32 | Bold |
| Title 1 | `.title` | Regular | 22 pt | 26 | 21.27 | 15.50 | Bold |
| Title 2 | `.title2` | Regular | 17 pt | 22 | 16.44 | 11.98 | Bold |
| Title 3 | `.title3` | Regular | 15 pt | 20 | 14.50 | 10.57 | Semibold |
| Headline | `.headline` | **Bold** | 13 pt | 16 | 12.57 | 9.16 | Heavy |
| Body | `.body` | Regular | 13 pt | 16 | 12.57 | 9.16 | Semibold |
| Callout | `.callout` | Regular | 12 pt | 15 | 11.60 | 8.46 | Semibold |
| Subheadline | `.subheadline` | Regular | 11 pt | 14 | 10.63 | 7.75 | Semibold |
| Footnote | `.footnote` | Regular | 10 pt | 13 | 9.67 | 7.05 | Semibold |
| Caption 1 | `.caption` | Regular | 10 pt | 13 | 9.67 | 7.05 | Medium |
| Caption 2 | `.caption2` | **Medium** | 10 pt | 13 | 9.67 | 7.05 | Semibold |

Rules:
- **13 pt body is the Mac default**; 11 pt is the smallest sensible secondary text; 10 pt is the floor ("minimum 10 pt" per HIG). For PureListen Chinese UI, 10 pt Caption 2 should be used only for units/metadata, never for song titles.
- **Line height is baked into the text style.** Don't apply extra `.lineSpacing` unless you're setting custom sizes; for multi-line lyrics use `.lineSpacing(4)` and `.font(.body)`.
- **Tabular digits for anything that ticks.** Time labels must use `.monospacedDigit()` (SF Pro has tabular figures; `NSFont.monospacedDigitSystemFont` keeps `.SFNS-Regular` but with fixed-width digits — **[MEASURED]** it reports `isFixedPitch == false`, which is normal: only digits are fixed). For a clock look, `.fontDesign(.monospaced)` (SF Mono) is acceptable for a *dedicated* counter but not for labels (`monospacedSystemFont` → `.AppleSystemUIFontMonospaced-Regular`).
- **Tracking follows size** on macOS (variable font does it automatically). If you hand-set sizes, use the HIG macOS tracking table; key values: 10 pt → +0.12 pt, 11 pt → +0.06 pt, 12 pt → 0, 13 pt → −0.08 pt, 15 pt → −0.23 pt, 17 pt → −0.43 pt, 22 pt → −0.26 pt, 26 pt → +0.22 pt. In SwiftUI prefer `.tracking(...)` only for large custom display text; system text styles already track correctly.
- **Weight budget:** Regular / Medium / Semibold / Bold only; avoid Light/Thin (HIG: "avoid Ultralight, Thin, Light"). Headline-style emphasis on Mac is usually **semibold, not bold**, in custom layouts; `.headline` is bold by definition.
- **What did *not* change in 27's type ramp:** the measured macOS 27 ramp is identical to the long-standing macOS table (26/22/17/15/13/12/11/10 pt). The recent typography deltas are (a) HIG's Dec-2025 addition of *emphasised weights* per style (e.g. body→semibold, title3→semibold) which matches what `NSFont.preferredFont(forTextStyle:)` returns when bolded, and (b) the 26-era system-wide switch of list/form section headers to **title case** (no ALL-CAPS) — [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography) change log; [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass). No new font family ships for macOS 27 UI.
- **Chinese (and mixed CJK) specifics** **[INFERRED, typography practice + measured font fallback]**:
  - System text styles automatically fall back to **PingFang SC** (the mac default Chinese UI face). Do not set a custom Chinese font unless you ship one.
  - CJK glyphs sit optically larger than Latin at the same point size; when mixing "净听 · Now Playing", the Chinese will look ~1 pt bigger. Keep Chinese at the same size (don't downsize) but give Latin labels one step of hierarchy *by weight or colour*, not by size.
  - CJK tracking: keep tracking at system default (0); negative tracking looks cramped in Chinese.
  - Chinese doesn't have lowercase; avoid `.textCase(.uppercase)` on mixed strings.
  - For the popover: song title `.title3.weight(.semibold)` (15 pt), artist `.subheadline` (11 pt secondary), section headers `.headline` (13 bold) or 11 pt semibold secondary — Apple's Golden Gate lists favour 13 bold headers over 11 pt caps-style headers (and since 26, "section headers no longer render entirely in capital letters" — [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)).
- **Do not use rounded design** for the interface (`.rounded`): HIG reserves SF Pro Rounded for "soft/rounded UI elements"; a music app can use it for a single hero number, not for the UI. **[INFERRED]**

Code recipes:

```swift
Text("夜曲").font(.title3.weight(.semibold)).lineLimit(1)
Text("周杰伦 · 十一月的萧邦").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
Text("01:23").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
Text("44.1 kHz / 16 bit").font(.caption2).foregroundStyle(.tertiary)
Text("无损独占").font(.system(size: 10, weight: .semibold)).textCase(nil)   // chip label
```

### 3.4 Colour

#### Semantic colours, measured on macOS 27 **[MEASURED]**

`NSColor` resolved through sRGB in `.aqua` / `.darkAqua`. Values with `a=` are the semantic colour's own alpha; the "effective" column composites it over `windowBackgroundColor` (#FFFFFF light / #1E1E1E dark) — use effective values when you need a concrete hex for design review or non-vibrancy contexts.

| Semantic colour | Light (sRGB) | Dark (sRGB) | Effective on window bg (light / dark) |
|---|---|---|---|
| `labelColor` | #000000 a=0.847 | #FFFFFF a=0.847 | #272727 / #DDDDDD |
| `secondaryLabelColor` | #000000 a=0.498 | #FFFFFF a=0.549 | #808080 / #9A9A9A |
| `tertiaryLabelColor` | #000000 a=0.259 | #FFFFFF a=0.247 | #BDBDBD / #565656 |
| `quaternaryLabelColor` | #000000 a=0.098 | #FFFFFF a=0.098 | #E6E6E6 / #343434 |
| `placeholderTextColor` | #000000 a=0.498 | #FFFFFF a=0.549 | #808080 / #9A9A9A |
| `separatorColor` | #000000 a=0.098 | #FFFFFF a=0.098 | #E6E6E6 / #343434 |
| `gridColor` | #E6E6E6 | #1A1A1A | — |
| `windowBackgroundColor` | #FFFFFF | #1E1E1E | — |
| `controlBackgroundColor` | #FFFFFF | #1E1E1E | — |
| `underPageBackgroundColor` | #F6F6F6 | #282828 | — |
| `textBackgroundColor` | #FFFFFF | #1E1E1E | — |
| `controlColor` (control surface) | #FFFFFF | #FFFFFF a=0.247 | — |
| `controlAccentColor` | #007AFF | #007AFF | (user's accent = default blue) |
| `selectedContentBackgroundColor` | #0064E1 | #0059D1 | selection fill |
| `unemphasizedSelectedContentBackgroundColor` | #DCDCDC | #464646 | inactive selection |
| `selectedTextBackgroundColor` | #B3D7FF | #3F638B | text selection |
| `keyboardFocusIndicatorColor` | #0067F4 a=0.498 | #1AA9FF a=0.498 | focus ring |
| `linkColor` | #0068DA | #419CFF | — |
| `windowFrameTextColor` | #000000 a=0.847 | #FFFFFF a=0.847 | titlebar text |

**System palette (SwiftUI `Color.blue` etc.), measured:**

| Colour | Light | Dark | | Colour | Light | Dark |
|---|---|---|---|---|---|---|
| red | #FF383C | #FF4245 | | purple | #CB30E0 | #DB34F2 |
| orange | #FF8D28 | #FF9230 | | pink | #FF2D55 | #FF375F |
| yellow | #FFCC00 | #FFD600 | | teal | #00C3D0 | #00D2E0 |
| green | #34C759 | #30D158 | | indigo | #6155F5 | #6D7CFF |
| blue | #0088FF | #0091FF | | mint | #00C8B3 | #00DAC3 |
| gray | #8E8E93 | #98989D | | cyan | #00C0E8 | #3CD3FE |
| brown | #AC7F5E | #B78A66 | | | | |

Notes:
- **`Color.blue` ≠ accent colour.** The accent (`controlAccentColor`) is #007AFF; SwiftUI's `.blue` is #0088FF (light) / #0091FF (dark). Use **`.tint(.accentColor)` or the semantic `Color.accentColor`** for interactive emphasis, `Color.blue` only for illustrative content.
- **Label colours are translucent by design** so vibrancy can pull them toward the backdrop. Never hard-code `#DDDDDD` on glass; use `Color.primary/.secondary/.tertiary`.
- **Colour rules from HIG:** reserve colour for meaning; no same colour for different meanings; test light/dark/increase-contrast; use system colours on vibrant surfaces; coloured Liquid Glass only for the single most important action. ([HIG Color](https://developer.apple.com/design/human-interface-guidelines/color))
- **Liquid Glass colour model:** glass is colourless by default and takes colour from content behind it; `.tint(...)` stains it like stained glass and is how the system styles prominent buttons. Don't tint more than one control per view. ([HIG Color ▸ Liquid Glass color](https://developer.apple.com/design/human-interface-guidelines/color); [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views))

#### Album-art tinting (Apple Music now-playing style) — recipe

The Music app's immersive now-playing look is a *content-layer* treatment: a heavily blurred, desaturated version of the artwork behind neutral chrome, not a tinted window. Measured behaviour of glass (below) means the wash must stay under the glass, not in it. **[INFERRED recipe, consistent with HIG "colour passes through materials" guidance]**

```swift
// 1. Extract a dominant colour from the artwork (CIQRCodeGenerator-style simple approach)
func dominantColor(of image: NSImage) -> Color { /* CIKMeans/area-average → NSColor */ }

// 2. Build a low-chroma, dual-stop wash (NOT a single flat tint)
let wash = LinearGradient(
    colors: [dominant.opacity(0.30), dominant.opacity(0.12), Color.clear],
    startPoint: .top, endPoint: .center)

// 3. Put it in the CONTENT layer over a neutral base; chrome stays neutral
ZStack {
    Rectangle().fill(.background)      // neutral base = legibility floor
    wash                                // ≤ 0.30 peak; hue-shift toward the cover only
    content
}

// 4. Optional native-feeling extra: mirror the artwork itself, blurred, under the chrome
Image(nsImage: cover).resizable().scaledToFill()
    .blur(radius: 40).saturation(1.4).opacity(0.25)
```

Limits that keep it tasteful (and native):
- **Peak tint opacity 25–35 %**; never tint text or controls (use `.primary`/`.secondary`).
- **Clamp saturation** (~1.0–1.4× of source, not 2×) and clamp lightness to the range of the appearance; very saturated album art should be desaturated ~30 % before use.
- Apply the wash **only below the glass layer**; if a glass control floats over it, the glass will pick up the colour by itself — that is the native effect.
- Animate tint changes with a **0.4–0.6 s cross-fade** on track change (`.smooth`), never a hard cut.
- Respect **Increase Contrast**: at high contrast, drop the wash to ≤ 15 % and raise the neutral base.

#### HDR

Apple uses HDR "for depth and dimension" in the Golden Gate UI (bright specular highlights can exceed SDR white on HDR displays) — [MacRumors](https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/). **[INFERRED]** For a third-party app: do not hand-roll HDR whites; let system glass and materials produce them. If you use extended-range colours (P3/HDR), keep UI text ≤ SDR white and verify on an SDR display/profile. PureListen should stay with semantic colours; the only place extended range is worth considering is a subtle glow behind the play button on HDR displays — low priority.

### 3.5 Materials & Liquid Glass

#### What Liquid Glass is for

- **Two material families:** Liquid Glass (functional layer: bars, sidebars, popovers, floating controls) and **standard materials** (content layer: `ultraThin/thin/regular/thick`, vibrancy). "Don't use Liquid Glass in the content layer." ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials))
- **Two Glass variants:** `.regular` (blurs + adjusts luminosity for legibility; use for anything with significant text — alerts, sidebars, popovers) and `.clear` (highly translucent; only over rich media; add a dimming layer if the background is bright — Apple recommends **35 % black** when needed). ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials); [Applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views))
- **`.tint(_:)`** stains the glass; reserved for the one prominent action. **`.interactive()`** adds the physical press/pointer response; use it on anything the user clicks. New in macOS 27 for AppKit: `NSGlassEffectView.effectIsInteractive`.
- **`GlassEffectContainer`** is required for multiple glass shapes: it batches rendering and lets shapes merge/morph. Spacing = merge distance; matched-geometry IDs coordinate morphs. ([Applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views); AppKit equivalents `NSGlassEffectContainerView` (macOS 26+) with `contentView`/`spacing`.)

#### Measured optical behaviour (the numbers to design against) **[MEASURED]**

Probe: 220×96 pt glass shapes at 20 pt radius over uniform white (#FFFFFF) and black (#000000) content, captured at 2×; interior sampled in the central 30 %. Values are the *rendered interior colour*.

| Material (dark appearance) | over white | over black |
|---|---|---|
| `Glass.regular` | **#868686** | **#202020** |
| `Glass.clear` | **#FFFFFF** | **#202020** |
| `Glass.regular.tint(.blue)` | **#1497FB** | **#0091FF** |
| `.ultraThinMaterial` | #A9A9A9 | — |
| `.thinMaterial` | #959595 | — |
| `.regularMaterial` | — | #232323 |
| `.thickMaterial` | — | #272727 |

| Material (light appearance) | over white | over black |
|---|---|---|
| `Glass.regular` | **#FEFEFE** | **#868686** |
| `Glass.clear` | **#FFFFFF** | **#202020** |
| `Glass.regular.tint(.blue)` | **#0088FF** | **#006ACF** |
| `.ultraThinMaterial` | #F5F5F5 | — |
| `.thinMaterial` | #F1F1F1 | — |
| `.regularMaterial` | — | #959595 |
| `.thickMaterial` | — | #B1B0B0 |

How to read these:
1. **Regular glass is not a flat 50 % grey layer.** It behaves like an appearance-tinted diffusion: in dark mode it maps a bright backdrop down to #868686 and a black backdrop up to #202020; in light mode a white backdrop stays #FEFEFE and black lifts to #868686. So *glass compresses backdrop contrast into roughly [#202020 … #868686] (dark) / [#868686 … #FEFEFE] (light)*. This is exactly why Apple says v2 "diffuses complex content much more effectively" — busy art turns into a soft mid-tone field, and text stays legible.
2. **Clear glass is genuinely clear**: opaque-white stays white; black gets a slight #202020 floor (its own faint dark tint). Use it only over media, with a dimming layer behind text.
3. **Tinted glass reads as saturated accent, near-opaque**: blue tint renders #0088FF-ish in light mode over white, #006ACF over black; dark mode #1497FB / #0091FF. Treat tinted glass as "primary button fill", not as "slightly blue glass".
4. **Rim & shadow construction (measured on a menu panel, dark mode, interior luminance 70/255):** immediately outside the panel there is a **dark contact line** (luminance 7/255) ~1 px; at the top edge a **bright specular line** (luminance 128 vs interior 70) 1–2 px ≈ 1 pt; the left edge shows a weaker highlight (88). I.e. the recipe is *dark hairline outside, bright hairline inside on the lit edge, interior diffused* — not a uniform white border. You get this for free from `.glassEffect`/`NSGlassEffectView`; only replicate it by hand if you are drawing a custom HUD.

   If you *must* hand-build a glass-like surface (last resort — e.g. an AppKit view that can't adopt `NSGlassEffectView`), the measured structure maps to three layers:

   ```swift
   RoundedRectangle(cornerRadius: 20, style: .continuous)
       .fill(.ultraThinMaterial)                                  // 1. diffused interior
       .overlay(                                                  // 2. inner shadow at the bottom
           RoundedRectangle(cornerRadius: 20, style: .continuous)
               .strokeBorder(.black.opacity(0.18), lineWidth: 1)
               .blur(radius: 1.5)
               .offset(y: 0.5)
       )
       .overlay(                                                  // 3. specular rim on the lit edge
           RoundedRectangle(cornerRadius: 20, style: .continuous)
               .strokeBorder(
                   LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.10), .black.opacity(0.22)],
                                  startPoint: .top, endPoint: .bottom),
                   lineWidth: 1)
       )
       .shadow(color: .black.opacity(0.28), radius: 14, y: 7)      // 4. contact shadow outside
   ```

   The inner darkening is what the measured `regular` glass over black (#202020 instead of #000000) encodes; the gradient border gives the "lighter top, darker bottom" read of the measured rim. Keep the rim **1 pt**, never 2–3 pt (thick rims are the single most common "fake glass" tell).

#### SwiftUI recipes (type-checked against SDK 27)

```swift
// Popover shell: system NSPopover already draws the glass. Do NOT add a background.
// Custom floating cluster inside the popover (play controls):
HStack(spacing: 24) { /* transport buttons */ }
    .padding(.horizontal, 22).padding(.vertical, 10)
    .glassEffect(.regular.interactive(), in: .capsule)   // interactive = press response

// Grouped chips that should merge/morph:
GlassEffectContainer(spacing: 10) {
    HStack(spacing: 10) {
        chip("无损").glassEffect(.regular, in: .capsule).glassEffectID("lossless", in: ns)
        chip("44.1 kHz").glassEffect(.regular, in: .capsule).glassEffectID("rate", in: ns)
    }
}

// Primary action only:
Button("立即播放") { play() }
    .buttonStyle(.glassProminent)     // or .glass for secondary

// Content-layer card (NOT glass):
VStack { /* track rows */ }
    .background(.regularMaterial, in: .rect(cornerRadius: 12))
```

Availability (from SDK 27 interfaces): `Glass`/`.glassEffect`/`GlassEffectContainer`/`.glassEffectID`/`.glassEffectTransition`/`.glassButtonStyle(.glass/.glassProminent)` are **macOS 26+**; `.effectIsInteractive` on AppKit's `NSGlassEffectView` is **macOS 27+**. `ToolbarOverflowMenu` and `.topBarPinnedTrailing` are **not available on macOS** (iOS/iPadOS only) — do not plan them in.

#### Scroll edge effect

When content scrolls under floating chrome, use the scroll-edge effect instead of a solid header:
```swift
ScrollView { content }
    .scrollEdgeEffectStyle(.automatic, for: .top)   // .automatic/.soft/.hard; macOS 26+
```
HIG: "Prefer the automatic scroll edge effect style… only use a scroll edge effect when a scroll view is behind floating interface elements. Scroll edge effects aren't decorative." ([HIG Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views), updated 2026-06-08)

#### Popovers, menus, materials in AppKit

- `NSPopover` draws its own panel (glass in 26/27). PureListen should **not** set a `contentViewController.view` background (no `NSVisualEffectView`). If an opaque content surface is required (album-art screen), inset it from the popover edge by **0** (full bleed) but add **no** extra background view.
- `NSGlassEffectView` (macOS 26+): `style = .regular/.clear`, `cornerRadius`, `tintColor`, `contentView`, and macOS 27's `effectIsInteractive = true`. Use it only when you must host AppKit views in glass.
- Standard materials still exist for the content layer (`NSVisualEffectView`: `.popover`, `.menu`, `.sidebar`, `.windowBackground`, `.underWindowBackground`, …). Prefer `.regularMaterial`/`.thinMaterial` in SwiftUI content.
- **Reduce Transparency**: if the user enables it, glass becomes opaque; design must not depend on translucency for meaning. Detect with `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` or SwiftUI `@Environment(\.accessibilityReduceTransparency)`, and in that mode: replace custom glass with `.regularMaterial`/opaque surface + hairline border, keep text colours unchanged. The Verge notes Reduce Transparency "is like taking a hammer to all that glass — introducing lots of harsh gray and black backgrounds" — so **don't combine custom glass with Reduce Transparency fallbacks that double up**; let the system handle standard chrome. ([The Verge](https://www.theverge.com/tech/946567/apple-macos-27-golden-gate-dev-beta-hands-on); [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials))
- **Liquid Glass slider**: users can set clear↔tinted; `.glassEffect` follows it automatically. Your only job is to verify legibility at both ends and with wallpapers behind the popover.

### 3.6 Motion

#### Measured macOS 27 / SwiftUI timings **[MEASURED]**

Probe: 40×40 pt view animated 320 pt horizontally via `withAnimation`, per-frame samples from an `Animatable` modifier (`CACurrentMediaTime`), 60 Hz display. "Settle" = time until within 0.5 pt of target.

| Animation | Settle time | Overshoot |
|---|---|---|
| `.default` | **0.74 s** | 0 |
| `.linear(duration: 0.25)` | 0.27 s | 0 |
| `.easeInOut` | **0.36 s** | 0 |
| `.easeOut(duration: 0.2)` | 0.21 s | 0 |
| `.smooth` | **0.75 s** | 0 |
| `.smooth(duration: 0.6)` | 0.87 s | 0 |
| `.snappy` | **0.66 s** | +1.4 pt (0.4 %) |
| `.snappy(duration: 0.5)` | 0.67 s | +1.4 pt |
| `.bouncy` | **0.75 s** | +13.4 pt (4.2 %) |
| `.bouncy(duration: 0.6)` | 0.92 s | +13.6 pt |
| `.spring(response: 0.35, dampingFraction: 0.8)` | 0.46 s | +3.5 pt (1.1 %) |
| `.interactiveSpring()` | **0.15 s** | +0.36 pt (0.1 %) |
| AppKit `NSAnimationContext.current.duration` | **0.25 s** default | — |

Implications:
- **The default spring is slow and soft** (0.74 s to full settle for a large move). The old habit of `.easeInOut`/0.25 s for structural changes now reads "snappy but cheap"; system-style UI uses springs with a long tail.
- **`.interactiveSpring()` is the press/hover primitive** (0.15 s) — use it for buttons, hover, knob feedback; it matches the "physical response" Apple added in 27 (`effectIsInteractive`, `.interactive()` glass).
- For **frequent, small** transitions (track selection, tab switch), a 0.25–0.35 s spring is still appropriate — the 0.7 s defaults are for large layout moves and would feel laggy on every click. Use `.spring(response: 0.3, dampingFraction: 0.85)` or `.snappy(duration: 0.3)`.
- Never `.linear`; never animate on scroll-linked parallax in the popover (motion sickness + reduce-motion complexity).

#### Recipes

```swift
// Press / hover feedback on a custom control
.scaleEffect(isPressed ? 0.97 : 1)
.animation(.interactiveSpring(), value: isPressed)

// Selection change / expansion inside the popover
withAnimation(.snappy(duration: 0.3)) { selection = newValue }

// Big structural change (e.g. switching popover pages)
withAnimation(.smooth) { showLyrics.toggle() }

// Glass morph between two states in a container
withAnimation(.smooth) { expanded.toggle() }   // + glassEffectID + glassEffectTransition(.matchedGeometry)

// Track-change tint cross-fade (album art wash)
.animation(.easeOut(duration: 0.45), value: currentCoverID)
```

#### Reduce Motion & accessibility

`@Environment(\.accessibilityReduceMotion)` — when true: replace movement with a 0.15 s opacity cross-fade, disable symbol bounce/pulse loops, and avoid scale transitions > 2 %. ([HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion): "Make motion optional… don't use it as the only way to communicate information.") Glass-specific motion also adapts automatically to the pointer type per HIG.

#### Symbol animations (use as seasoning)

`bounce` on play/pause, `variableColor` (iterative) for an equaliser/now-playing indicator, `pulse` for buffering/connecting, `replace` (Magic Replace default) for play↔pause glyph swap. Don't stack more than one effect per symbol. ([HIG SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols))

### 3.7 Iconography & SF Symbols

- **Library:** macOS 27 ships the current SF Symbols set (the HIG documents gradient rendering and Draw On/Off animations from **SF Symbols 7**, and layered/clear/tinted icon appearances; treat the installed set as "SF Symbols 8-era" — **[INFERRED version number]**, but the *features* below are documented). Use `NSImage(systemSymbolName:)` / `Image(systemName:)`; never ship custom bitmaps for standard actions.
- **Sizes [MEASURED]** (glyph box at font size): 13 pt → 12×13; 17 pt → 15×16; 26 pt → 23×26. Practical ramp:
  - inline with 13 pt text / list rows: **13 pt**
  - secondary toolbar/transport: **15–17 pt**
  - primary transport (play/pause): **20–26 pt**
  - menu-bar status glyph: **16–17 pt**
  - header actions in popover: **13–15 pt**
- **Weight must match adjacent text weight** (symbols are designed to align with SF). Use `.medium`/`.semibold` for emphasis, `.regular` elsewhere.
- **Rendering modes:** monochrome for ordinary controls; **hierarchical** for transport/status glyphs on glass (gives depth); palette/multicolor only when meaning requires (e.g. state colours). HIG: confirm the mode works at small sizes and in every appearance.
- **Scales:** default medium; `.imageScale(.large)` instead of increasing font size when you need emphasis without changing weight matching.
- **Menu bar extras** ([HIG: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)):
  - Use an **SF Symbol as a template** image, black + clear only; the system applies colour for light/dark/selected.
  - Measured status-item glyph sizes: **17×17 pt** and 15×14 pt (third-party), system glyph/text ~12–13.5 pt tall, centred in the 33 pt bar. For PureListen: 16–17 pt `headphones` / `waveform` symbol, `.isTemplate = true`, with `.image(with: NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))`.
  - **macOS 27 API for popover-style extras:** `NSStatusItem.expandedInterfaceDelegate` + `NSStatusItemExpandedInterfaceSession` — replaces ad-hoc target/action toggling and participates in keyboard navigation and menu tracking (per header docs in SDK 27; WWDC26 session 289). This is the correct foundation for PureListen's 360×560 panel.
- **Sidebar icons** (if PureListen ever grows a window): coloured icons are *back* in macOS 27; use accent-tinted symbols by default, fixed colours only when they carry meaning ("VIP yellow") ([HIG Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), updated 2026-06-08).
- **Menus:** macOS 27 uses **fewer** menu-item icons than Tahoe; "use menu item icons sparingly and with purpose… if you can't find one that clearly represents the item, don't display an icon"; icons must be uniform within a group ([HIG Menus](https://developer.apple.com/design/human-interface-guidelines/menus), updated 2026-06-08).
- **App icon:** layered, composed in **Icon Composer**, 1024×1024 square, background layer + foreground layers, default/dark/clear/tinted appearances, no baked-in shadows/highlights/masks ([HIG App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons); [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)). **PureListen needs a new layered icon** — a golden-gate-era headphones/tonearm mark with 2–3 translucent layers; do not reuse the current flat glyph.

---

## 4. PureListen component blueprints

Context from the current codebase (read-only inspection): `AppDelegate` creates an `NSPopover` with `contentSize = 360×560`, `.behavior = .transient`, `NSStatusItem` with the `headphones` SF Symbol, a separate Bilibili login `NSWindow` (520×680), and a `NowPlaying` window using a dominant-cover-colour gradient. The blueprint below keeps the product structure and replaces the visual system.

### 4.1 Menu-bar status item

| Property | Spec |
|---|---|
| Glyph | SF Symbol `headphones` (or a state-aware pair: `headphones` / `waveform`), **template**, 16–17 pt, weight `.regular`–`.medium` |
| Bar height to design against | **33 pt** (measured); glyph box centred, max ~18 pt tall for optical balance |
| Length | `NSStatusItem.variableLength`; no text label (a number in the menu bar competes with system items) |
| Accessibility | `button.image?.accessibilityDescription = "净听"`; `button.setAccessibilityLabel("净听")` |
| Interaction (macOS 27) | Use `NSStatusItem.expandedInterfaceDelegate` + `NSStatusItemExpandedInterfaceSession` instead of a bare target/action. It gives keyboard navigation and menu-tracking dismissal for free (WWDC26 [289](https://developer.apple.com/videos/play/wwdc2026/289/); `NSStatusItem.h` SDK 27). Keep `NSPopover` internally if desired, but drive it from the session callbacks. |
| State | Idle = template glyph; playing = optional `waveform` symbol with **one** subtle symbol effect (`.variableColor.iterative` at low intensity) — no colour in the menu bar (system template rules) |
| Right-click | Context menu with Play/Pause, Next, Output Device, Settings, Quit — menus are 24 pt rows, icons sparse (§3.7) |

```swift
// macOS 27 expanded-interface pattern (shape of the API; see SDK header for exact signatures)
final class StatusController: NSObject, NSStatusItemExpandedInterfaceDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    func install() {
        item.button?.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "净听")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        item.button?.image?.isTemplate = true
        item.expandedInterfaceDelegate = self
    }
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) { showPanel() }
    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) { hidePanel() }
}
```

### 4.2 The 360×560 popover (primary surface)

**Shell**
- `NSPopover(contentSize: 360×560)`, system glass panel radius **≈20 pt**, 13 pt transparent shadow ring — don't paint a background.
- Content top padding **16 pt**; side padding **16 pt** (content width 328 pt); bottom padding **16 pt**.
- If the popover content needs its own surface (e.g. opaque album-art page), use `Rectangle().fill(.background)` — **one** opaque layer, never a stack of translucent ones.

**Header strip (44 pt)**
- Leading: 20 pt status dot or small glyph; title `净听` 13 pt semibold; trailing: settings gear 15 pt (`.secondary`, hover background appears as a capsule on hover **[INFERRED]**).
- Optional center: output-device menu (`Menu` label = "耳机 · 44.1 kHz" in 11 pt secondary) — a menu, not a custom popover.

**Now-playing hero (album art)**
- Art 328×328 pt, **12 pt continuous radius**, single soft shadow (radius 12, y 6, opacity 0.25), no border.
- Artwork is content: no glass, no tint overlay above 0.15 opacity (keeps art accurate).
- On hover, show a 28 pt glass circle "expand" affordance bottom-trailing (`.glassEffect(.regular.interactive(), in: .circle)`).

**Track text block**
- Title `.title3.weight(.semibold)` 15 pt, single line, tail truncation.
- Artist `.subheadline` 11 pt `.secondary`.
- Album/quality line `.caption2` 10 pt `.tertiary` (e.g. "十一月的萧邦 · FLAC 24/96").
- 8 pt between title and artist, 14 pt above the block.

**Progress**
- Slider `.controlSize(.regular)` (16 pt high), 8 pt vertical padding; elapsed/remaining `.caption2.monospacedDigit()` `.secondary`.
- Use a custom track if you need 8 pt thickness; knob 12 pt on hover, 8 pt at rest **[CUSTOM, INFERRED]**; keep 44 pt hit region with `.contentShape`.
- Drag: capture on first mouse-down (`DragGesture(minimumDistance: 0)`), show a 12 pt floating glass bubble with the target time above the knob (`.glassEffect(.regular.interactive(), in: .capsule)`).

**Transport cluster**
- Center play/pause **36 pt** (extraLarge control size / 36 pt glass circle), prev/next 20–24 pt symbols, 28 pt gaps.
- Wrap the group in **one** capsule glass cluster (`.glassEffect(.regular.interactive(), in: .capsule)`), 10 pt vertical padding, 22 pt horizontal padding; **only if** the cluster floats over the album-art wash. If it sits on a plain surface, use `.borderless`/`.glass` buttons without an enclosing panel (double-glass = Tahoe tell).
- Secondary row: repeat / shuffle toggles (13 pt symbols, accent when active), lyrics button (text.quote), output device.

**Footer / navigation**
- A 24 pt segmented control (symbols only) with 3–4 sections: 正在播放 / 歌单 / 设置. 16 pt top margin, 16 pt inset, `.pickerStyle(.segmented)`.
- Optional status chip row: `无损独占` and `44.1 kHz` capsules 20 pt tall, `.regularMaterial` or glass; ≤2 chips.

**States**

| State | Treatment |
|---|---|
| Logged out | Centered QR card on a neutral `.background`; QR on **flat white** surface, 12 pt radius, 16 pt quiet zone; caption 11 pt `.secondary`; primary button `.glassProminent` ("重新扫码"), secondary `.bordered` |
| Loading | `ProgressView()` `.controlSize(.regular)` (32 pt) + 13 pt `.secondary` label; no skeleton shimmer (dated) — a subtle 0.4 opacity pulse is enough |
| No track | 32 pt hierarchical symbol (`music.note`) `.tertiary`; 13 pt "还没有正在播放的歌曲"; 11 pt hint |
| Playing | art + full transport, progress animated with `.interactiveSpring()` feedback |
| Paused | play glyph swaps with `.symbolEffect(.replace)` / `.bounce`; keep title colour unchanged (don't grey text to signal pause) |
| Error | inline banner: 28 pt `exclamationmark.triangle` in accent-warning colour (#FF8D28 measured orange), 13 pt title, 11 pt detail, single `.bordered` retry — not an alert sheet |

**Layout skeleton**

```swift
VStack(spacing: 0) {
    header.padding(.horizontal, 16).frame(height: 44)
    ScrollView {
        VStack(spacing: 14) {
            albumArt                                  // 328×328, r12
            trackTextBlock
            progressBlock
            transportCluster.padding(.top, 4)
            statusChips
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    .scrollEdgeEffectStyle(.soft, for: .top)
    footerTabs.padding(.horizontal, 16).padding(.vertical, 10)
}
.frame(width: 360, height: 560)
```

### 4.3 Now Playing window (if the standalone window stays)

- `NSWindow` with `.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView`, `titlebarAppearsTransparent = true`, `toolbarStyle = .unified`; window radius is system-drawn **16 pt** — do not override.
- Chrome height: **52 pt** (measured for unified toolbar). Toolbar content in 2–3 groups max: leading back/title, center "正在播放", trailing share/more.
- Content: 20 pt outer padding; two-column layout at ≥ 720 pt width (art | lyrics/metadata), single column below.
- Background: neutral `.background` + optional album-art wash ≤ 25 %; no glass panel behind the whole content (window background already is the chrome).
- Keep the app-specific background wash *under* content and *under* any floating controls to preserve the native glass pickup.

### 4.4 Settings

- Presentation: **sheet** (radius 20 pt) or a separate window using grouped form; never a custom-drawn panel.
- Use `Form` + `.formStyle(.grouped)`; macOS 27 forms have larger row heights/padding and increased section radius automatically ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)).
- Rows: 32 pt min; label 13 pt, value/control trailing (switch 24 pt regular, `.menu` picker 24 pt, slider 16 pt). Section headers: title case, 13 pt semibold — **not ALL CAPS**.
- Destructive actions: red (`#FF383C` light / `#FF4245` dark), trailing; confirm with an alert if irreversible.
- Footer explanatory text: `.caption2` 10 pt `.tertiary`, max 2 lines.
- Quality/bitrate selection: a `.segmented` control for 3 options, or a checkable menu for >3.

### 4.5 Menus

- Use system `Menu`/`contextMenu`; menu panel radius measured ≈16 pt, row height ≈24 pt, no custom drawing.
- Icons: only where they add meaning (play/pause/next, output device, settings); uniform within a group; standard selectors give system icons automatically.
- Keyboard shortcuts right-aligned (`⌘P`, `⌘→`), separators between groups, submenu depth ≤ 1.
- Menu-bar extra click opens the panel (not a menu) per PureListen's product model; right-click opens the context menu.

### 4.6 Quality/status chips & counters

- Chip: 20 pt tall capsule; `.caption2` (10 pt) semibold label; padding 8 pt horizontal; colours: neutral (`.regularMaterial`) for state, accent tinted for "正在独占" only.
- Counters: `.caption2.monospacedDigit()`; reserve fixed width (`.frame(minWidth: 34, alignment: .trailing)`) so numbers don't jitter.
- Bit-depth/sample-rate strings: use thin spaces and lowercase units ("44.1 kHz · 16 bit"); never uppercase.

### 4.7 Hover & focus (Mac-specific)

- Every clickable icon/text button gets a **hover background**: capsule `.regularMaterial`/`.quaternary` fill (opacity ~8–12 %) with `.interactiveSpring()` fade; 0.12–0.15 s.
- Keyboard focus ring: system `keyboardFocusIndicatorColor` (#0067F4 a=0.498 light / #1AA9FF a=0.498 dark) — don't invent your own ring.
- Pointer cursor: `.pointerStyle(.link)`/default; do not hide the cursor.

---

## 5. Do / Don't — dated vs. native Golden Gate

| ❌ Reads dated (2023–Tahoe) | ✅ Reads native macOS 27 |
|---|---|
| Custom translucent "frosted" panels with 20–30 pt radii stacked on each other | System glass chrome; **one** radius family; matte content layer |
| Hand-rolled `NSVisualEffectView` behind a popover/window | Let `NSPopover`/glass draw the shell; remove custom background views |
| Floating inset sidebar with big shadow and rounded corners | Edge-to-edge sidebar, flush, hairline separation |
| Main content tinted by album art everywhere | Neutral surfaces; album wash ≤25–35 % under glass; colour as accent |
| 0.2 s `easeInOut` for every change | `.snappy` / `.smooth` springs (0.3–0.75 s), `.interactiveSpring()` for press |
| Small 18–20 pt hit areas, 2 pt hairlines | 24–36 pt controls, 28 pt rows, 44 pt hit regions, 1 pt hairlines |
| ALL CAPS section headers | Title-case headers, hierarchy via weight/colour |
| Custom window corner radius / custom titlebar drawing | System window shape (16 pt), unified toolbar (52 pt) |
| Icon on every menu item | Icons only where meaningful, uniform within group |
| Coloured header bars/cards to express branding | Branding via content (album art, typography), neutral chrome |
| Dot/badge clutter in the status item | One template glyph, state via symbol animation |
| Opaque black `#000` dark backgrounds | `windowBackgroundColor` #1E1E1E, labels via semantic colours |
| Hard-coded label greys | `.primary/.secondary/.tertiary` (translucent by design) |
| "Glass everywhere" toggle buttons | Glass only on floating controls; tinted glass only for the primary action |
| Static play/pause image swap | Magic Replace/bounce symbol transition; 0.15 s spring press state |
| Full-bleed image behind a solid black header bar | Scroll-edge fade under floating chrome (`scrollEdgeEffectStyle`) |
| Custom focus rings | System focus indicator colour |
| Ignoring Reduce Transparency / slider settings | Designed fallbacks and verified legibility at both slider ends |

---

## 6. Implementation notes, risks, open questions

### 6.1 Deployment target & availability strategy

PureListen's package currently declares `platforms: [.macOS(.v13)]`, and the redesign should not pretend otherwise: on macOS 13–15 the Golden Gate APIs do not exist, and the app will fall back to Tahoe/static chrome. Two viable paths:

| Path | Target | Consequence |
|---|---|---|
| **A (recommended for the redesign)** | `.macOS(.v27)` (+ `swiftLanguageModes` unchanged) | Full glass/concentric/scroll-edge APIs without `#available` clutter; the redesign only *claims* to be Golden Gate where it can actually render it. Users on 26 keep Tahoe chrome via a small availability tier. |
| **B (compat-first)** | keep `.v13`, gate everything | Every glass/scroll/toolbar call behind `if #available(macOS 26/27)`, plus a legacy look for 13–15. Most code churn, and the legacy look will not be used by the target audience (macOS 27 is current). |

Absolute must-knows:
- Building against the macOS 27 SDK makes the app adopt the new design **automatically**; the `UIDesignRequiresCompatibility` opt-out is ignored for macOS 27+ SDK builds ([Apple docs](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility)).
- `Glass`, `.glassEffect`, `GlassEffectContainer`, `scrollEdgeEffectStyle`, `backgroundExtensionEffect` = macOS 26+; `NSGlassEffectView.effectIsInteractive`, `NSViewCornerConfiguration`, `NSStatusItem.expandedInterfaceDelegate` = **macOS 27+**.
- `ToolbarOverflowMenu` + `.topBarPinnedTrailing` + `.toolbarMinimizeBehavior` are **not available on macOS** — don't design around them.
- `ConcentricRectangle` is not a `RoundedRectangularShape`; use it as a shape, not in `.containerShape`.

### 6.2 Popover vs. expanded-interface session

For a menu-bar app with a rich panel, macOS 27's `NSStatusItemExpandedInterfaceSession` is the intended replacement for manual show/hide: it keeps keyboard focus, menu tracking and dismissal behaviours consistent. Keep `NSPopover`'s `contentSize = 360×560` and its system glass; don't set `popover.appearance` or a custom background.

### 6.3 Verification matrix (must pass before shipping the redesign)

1. Light + Dark + Auto appearance.
2. Liquid Glass slider at **min, default (middle), max** (System Settings ▸ Appearance) — text over glass must remain ≥4.5:1.
3. Reduce Transparency ON (glass becomes opaque — layout must not collapse).
4. Increase Contrast ON (labels/focus rings).
5. Reduce Motion ON (no movement, cross-fades only).
6. Busy/light wallpaper behind the popover (worst case for clear glass).
7. HDR display vs SDR display/profile.
8. VoiceOver: every symbol/button labelled; time counters read sensibly.
9. Window resize (Now Playing window) from minimum to wide.
10. Menu bar crowded (extra status items hide) — glyph must remain recognisable at 16 pt.

### 6.4 Risks & uncertainty

| Risk | Detail | Mitigation |
|---|---|---|
| Popover radius | 19–20 pt measured on a custom `NSPopover`; a system `MenuBarExtra(.window)` popover may differ by a point or two. | Re-measure after choosing the container; never hard-code the *shell* radius — let the system draw it. |
| Glass colour numbers | Captured from a P3 display and converted to sRGB; values indicate behaviour, not API constants. They also shift with the global slider and Increase Contrast. | Use them as ratios/relationships; verify visually on the target display. |
| Motion numbers | Settle times derived at 60 Hz with a 0.5 pt threshold; ProMotion sampling differs (same curve, different sample counts). `.snappy(duration:)` showed no measurable change — treat duration parameter as advisory. | Validate feel on-device; prefer `spring(response:dampingFraction:)` when precise control matters. |
| Press contradictions | The Verge called window radii "increased"; MacRumors/9to5Mac/iThome say Tahoe was more rounded and GG is tighter. The **measured** 16 pt on 27.0.1 is authoritative here. | If Apple tweaks radius in 27.x, the system enforces it — don't paint over it. |
| SF Symbols version | Version number not verifiable on disk; features documented in HIG are SF Symbols 7-era. | Use symbol names present on the minimum supported OS; test `NSImage(systemSymbolName:)` non-nil. |
| HDR | Apple's HDR UI claim is unverified for third-party rendering. | Don't hand-roll HDR; rely on system glass. |
| Chinese typography | CJK optical size/tracking specificities are practice-based, not measured against a Chinese macOS 27 spec. | Visually test 10/11/13/15 pt Chinese strings; prefer 11 pt+ for anything users read. |
| Menu bar height | HIG says 24 pt, measured 33 pt. | Design against 33 pt; don't hard-code either — use the status item APIs. |

### 6.5 Suggested implementation order

1. **Shell:** status item via expanded-interface session; popover content padding/typography tokens; remove all custom backgrounds from popover/window.
2. **Tokens file** (`DesignTokens.swift`): radius, spacing, type ramp wrappers, colours, motion constants from §3.
3. **Now-playing screen:** art + text + progress + one glass transport cluster; verify glass over art wash.
4. **Secondary screens:** playlists/tracks list (28 pt rows, 12 pt radius selection capsules), settings sheet, login QR.
5. **Now Playing window:** unified toolbar, 52 pt chrome, two-column layout, background extension if art goes edge-to-edge.
6. **Icon:** layered Icon Composer app icon; status item template glyph.
7. **Accessibility & verification:** matrix §6.3.

---

## Appendix A — measurement log & methodology

**Environment:** macOS 27.0.1 (26A434), Xcode 27.1 (27A9275), Swift 6.4, SDK macOS 27.0; display 1470×956 pt @2× (visibleFrame 1405×923, Dock left inset 65 pt, menu bar 33 pt). Date: 2026-10-26, 01:47–02:05 local.

**Capture:** `screencapture -x -o -l <windowID>` for standard app windows (Finder, System Settings, Preview) and for probe windows; `-R` region captures for composited/glass sampling. Window IDs from a Swift `CGWindowListCopyWindowInfo` helper (`measure/windowlist.swift`). No audio, no settings changes, no personal documents retained.

**Pixel analysis (`measure/`):** corner radii via alpha-mask least-squares fit `x(y) = R − √(R² − (R − y)²)` (windows: R = 32.25 px @2×; popover: 38.5 px; menu: 31.75 px); glass interiors sampled over known #FFFFFF/#000000 backdrops; rim profiles via 1-px luminance scans; control sizes via `NSHostingView.fittingSize`.

**Probes built for this research (all in `measure/`):**
- [metrics.swift](measure/metrics.swift) — NSFont text styles + metrics, NSColor semantics in light/dark, NSAnimationContext default.
- [probe/main.swift](measure/probe/main.swift) — SwiftUI control fitting sizes; window chrome for plain/unified toolbar styles; NSPopover geometry; NSMenu geometry.
- [probe/glass.swift](measure/probe/glass.swift) — glass/material specimens over white/black in both appearances.
- [probe/motion.swift](measure/probe/motion.swift) — per-frame animation timing via an `Animatable` view modifier.
- [snippets.swift](measure/snippets.swift) — compile-check of every API snippet quoted in this document (type-checks against SDK 27; macOS-unavailable APIs removed).
- [windowlist.swift](measure/windowlist.swift), [extra.swift](measure/extra.swift) — window enumeration; extra control/glass-button sizing.

**Notable measurements recap:** window radius 16 pt (uniform); popover panel ≈20 pt with 13 pt shadow ring; menu ≈16 pt; unified toolbar chrome 52 pt; plain titlebar 32 pt; menu bar 33 pt; toolbar control pill 36 pt; slider track 6 pt/knob 20 pt; List row 24 pt; slider default ≈52 % of track; glass transmission/rim table in §3.5; motion table in §3.6.

## Appendix B — visual reference index (`docs/research/refs/`)

| File | What it shows | What to copy |
|---|---|---|
| [01-menubar-macos27.png](refs/01-menubar-macos27.png) | Full menu-bar strip on macOS 27 (33 pt, translucent over wallpaper) | menu bar height, text weight/position |
| [02-menubar-status-items-zoom.png](refs/02-menubar-status-items-zoom.png) | Status items zoomed: date, battery/percentage, Control Center, third-party icons | 16–17 pt glyph sizing, spacing, template treatment |
| [03-finder-toolbar-strip.png](refs/03-finder-toolbar-strip.png) | Golden Gate unified toolbar: traffic lights, grouped glass pills, search field | 36 pt control pills, group gaps, title placement |
| [04-finder-sidebar-strip.png](refs/04-finder-sidebar-strip.png) | Edge-to-edge sidebar with coloured icons and capsule selection | sidebar row pitch, accent-coloured icons, flush edge |
| [05-settings-window-appearance.png](refs/05-settings-window-appearance.png) | System Settings window (account row redacted), dark | window radius 16 pt, sidebar width 252 pt, grouped cards |
| [06-settings-liquid-glass-section.png](refs/06-settings-liquid-glass-section.png) | The new Liquid Glass slider + live glass preview card | slider anatomy, clear↔tinted end icons, glass over photo |
| [07-settings-theme-accent-colors.png](refs/07-settings-theme-accent-colors.png) | Accent colour swatches + icon/widget appearance options | swatch sizing/selection ring, label alignment |
| [08-settings-sidebar-edge-to-edge.png](refs/08-settings-sidebar-edge-to-edge.png) | Sidebar detail: coloured icons, selection, group headers | selection capsule, icon colour behaviour |
| [09-popover-360x560-panel.png](refs/09-popover-360x560-panel.png) | A real NSPopover panel with 360×560 content (dark) | panel radius, content margins, interactive glass capsule |
| [10-window-corner-radius-annotated.png](refs/10-window-corner-radius-annotated.png) | Annotated 16 pt window corner fit | how tight the new radius is |
| [11-glass-specimens-dark.png](refs/11-glass-specimens-dark.png) | `regular`/`clear`/`tinted` glass + materials over white/black, dark | glass colour conclusions in §3.5 |
| [12-glass-specimens-light.png](refs/12-glass-specimens-light.png) | Same, light appearance | light-mode glass behaviour |
| [13-controls-gallery-dark.png](refs/13-controls-gallery-dark.png) | macOS 27 controls: bordered/glass buttons, switch, checkbox, field, segmented, slider, progress, 4 button sizes, List rows | exact control styling & heights |
| [14-menu-liquid-glass.png](refs/14-menu-liquid-glass.png) | NSMenu (golden-gate glass) over a known backdrop | menu radius, row height, icons, chevron |
| [15-popover-over-desktop.png](refs/15-popover-over-desktop.png) | Popover composited over the desktop (shadow + transparency) | how the panel sits on content, shadow extents |

## Appendix C — sources

**Apple**
- HIG Materials — https://developer.apple.com/design/human-interface-guidelines/materials
- HIG Layout — https://developer.apple.com/design/human-interface-guidelines/layout
- HIG Typography — https://developer.apple.com/design/human-interface-guidelines/typography
- HIG Color — https://developer.apple.com/design/human-interface-guidelines/color
- HIG Motion — https://developer.apple.com/design/human-interface-guidelines/motion
- HIG Sidebars — https://developer.apple.com/design/human-interface-guidelines/sidebars
- HIG Toolbars — https://developer.apple.com/design/human-interface-guidelines/toolbars
- HIG Menus — https://developer.apple.com/design/human-interface-guidelines/menus
- HIG The menu bar — https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
- HIG Buttons — https://developer.apple.com/design/human-interface-guidelines/buttons
- HIG Scroll views — https://developer.apple.com/design/human-interface-guidelines/scroll-views
- HIG Dark Mode — https://developer.apple.com/design/human-interface-guidelines/dark-mode
- HIG SF Symbols — https://developer.apple.com/design/human-interface-guidelines/sf-symbols
- HIG App icons — https://developer.apple.com/design/human-interface-guidelines/app-icons
- Adopting Liquid Glass — https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Applying Liquid Glass to custom views — https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- ConcentricRectangle — https://developer.apple.com/documentation/swiftui/concentricrectangle
- NSViewCornerConfiguration — https://developer.apple.com/documentation/appkit/nsviewcornerconfiguration
- UIDesignRequiresCompatibility (ignored on 27+) — https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility
- WWDC26 269 What's new in SwiftUI — https://developer.apple.com/videos/play/wwdc2026/269/
- WWDC26 289 Modernize your AppKit app — https://developer.apple.com/videos/play/wwdc2026/289/
- WWDC26 102 Platforms State of the Union — https://developer.apple.com/videos/play/wwdc2026/102/
- WWDC26 250 Principles of great design — https://developer.apple.com/videos/play/wwdc2026/250/
- WWDC25 219 Meet Liquid Glass (background on glass principles) — https://developer.apple.com/videos/play/wwdc2025/219/
- Apple Support: What's new in the updates for macOS 27 Golden Gate — https://support.apple.com/en-us/127257

**Press**
- MacRumors, "Apple Announces macOS 27 Golden Gate…" (2026-06-08) — https://www.macrumors.com/2026/06/08/apple-announces-macos-golden-gate/
- MacRumors, "All the Liquid Glass Changes in macOS Golden Gate" (2026-06-09) — https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/
- MacRumors, "Apple Releases macOS Golden Gate Beta 6" (uniform toolbars, edge-to-edge sidebars, less rounded corners) — https://www.macrumors.com/2026/08/17/apple-releases-macos-golden-gate-beta-6/
- 9to5Mac, "macOS 27 Golden Gate includes these changes that Tahoe critics will appreciate" (2026-06-09) — https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/
- The Verge, "Apple dials down Liquid Glass, and the Mac looks way better for it" (hands-on) — https://www.theverge.com/tech/946567/apple-macos-27-golden-gate-dev-beta-hands-on
- heise online, "macOS 27 Golden Gate: Liquid Glass refinement…" — https://www.heise.de/en/news/macOS-27-Golden-Gate-Liquid-Glass-refinement-better-performance-Siri-AI-11322387.html
- iThome (zh), "初探苹果 macOS 27 液态玻璃调整" (window radius, edge-to-edge sidebar, coloured icons) — https://m.ithome.com/html/962168.htm

---

*Prepared for the PureListen Golden Gate redesign. Measurements are reproducible with the scripts in `docs/research/measure/`; API availability is verified separately in `docs/research/sdk-api-cheatsheet.md`.*
