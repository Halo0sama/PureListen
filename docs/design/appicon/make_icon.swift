#!/usr/bin/env swift
// make_icon.swift — 净听 PureListen macOS 27 "Golden Gate" 应用图标 / 菜单栏图标生成器
//
// 用法:
//   swift docs/design/appicon/make_icon.swift
//   产物(同目录):
//     icon_1024.png           1024×1024 应用图标(透明外缘 + 内建投影, Apple 824 网格)
//     icon_16.png / icon_32.png   小尺寸自检样张(光学补偿变体)
//     AppIcon.icns            macOS 全套 icns(16/32/128/256/512 @1x@2x)
//     menubar_template.png    17×17 template(黑 + alpha, isTemplate=true)
//     menubar_template@2x.png 34×34 template
//     menubar_visibility_check.png  浅色/深色/壁纸三种菜单栏底色下的可见性验证
//     icon_preview.png        浅色/深色背景 + 各尺寸的评审预览
//
// 设计: 分层液态玻璃 —— 圆角方块玻璃底(深靛蓝→紫罗兰, 右上青绿冷光, 左上柔光)
//       + 内层玻璃薄片(上亮下暗 + 镜面高光边) + 深色唱片盘(浅纹圈/标签)
//       + 品牌符号: 外圈 18–20° 开口的唱片环 + 中心唱针落点。
// 16/32px 做光学补偿: 符号放大加粗、唱片盘同步放大、≤16px 闭合开口保证辨识。

import AppKit
import CoreGraphics
import CoreText
import ImageIO

// MARK: - 常量

private let CANVAS: CGFloat = 1024
private let TILE: CGFloat = 824                    // Apple macOS icon grid: 824×824 centered
private let TILE_INSET: CGFloat = (CANVAS - TILE) / 2
private let TILE_RADIUS: CGFloat = 185.4           // Apple template corner radius (superellipse approx.)

func cg(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a)
}

// MARK: - 路径

/// 连续圆角方块(superellipse n≈5, 近似 macOS squircle 网格形状)。
func squirclePath(rect: CGRect, n: CGFloat = 5.0, segments: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let cx = rect.midX, cy = rect.midY
    let a = rect.width / 2, b = rect.height / 2
    func point(_ t: CGFloat) -> CGPoint {
        let ct = cos(t), st = sin(t)
        return CGPoint(x: cx + copysign(pow(abs(ct), 2 / n), ct) * a,
                       y: cy + copysign(pow(abs(st), 2 / n), st) * b)
    }
    path.move(to: point(0))
    for i in 1...segments {
        path.addLine(to: point(CGFloat(i) / CGFloat(segments) * 2 * .pi))
    }
    path.closeSubpath()
    return path
}

/// 开口圆环(0° = 正右, 角度增加为屏幕顺时针; 上下文为 y 向下)。
func openRingPath(center: CGPoint, radius: CGFloat, gapDegrees: CGFloat,
                  gapCenterDegrees: CGFloat) -> CGPath {
    let half = gapDegrees / 2
    let path = CGMutablePath()
    path.addArc(center: center, radius: radius,
                startAngle: (gapCenterDegrees + half) * .pi / 180,
                endAngle: (gapCenterDegrees + 360 - half) * .pi / 180,
                clockwise: false)
    return path
}

// MARK: - 设计参数

struct Palette {
    var plate: [CGColor]
    var plateLocations: [CGFloat]
    var violetBloom: CGColor
    var cyanGlow: CGColor
    var cyanGlowRadius: CGFloat
    var symbolTop: CGColor
    var symbolBottom: CGColor
    var innerPaneAlpha: CGFloat
    var innerPaneInset: CGFloat
    var bottomShade: CGFloat
}

