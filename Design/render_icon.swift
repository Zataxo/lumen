// Renders the Lumen "neural engine" app icon in all variants.
// Usage: swift render_icon.swift <output-dir>
import AppKit
import CoreGraphics
import Foundation

enum Variant: String { case light, dark, tinted, mac }

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let canvas: CGFloat = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [white, white, white, alpha])!
}

// MARK: Geometry (in a 1024 design space, centred)

let center = CGPoint(x: 512, y: 512)

func point(radius: CGFloat, degrees: CGFloat) -> CGPoint {
    let r = degrees * .pi / 180
    return CGPoint(x: center.x + radius * cos(r), y: center.y + radius * sin(r))
}

let outerNodes = (0..<8).map { point(radius: 318, degrees: 22.5 + CGFloat($0) * 45) }
let innerNodes = (0..<6).map { point(radius: 178, degrees: 90 + CGFloat($0) * 60) }

func nearestOuter(to p: CGPoint, count: Int) -> [CGPoint] {
    outerNodes.sorted { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }.prefix(count).map { $0 }
}

// MARK: Drawing helpers

func radialGlow(_ ctx: CGContext, at p: CGPoint, radius: CGFloat, colors: [CGColor], locations: [CGFloat]) {
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    ctx.drawRadialGradient(gradient, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
}

func line(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, width: CGFloat, from: CGColor, to: CGColor) {
    ctx.saveGState()
    let path = CGMutablePath()
    path.move(to: a)
    path.addLine(to: b)
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [from, to] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

/// A sphere: glow behind, then a gradient clipped to the circle with the highlight up-left.
func shadedSphere(_ ctx: CGContext, at p: CGPoint, radius: CGFloat, glow: CGColor, glowBlur: CGFloat, colors: [CGColor], locations: [CGFloat]) {
    let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: glowBlur, color: glow)
    ctx.setFillColor(colors.last!)
    ctx.fillEllipse(in: rect)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: rect)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    let highlight = CGPoint(x: p.x - radius * 0.3, y: p.y + radius * 0.3)
    ctx.drawRadialGradient(gradient, startCenter: highlight, startRadius: 0, endCenter: p, endRadius: radius, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}

func node(_ ctx: CGContext, at p: CGPoint, radius: CGFloat, glow: CGColor, core: CGColor, rim: CGColor) {
    shadedSphere(ctx, at: p, radius: radius, glow: glow, glowBlur: radius * 2.2, colors: [core, rim], locations: [0, 1])
}

func sparkle(_ ctx: CGContext, at p: CGPoint, size s: CGFloat, color c: CGColor) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: p.x, y: p.y + s))
    path.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: CGPoint(x: p.x + s * 0.12, y: p.y + s * 0.12))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: CGPoint(x: p.x + s * 0.12, y: p.y - s * 0.12))
    path.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: CGPoint(x: p.x - s * 0.12, y: p.y - s * 0.12))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: CGPoint(x: p.x - s * 0.12, y: p.y + s * 0.12))
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.8, color: c)
    ctx.addPath(path)
    ctx.setFillColor(c)
    ctx.fillPath()
    ctx.restoreGState()
}

// MARK: Layers

func drawBackground(_ ctx: CGContext, variant: Variant) {
    let rect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    switch variant {
    case .tinted:
        return // transparent: the system tints the artwork
    case .dark:
        let base = CGGradient(colorsSpace: colorSpace, colors: [color(0x0B0F24), color(0x04050C)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: canvas), end: CGPoint(x: canvas, y: 0), options: [])
        radialGlow(ctx, at: center, radius: 470, colors: [color(0x6D4CFF, 0.38), color(0x6D4CFF, 0)], locations: [0, 1])
    case .light, .mac:
        let base = CGGradient(colorsSpace: colorSpace, colors: [color(0x3A2BC4), color(0x1A1663), color(0x081530)] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: canvas), end: CGPoint(x: canvas, y: 0), options: [])
        radialGlow(ctx, at: CGPoint(x: 820, y: 180), radius: 520, colors: [color(0x06B6D4, 0.35), color(0x06B6D4, 0)], locations: [0, 1])
        radialGlow(ctx, at: center, radius: 480, colors: [color(0x8B5CF6, 0.55), color(0x8B5CF6, 0)], locations: [0, 1])
    }
    _ = rect
}

