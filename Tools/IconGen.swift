// SilenceGate 图标生成器：用 CoreGraphics 画，不依赖任何设计工具。
// 编译：swiftc -O Tools/IconGen.swift -o /tmp/icongen
// 用法：/tmp/icongen <输出目录>
//
// 设计：深色圆角底板 + 被斜线划掉的喇叭（外放静音）+ 右下角绿色耳机徽章（只有耳机出声）。

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - 基础工具

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("cannot create context")
    }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot create destination \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(path)") }
}

// MARK: - 图标绘制（1024 × 1024 设计稿坐标，左上角为原点）

let canvas: CGFloat = 1024

/// 底板：macOS 原生比例 —— 824 见方、圆角 185、居中留白
func drawTile(_ ctx: CGContext) {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()

    // 底色渐变：上方偏蓝灰，下方近黑
    let base = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [rgb(0x33456B), rgb(0x151E31), rgb(0x0B1220)] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 512, y: 100),
                           end: CGPoint(x: 512, y: 924), options: [])

    // 左上柔和光晕，避免整块死板
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: 380, y: 260), startRadius: 0,
                           endCenter: CGPoint(x: 380, y: 260), endRadius: 620,
                           options: [])

    ctx.restoreGState()

    // 玻璃质感的内描边
    ctx.addPath(tile)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.14))
    ctx.setLineWidth(3)
    ctx.strokePath()
}

/// 喇叭（箱体 + 号角），白色
func drawSpeaker(_ ctx: CGContext) {
    let body = CGPath(roundedRect: CGRect(x: 206, y: 402, width: 142, height: 178),
                      cornerWidth: 34, cornerHeight: 34, transform: nil)

    let horn = CGMutablePath()
    horn.move(to: CGPoint(x: 348, y: 432))
    horn.addLine(to: CGPoint(x: 572, y: 318))
    horn.addLine(to: CGPoint(x: 572, y: 664))
    horn.addLine(to: CGPoint(x: 348, y: 550))
    horn.closeSubpath()

    ctx.setFillColor(rgb(0xF4F7FF))
    ctx.addPath(body)
    ctx.fillPath()
    ctx.addPath(horn)
    ctx.fillPath()
}

/// 静音斜线：先垫一圈底色做分离，再画红杠
func drawSlash(_ ctx: CGContext) {
    let from = CGPoint(x: 214, y: 648)
    let to = CGPoint(x: 594, y: 336)

    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(0x111A2B))
    ctx.setLineWidth(76)
    ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()

    ctx.setStrokeColor(rgb(0xFF6B6B))
    ctx.setLineWidth(44)
    ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
}

/// 右下角徽章：绿色圆 + 白色耳机（表示"只有耳机出声"）
func drawBadge(_ ctx: CGContext) {
    let center = CGPoint(x: 752, y: 752)
    let radius: CGFloat = 124

    // 用底色描一圈，和底板拉开层次
    ctx.setFillColor(rgb(0x0F1626))
    ctx.fillEllipse(in: CGRect(x: center.x - radius - 16, y: center.y - radius - 16,
                               width: (radius + 16) * 2, height: (radius + 16) * 2))

    ctx.saveGState()
    let circle = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2), transform: nil)
    ctx.addPath(circle)
    ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [rgb(0x63F3B8), rgb(0x0FA96F)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: center.x - radius, y: center.y - radius),
                           end: CGPoint(x: center.x + radius, y: center.y + radius),
                           options: [])
    ctx.restoreGState()

    // 头梁：一条向上拱的粗线（坐标系 y 向下，所以控制点要在中心点上方）
    let cupY = center.y + 6
    let band = CGMutablePath()
    band.move(to: CGPoint(x: center.x - 58, y: cupY))
    band.addQuadCurve(to: CGPoint(x: center.x + 58, y: cupY),
                      control: CGPoint(x: center.x, y: cupY - 96))

    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(0x0B2A1E))
    ctx.setLineWidth(42)
    ctx.addPath(band); ctx.strokePath()

    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineWidth(24)
    ctx.addPath(band); ctx.strokePath()

    // 两个耳罩：从头梁两端往下挂
    ctx.setFillColor(rgb(0xFFFFFF))
    for x in [center.x - 72, center.x + 48] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: cupY - 6, width: 24, height: 66),
                           cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.fillPath()
    }
}