struct SymbolStyle {
    var ringRadius: CGFloat
    var stroke: CGFloat
    var dotRadius: CGFloat
    var gap: CGFloat
    var gapCenter: CGFloat
    var roundCaps: Bool
    var specular: Bool
    var darkEdge: Bool
    var discRadius: CGFloat
    var grooveRings: Int
    var dotRingAlpha: CGFloat
}

/// 最终配色(与 DesignSystem.swift 的紫罗兰/靛蓝调性一致, 未使用系统蓝)
let palette = Palette(
    plate: [cg(0x6E57F5), cg(0x3A28A8), cg(0x120B33)],
    plateLocations: [0, 0.46, 1],
    violetBloom: cg(0xA895FF, 0.34),
    cyanGlow: cg(0x5BE9DA, 0.34),
    cyanGlowRadius: 0.58,
    symbolTop: cg(0xFFFFFF, 1.0),
    symbolBottom: cg(0xD3CAFF, 0.96),
    innerPaneAlpha: 0.15,
    innerPaneInset: 58,
    bottomShade: 0.40)

/// 最终符号: 深色唱片盘 + 18° 开口唱片环(平切) + 中心唱针落点。
let symbol = SymbolStyle(
    ringRadius: 258, stroke: 58, dotRadius: 56, gap: 18, gapCenter: -55,
    roundCaps: false, specular: true, darkEdge: true,
    discRadius: 292, grooveRings: 3, dotRingAlpha: 0.16)

struct IconOptions {
    var small: Bool = false     // ≤32px: 加粗放大
    var tiny: Bool = false      // ≤16px: 闭合开口 + 去掉细节
    var showShadow: Bool = true
}

// MARK: - 绘制