func drawNetwork(_ ctx: CGContext, variant: Variant) {
    let tinted = variant == .tinted
    let cyan = tinted ? gray(1, 0.9) : color(0x67E8F9, 0.95)
    let violet = tinted ? gray(1, 0.45) : color(0xA78BFA, 0.75)
    let faint = tinted ? gray(1, 0.22) : color(0x93C5FD, 0.28)
    let glow = tinted ? gray(1, 0.6) : color(0x22D3EE, 0.9)

    // Outer ring: a faint octagon.
    for i in outerNodes.indices {
        line(ctx, outerNodes[i], outerNodes[(i + 1) % outerNodes.count], width: 5, from: faint, to: faint)
    }

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 22, color: tinted ? gray(1, 0.3) : color(0x22D3EE, 0.55))
    // Inner → outer synapses.
    for p in innerNodes {
        for q in nearestOuter(to: p, count: 2) {
            line(ctx, p, q, width: 8, from: cyan, to: violet)
        }
    }
    // Inner ring neighbours.
    for i in innerNodes.indices {
        line(ctx, innerNodes[i], innerNodes[(i + 1) % innerNodes.count], width: 6, from: violet, to: violet)
    }
    // Core → inner spokes.
    for p in innerNodes {
        line(ctx, center, p, width: 11, from: tinted ? gray(1, 1) : color(0xE0F2FE), to: cyan)
    }
    ctx.restoreGState()

    // Nodes.
    for p in outerNodes {
        node(ctx, at: p, radius: 20, glow: glow, core: tinted ? gray(1) : color(0xFFFFFF), rim: tinted ? gray(0.85) : color(0xA78BFA))
    }
    for p in innerNodes {
        node(ctx, at: p, radius: 26, glow: glow, core: tinted ? gray(1) : color(0xFFFFFF), rim: tinted ? gray(0.9) : color(0x22D3EE))
    }

    // The luminous core.
    if !tinted {
        radialGlow(ctx, at: center, radius: 250, colors: [color(0x67E8F9, 0.55), color(0x8B5CF6, 0.25), color(0x8B5CF6, 0)], locations: [0, 0.45, 1])
    }
    shadedSphere(
        ctx, at: center, radius: 96,
        glow: tinted ? gray(1, 0.8) : color(0x67E8F9, 1), glowBlur: 80,
        colors: tinted ? [gray(1), gray(0.9)] : [color(0xFFFFFF), color(0xCFFAFE), color(0x67E8F9), color(0x6366F1)],
        locations: tinted ? [0, 1] : [0, 0.3, 0.7, 1]
    )

    // A spark of intelligence.
    sparkle(ctx, at: CGPoint(x: 742, y: 760), size: 44, color: tinted ? gray(1) : color(0xFFFFFF, 0.95))
    sparkle(ctx, at: CGPoint(x: 808, y: 690), size: 20, color: tinted ? gray(1, 0.8) : color(0xC4B5FD, 0.9))
}

// MARK: Render

func render(_ variant: Variant) -> CGImage {
    let ctx = CGContext(
        data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)

    if variant == .mac {
        // macOS icons carry their own rounded-rect body with margin and drop shadow.
        let inset: CGFloat = 100
        let body = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
        let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: gray(0, 0.38))
        ctx.addPath(shape)
        ctx.setFillColor(color(0x1A1663))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let scale = body.width / canvas
        ctx.translateBy(x: body.minX, y: body.minY)
        ctx.scaleBy(x: scale, y: scale)
        drawBackground(ctx, variant: variant)
        drawNetwork(ctx, variant: variant)
        ctx.restoreGState()

        // Subtle top highlight on the body edge.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.setStrokeColor(gray(1, 0.14))
        ctx.setLineWidth(3)
        ctx.strokePath()
        ctx.restoreGState()
    } else {
        drawBackground(ctx, variant: variant)
        drawNetwork(ctx, variant: variant)
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ name: String, opaque: Bool) throws {
    var output = image
    if opaque {
        // iOS app icons must not contain an alpha channel.
        let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        output = ctx.makeImage()!
    }
    let rep = NSBitmapImageRep(cgImage: output)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: outputDirectory.appendingPathComponent(name))
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try writePNG(render(.light), "AppIcon-iOS.png", opaque: true)
try writePNG(render(.dark), "AppIcon-iOS-Dark.png", opaque: true)
try writePNG(render(.tinted), "AppIcon-iOS-Tinted.png", opaque: false)
try writePNG(render(.mac), "AppIcon-macOS-1024.png", opaque: false)
print("rendered to \(outputDirectory.path)")