func drawAppIcon(_ ctx: CGContext, size: CGFloat) {
    let scale = size / canvas
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)
    // 设计稿用"左上角原点、y 向下"，这里翻转一次
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    drawTile(ctx)

    // 只放大"喇叭 + 斜线"这组：小尺寸（16/32px）更立得住，
    // 同时把徽章留在原来的内缩位置，不让它顶到圆角。
    ctx.saveGState()
    ctx.translateBy(x: 392, y: 485)
    ctx.scaleBy(x: 1.12, y: 1.12)
    ctx.translateBy(x: -392, y: -485)
    drawSpeaker(ctx)
    drawSlash(ctx)
    ctx.restoreGState()

    drawBadge(ctx)

    ctx.restoreGState()
}

// MARK: - 仓库 / README 用的横幅（1280 × 640）

func drawSocial(_ ctx: CGContext, width: CGFloat, height: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // 背景
    let bg = CGGradient(colorsSpace: space,
                        colors: [rgb(0x131C2E), rgb(0x090E18)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

    // 图标后方一团冷蓝光
    let blue = CGGradient(colorsSpace: space,
                          colors: [rgb(0x3E5C8F, 0.50), rgb(0x131C2E, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(blue,
                           startCenter: CGPoint(x: 246, y: height - 320), startRadius: 0,
                           endCenter: CGPoint(x: 246, y: height - 320), endRadius: 430,
                           options: [])

    // 右下角一点绿色，呼应"耳机可以出声"
    let green = CGGradient(colorsSpace: space,
                           colors: [rgb(0x12B37A, 0.30), rgb(0x0A0F1A, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(green,
                           startCenter: CGPoint(x: width - 90, y: 60), startRadius: 0,
                           endCenter: CGPoint(x: width - 90, y: 60), endRadius: 420,
                           options: [])

    // 图标：左侧竖排居中
    let iconSize: CGFloat = 300
    ctx.saveGState()
    ctx.translateBy(x: 96, y: (height - iconSize) / 2)
    drawAppIcon(ctx, size: iconSize)
    ctx.restoreGState()

    // 文字：右侧，三条基线排好，互不打架
    let textX: CGFloat = 96 + iconSize + 56

    let title = NSAttributedString(string: "SilenceGate", attributes: [
        .font: NSFont.systemFont(ofSize: 76, weight: .bold),
        .foregroundColor: NSColor(srgbRed: 0.96, green: 0.98, blue: 1, alpha: 1)
    ])
    let subtitle = NSAttributedString(string: "Sound only through your Bluetooth headphones", attributes: [
        .font: NSFont.systemFont(ofSize: 29, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.63, green: 0.73, blue: 0.87, alpha: 1)
    ])
    let chinese = NSAttributedString(string: "没戴耳机的时候，这台 Mac 一点声音都不许出", attributes: [
        .font: NSFont.systemFont(ofSize: 29, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.42, green: 0.86, blue: 0.68, alpha: 1)
    ])

    let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics

    title.draw(at: CGPoint(x: textX, y: 322))
    subtitle.draw(at: CGPoint(x: textX + 2, y: 262))
    chinese.draw(at: CGPoint(x: textX + 2, y: 205))

    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - 主流程

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let fm = FileManager.default

// 1. 1024 主图（README / 仓库用）
let iconCtx = makeContext(1024, 1024)
drawAppIcon(iconCtx, size: 1024)
guard let iconImage = iconCtx.makeImage() else { fatalError("no image") }
writePNG(iconImage, to: "\(outDir)/icon-1024.png")

// 2. iconset（每个尺寸单独矢量绘制，缩小时才不糊）
let iconsetPath = "\(outDir)/AppIcon.iconset"
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for variant in variants {
    let ctx = makeContext(variant.px, variant.px)
    drawAppIcon(ctx, size: CGFloat(variant.px))
    guard let image = ctx.makeImage() else { fatalError("no image") }
    writePNG(image, to: "\(iconsetPath)/\(variant.name).png")
}

// 3. 横幅
let socialCtx = makeContext(1280, 640)
drawSocial(socialCtx, width: 1280, height: 640)
guard let socialImage = socialCtx.makeImage() else { fatalError("no image") }
writePNG(socialImage, to: "\(outDir)/social-preview.png")

print("done: \(outDir)")