func drawIcon(_ ctx: CGContext, px: CGFloat, options: IconOptions) {
    ctx.saveGState()
    ctx.scaleBy(x: px / CANVAS, y: px / CANVAS)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: CANVAS)
    ctx.scaleBy(x: 1, y: -1)

    let tileRect = CGRect(x: TILE_INSET, y: TILE_INSET, width: TILE, height: TILE)
    let tile = squirclePath(rect: tileRect)

    // 0. 底部投影
    if options.showShadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 20), blur: 36,
                      color: cg(0x05030F, options.small ? 0.32 : 0.42))
        ctx.addPath(tile)
        ctx.setFillColor(cg(0x0B0820))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 1. 玻璃底: 深靛蓝 → 紫罗兰 + 右上冷光 + 左上柔光 + 底部加暗 + 斜向反光带
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let plateGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: palette.plate as CFArray,
                               locations: palette.plateLocations)!
    ctx.drawLinearGradient(plateGrad,
                           start: CGPoint(x: tileRect.minX, y: tileRect.maxY),
                           end: CGPoint(x: tileRect.maxX, y: tileRect.minY), options: [])
    let cyan = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [palette.cyanGlow, cg(0x46E0D2, 0)] as CFArray,
                          locations: [0, 1])!
    let cc = CGPoint(x: tileRect.minX + TILE * 0.86, y: tileRect.minY + TILE * 0.10)
    ctx.drawRadialGradient(cyan, startCenter: cc, startRadius: 0, endCenter: cc,
                           endRadius: TILE * palette.cyanGlowRadius, options: [])
    let bloom = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [palette.violetBloom, cg(0x8B7BFF, 0)] as CFArray,
                           locations: [0, 1])!
    let bc = CGPoint(x: tileRect.minX + TILE * 0.22, y: tileRect.minY + TILE * 0.16)
    ctx.drawRadialGradient(bloom, startCenter: bc, startRadius: 0, endCenter: bc,
                           endRadius: TILE * 0.72, options: [])
    let shade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [cg(0x05030F, 0), cg(0x05030F, palette.bottomShade)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(shade,
                           start: CGPoint(x: 0, y: tileRect.minY + TILE * 0.42),
                           end: CGPoint(x: 0, y: tileRect.maxY), options: [])
    ctx.saveGState()
    ctx.translateBy(x: tileRect.minX, y: tileRect.minY)
    ctx.rotate(by: -32 * .pi / 180)
    let band = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [cg(0xFFFFFF, 0), cg(0xFFFFFF, 0.05), cg(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(band, start: CGPoint(x: -TILE * 0.4, y: 0),
                           end: CGPoint(x: TILE * 0.4, y: 0), options: [])
    ctx.restoreGState()
    ctx.restoreGState()

    // 2. 内层玻璃薄片
    let inset = options.tiny ? palette.innerPaneInset * 1.3 : palette.innerPaneInset
    let innerRect = tileRect.insetBy(dx: inset, dy: inset)
    let inner = squirclePath(rect: innerRect)
    ctx.saveGState()
    ctx.addPath(inner)
    ctx.clip()
    let glass = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [cg(0xFFFFFF, options.tiny ? 0.20 : palette.innerPaneAlpha),
                                    cg(0xFFFFFF, palette.innerPaneAlpha * 0.30),
                                    cg(0xFFFFFF, 0.004)] as CFArray,
                           locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(glass, start: CGPoint(x: 0, y: innerRect.minY),
                           end: CGPoint(x: 0, y: innerRect.maxY), options: [])
    let innerBottom = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: [cg(0x05030F, 0), cg(0x05030F, 0.30)] as CFArray,
                                 locations: [0, 1])!
    ctx.drawLinearGradient(innerBottom,
                           start: CGPoint(x: 0, y: innerRect.minY + innerRect.height * 0.55),
                           end: CGPoint(x: 0, y: innerRect.maxY), options: [])
    ctx.restoreGState()

    // 2b. 玻璃方块边缘: 内侧镜面描边 + 外侧暗线
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.setLineWidth(options.small ? 2.0 : 3.0)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let edgeLight = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [cg(0xFFFFFF, 0.34), cg(0xFFFFFF, 0.10), cg(0xFFFFFF, 0.02)] as CFArray,
                               locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(edgeLight, start: CGPoint(x: 0, y: tileRect.minY),
                           end: CGPoint(x: 0, y: tileRect.maxY), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.setLineWidth(options.small ? 1.0 : 1.4)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.setFillColor(cg(0x05030F, 0.30))
    ctx.fill(CGRect(x: 0, y: 0, width: CANVAS, height: CANVAS))
    ctx.restoreGState()

    // 2c. 内片镜面高光边
    ctx.saveGState()
    let rimGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                             colors: [cg(0xFFFFFF, 0.62), cg(0xFFFFFF, 0.10), cg(0x05030F, 0.22)] as CFArray,
                             locations: [0, 0.55, 1])!
    ctx.addPath(inner)
    ctx.setLineWidth(options.small ? 2.2 : 3.0)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(rimGrad, start: CGPoint(x: 0, y: innerRect.minY),
                           end: CGPoint(x: 0, y: innerRect.maxY), options: [])
    ctx.restoreGState()

    // 3. 前景符号
    let center = CGPoint(x: CANVAS / 2, y: CANVAS / 2)
    var st = symbol
    if options.tiny {
        st.gap = 0
        st.ringRadius *= 1.05
        st.stroke *= 1.30
        st.dotRadius *= 1.16
        st.specular = false
    } else if options.small {
        st.gap = 14
        st.ringRadius *= 1.10
        st.stroke *= 1.28
        st.dotRadius *= 1.16
    }
    // 唱片盘始终略大于环外缘, 形成"环=盘沿"的关系
    st.discRadius = st.ringRadius + st.stroke * 0.55

    let ring = openRingPath(center: center, radius: st.ringRadius,
                            gapDegrees: st.gap, gapCenterDegrees: st.gapCenter)
    let symbolColor = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: [palette.symbolTop, palette.symbolBottom] as CFArray,
                                 locations: [0, 1])!
    let cap: CGLineCap = st.roundCaps ? .round : .butt

    func strokePath(_ path: CGPath, width: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(width)
        ctx.setLineCap(cap)
        ctx.setStrokeColor(color)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // 3a. 深色唱片盘
    let discRect = CGRect(x: center.x - st.discRadius, y: center.y - st.discRadius,
                          width: st.discRadius * 2, height: st.discRadius * 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: options.small ? 4 : 14),
                  blur: options.small ? 8 : 26, color: cg(0x04020E, 0.55))
    ctx.setFillColor(cg(0x0A0720, 1))
    ctx.fillEllipse(in: discRect)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: discRect)
    ctx.clip()
    let vinyl = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [cg(0x2B2166, 1), cg(0x141034, 1), cg(0x070510, 1)] as CFArray,
                           locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(vinyl, start: CGPoint(x: discRect.minX, y: discRect.minY),
                           end: CGPoint(x: discRect.maxX, y: discRect.maxY), options: [])
    let discSheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [cg(0xFFFFFF, 0.14), cg(0xFFFFFF, 0)] as CFArray,
                               locations: [0, 1])!
    let sc = CGPoint(x: center.x - st.discRadius * 0.30, y: center.y - st.discRadius * 0.55)
    ctx.drawRadialGradient(discSheen, startCenter: sc, startRadius: 0, endCenter: sc,
                           endRadius: st.discRadius * 0.95, options: [])
    ctx.restoreGState()
    if st.grooveRings > 0 && !options.small && !options.tiny {
        for i in 1...st.grooveRings {
            let r = st.discRadius * (1 - CGFloat(i) * 0.135)
            ctx.saveGState()
            ctx.setStrokeColor(cg(0xFFFFFF, i == 1 ? 0.16 : 0.09))
            ctx.setLineWidth(max(1.0, st.discRadius * 0.010))
            ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                         width: r * 2, height: r * 2))
            ctx.restoreGState()
        }
    }

    // 3b. 符号投影
    if options.showShadow && !options.tiny {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: options.small ? 5 : 15),
                      blur: options.small ? 8 : 28, color: cg(0x0A0620, 0.50))
        strokePath(ring, width: st.stroke, color: cg(0x0A0620))
        ctx.setFillColor(cg(0x0A0620))
        ctx.fillEllipse(in: CGRect(x: center.x - st.dotRadius, y: center.y - st.dotRadius,
                                   width: st.dotRadius * 2, height: st.dotRadius * 2))
        ctx.restoreGState()
    }

    // 3c. 深色折射边: 只在环的下半段(避免切口处出现碎块) —— 用裁剪实现
    if st.darkEdge {
        ctx.saveGState()
        ctx.clip(to: CGRect(x: center.x - st.discRadius, y: center.y,
                            width: st.discRadius * 2, height: st.discRadius))
        let edge = openRingPath(center: CGPoint(x: center.x + 2, y: center.y + 3),
                                radius: st.ringRadius, gapDegrees: st.gap,
                                gapCenterDegrees: st.gapCenter)
        strokePath(edge, width: st.stroke + 3, color: cg(0x0B0726, 0.45))
        ctx.restoreGState()
    }

    // 3d. 环填充(渐变裁剪到笔画)
    func fillOpenRing(radius: CGFloat, width: CGFloat, gap: CGFloat) {
        let path = openRingPath(center: center, radius: radius, gapDegrees: gap,
                                gapCenterDegrees: st.gapCenter)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(width)
        ctx.setLineCap(cap)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(symbolColor,
                               start: CGPoint(x: center.x - radius, y: center.y - radius),
                               end: CGPoint(x: center.x + radius, y: center.y + radius), options: [])
        ctx.restoreGState()
    }
    fillOpenRing(radius: st.ringRadius, width: st.stroke, gap: st.gap)

    // 3e. 唱片标签(微弱圆盘) + 中心唱针落点
    if !options.tiny {
        let lr = st.dotRadius * 1.9
        ctx.saveGState()
        ctx.setFillColor(cg(0x8C7BFF, 0.10))
        ctx.fillEllipse(in: CGRect(x: center.x - lr, y: center.y - lr, width: lr * 2, height: lr * 2))
        ctx.restoreGState()
    }
    let dotRect = CGRect(x: center.x - st.dotRadius, y: center.y - st.dotRadius,
                         width: st.dotRadius * 2, height: st.dotRadius * 2)
    ctx.saveGState()
    ctx.addEllipse(in: dotRect)
    ctx.clip()
    ctx.drawLinearGradient(symbolColor, start: CGPoint(x: dotRect.minX, y: dotRect.minY),
                           end: CGPoint(x: dotRect.maxX, y: dotRect.maxY), options: [])
    ctx.restoreGState()

    // 3f. 细圈 + 顶部镜面高光弧
    if st.dotRingAlpha > 0 && !options.tiny {
        let r = st.dotRadius * 1.62
        ctx.saveGState()
        ctx.setStrokeColor(cg(0xFFFFFF, st.dotRingAlpha))
        ctx.setLineWidth(options.small ? 1.2 : 2.2)
        ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }
    if st.specular && !options.small && !options.tiny {
        let hi = openRingPath(center: CGPoint(x: center.x - 2, y: center.y - 3),
                              radius: st.ringRadius - st.stroke * 0.30,
                              gapDegrees: st.gap + 10, gapCenterDegrees: st.gapCenter)
        strokePath(hi, width: st.stroke * 0.12, color: cg(0xFFFFFF, 0.62))
    }

    // 4. 左上大光斑(很轻, 只负责"玻璃感")
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [cg(0xFFFFFF, options.small ? 0.05 : 0.08), cg(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    let sheenCenter = CGPoint(x: tileRect.minX + TILE * 0.28, y: tileRect.minY + TILE * 0.08)
    ctx.drawRadialGradient(sheen, startCenter: sheenCenter, startRadius: 0,
                           endCenter: sheenCenter, endRadius: TILE * 0.8, options: [])
    ctx.restoreGState()
    ctx.restoreGState()
}

func renderCGImage(size: Int, options: IconOptions) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    // 小尺寸超采样后降采样, 保证 16/32px 边缘干净
    let supersample: CGFloat = size <= 32 ? 8 : (size <= 64 ? 3 : 1)
    let renderPx = CGFloat(size) * supersample
    let ctx = CGContext(data: nil, width: Int(renderPx), height: Int(renderPx),
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(ctx, px: renderPx, options: options)
    let raw = ctx.makeImage()!
    if supersample == 1 { return raw }
    let down = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                         bytesPerRow: 0, space: cs,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    down.interpolationQuality = .high
    down.draw(raw, in: CGRect(x: 0, y: 0, width: size, height: size))
    return down.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed: \(url.path)")
    }
    try! data.write(to: url)
}

// MARK: - 菜单栏 template 图标

/// 17pt 画布: 环 + 中心点, 1.5px 线宽(1x)。纯黑 + alpha, 交给系统做 template 着色。
func renderMenuBarGlyph(pt: CGFloat, px: CGFloat) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(px), height: Int(px), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: px / pt, y: px / pt)
    ctx.setShouldAntialias(true)
    ctx.setAllowsAntialiasing(true)
    ctx.translateBy(x: 0, y: pt)
    ctx.scaleBy(x: 1, y: -1)
    let c = CGPoint(x: pt / 2, y: pt / 2)
    let radius = pt * 0.315            // 17pt → 5.36pt
    let stroke: CGFloat = 1.5
    let dot: CGFloat = 2.6
    let ring = openRingPath(center: c, radius: radius, gapDegrees: 42, gapCenterDegrees: -55)
    ctx.addPath(ring)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(cg(0x000000, 1))
    ctx.strokePath()
    ctx.setFillColor(cg(0x000000, 1))
    ctx.fillEllipse(in: CGRect(x: c.x - dot / 2, y: c.y - dot / 2, width: dot, height: dot))
    return ctx.makeImage()!
}

// MARK: - 预览图 / 可见性验证图

/// 在 y 向下(已翻转)的上下文里正确绘制位图。
func drawImageFlipped(_ ctx: CGContext, _ img: CGImage, in rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    ctx.restoreGState()
}

func drawLabel(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat,
               color: CGColor) {
    let font = CTFontCreateWithName("SF Pro Text" as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor(cgColor: color) ?? .black
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func makeIconPreview(icon: CGImage) -> CGImage {
    let W: CGFloat = 1200, H: CGFloat = 720
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)   // y 向下
    // 背景: 上半浅色, 下半深色
    ctx.setFillColor(cg(0xF2F2F5, 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H / 2))
    ctx.setFillColor(cg(0x1C1C22, 1)); ctx.fill(CGRect(x: 0, y: H / 2, width: W, height: H / 2))
    // 320pt 预览(浅/深)
    drawImageFlipped(ctx, icon, in: CGRect(x: 40, y: 40, width: 320, height: 320))
    drawImageFlipped(ctx, icon, in: CGRect(x: 40, y: 380, width: 320, height: 320))
    drawLabel(ctx, "Golden Gate app icon · 320pt on light / dark", x: 380, y: 660, size: 18,
              color: cg(0x1C1C22, 1))
    // 尺寸阶梯 on light
    var x: CGFloat = 420
    var rowY: CGFloat = 30
    for size in [128, 64, 32, 16] {
        let img = renderCGImage(size: size, options: IconOptions(small: size <= 32, tiny: size <= 16))
        let h = CGFloat(size)
        drawImageFlipped(ctx, img, in: CGRect(x: x, y: rowY, width: h, height: h))
        drawLabel(ctx, "\(size)px", x: x + h + 12, y: rowY + h / 2 - 6, size: 14, color: cg(0x1C1C22, 1))
        rowY += h + 16
    }
    // 尺寸阶梯 on dark
    x = 420
    rowY = 370
    for size in [128, 64, 32, 16] {
        let img = renderCGImage(size: size, options: IconOptions(small: size <= 32, tiny: size <= 16))
        let h = CGFloat(size)
        drawImageFlipped(ctx, img, in: CGRect(x: x, y: rowY, width: h, height: h))
        drawLabel(ctx, "\(size)px", x: x + h + 12, y: rowY + h / 2 - 6, size: 14, color: cg(0xE8E8EE, 1))
        rowY += h + 16
    }
    // 浅色下的描边分离检查窄条
    ctx.setFillColor(cg(0xFFFFFF, 1)); ctx.fill(CGRect(x: 900, y: 40, width: 260, height: 260))
    drawImageFlipped(ctx, icon, in: CGRect(x: 920, y: 60, width: 220, height: 220))
    return ctx.makeImage()!
}

func makeMenuBarVisibilityCheck() -> CGImage {
    let zoom: CGFloat = 6
    let glyph = renderMenuBarGlyph(pt: 17, px: 17)
    let W: CGFloat = 900, H: CGFloat = 360
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)   // y 向下
    // 三种底色(上→下): 浅色菜单栏 / 深色菜单栏 / 半透明壁纸
    ctx.setFillColor(cg(0xE9E9EC)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H / 3))
    ctx.setFillColor(cg(0x2A2A2E)); ctx.fill(CGRect(x: 0, y: H / 3, width: W, height: H / 3))
    let wallpaper = CGGradient(colorsSpace: cs,
                                colors: [cg(0x5E6E82), cg(0x93A3B0)] as CFArray,
                                locations: [0, 1])!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: H * 2 / 3, width: W, height: H / 3))
    ctx.drawLinearGradient(wallpaper, start: CGPoint(x: 0, y: H * 2 / 3),
                           end: CGPoint(x: W, y: H), options: [])
    ctx.restoreGState()
    // 每种底色上: 系统 template 着色 -> 浅底黑字, 深底白字
    func drawGlyph(_ g: CGImage, rect: CGRect, white: Bool) {
        if white {
            let cs2 = CGColorSpace(name: CGColorSpace.sRGB)!
            let tmp = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height),
                                bitsPerComponent: 8, bytesPerRow: 0, space: cs2,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            tmp.draw(g, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            tmp.setBlendMode(.sourceIn)
            tmp.setFillColor(cg(0xFFFFFF, 1))
            tmp.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            if let whiteGlyph = tmp.makeImage() {
                drawImageFlipped(ctx, whiteGlyph, in: rect)
            }
        } else {
            drawImageFlipped(ctx, g, in: rect)
        }
    }
    let gw = 17 * zoom
    let lightY = (H / 3 - gw) / 2
    let darkY = H / 3 + (H / 3 - gw) / 2
    let wallY = H * 2 / 3 + (H / 3 - gw) / 2
    ctx.setFillColor(cg(0x2A2A2E, 1)) // 浅色栏上黑色字形
    ctx.setStrokeColor(cg(0x2A2A2E, 1))
    drawGlyph(glyph, rect: CGRect(x: 60, y: lightY, width: gw, height: gw), white: false)
    drawGlyph(glyph, rect: CGRect(x: 60, y: darkY, width: gw, height: gw), white: true)
    drawGlyph(glyph, rect: CGRect(x: 60, y: wallY, width: gw, height: gw), white: true)
    // 14pt 版本对比(说明 17pt 更稳)
    drawLabel(ctx, "17pt template @6x — light bar: black glyph", x: 60 + gw + 30, y: lightY + gw / 2,
              size: 18, color: cg(0x2A2A2E, 1))
    drawLabel(ctx, "17pt template @6x — dark bar: white glyph", x: 60 + gw + 30, y: darkY + gw / 2,
              size: 18, color: cg(0xF2F2F6, 1))
    drawLabel(ctx, "17pt template @6x — translucent wallpaper bar: white glyph",
              x: 60 + gw + 30, y: wallY + gw / 2, size: 18, color: cg(0xF2F2F6, 1))
    return ctx.makeImage()!
}

// MARK: - main

let outDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let fm = FileManager.default

writePNG(renderCGImage(size: 1024, options: IconOptions()), to: outDir.appendingPathComponent("icon_1024.png"))
writePNG(renderCGImage(size: 16, options: IconOptions(small: true, tiny: true)),
         to: outDir.appendingPathComponent("icon_16.png"))
writePNG(renderCGImage(size: 32, options: IconOptions(small: true)),
         to: outDir.appendingPathComponent("icon_32.png"))

// iconset → icns
let iconset = outDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in entries {
    writePNG(renderCGImage(size: size, options: IconOptions(small: size <= 32, tiny: size <= 16)),
             to: iconset.appendingPathComponent(name))
}
let icnsURL = outDir.appendingPathComponent("AppIcon.icns")
try? fm.removeItem(at: icnsURL)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try! p.run(); p.waitUntilExit()
try? fm.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "AppIcon.icns ✓" : "iconutil failed")

// 菜单栏 template(@1x / @2x)
writePNG(renderMenuBarGlyph(pt: 17, px: 17), to: outDir.appendingPathComponent("menubar_template.png"))
writePNG(renderMenuBarGlyph(pt: 17, px: 34), to: outDir.appendingPathComponent("menubar_template@2x.png"))

// 预览 / 可见性验证
writePNG(makeIconPreview(icon: renderCGImage(size: 1024, options: IconOptions())),
         to: outDir.appendingPathComponent("icon_preview.png"))
writePNG(makeMenuBarVisibilityCheck(), to: outDir.appendingPathComponent("menubar_visibility_check.png"))

print("done → \(outDir.path)")
