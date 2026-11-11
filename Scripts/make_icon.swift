#!/usr/bin/env swift
//
// Regenerates AnyPaste/Resources/AppIcon.icns.
// Usage: swift Scripts/make_icon.swift
//
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let buildDir = root.appendingPathComponent("build", isDirectory: true)
let iconsetDir = buildDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let outputURL = root.appendingPathComponent("AnyPaste/Resources/AppIcon.icns")

func drawIcon(size: CGFloat) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    // Rounded square with a blue → violet gradient.
    let inset = size * 0.055
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237
    let background = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(background)
    ctx.clip()
    let colors = [
        CGColor(red: 0.16, green: 0.42, blue: 0.98, alpha: 1.0),
        CGColor(red: 0.45, green: 0.27, blue: 0.96, alpha: 1.0),
    ]
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Clipboard body.
    let bodyWidth = size * 0.46
    let bodyHeight = size * 0.55
    let bodyRect = CGRect(
        x: (size - bodyWidth) / 2,
        y: size * 0.215,
        width: bodyWidth,
        height: bodyHeight
    )
    let body = CGPath(
        roundedRect: bodyRect,
        cornerWidth: size * 0.062,
        cornerHeight: size * 0.062,
        transform: nil
    )
    ctx.addPath(body)
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.15))
    ctx.fillPath()

    ctx.addPath(body)
    ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.97))
    ctx.setLineWidth(size * 0.036)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Clip at the top.
    let clipWidth = size * 0.20
    let clipHeight = size * 0.085
    let clipRect = CGRect(
        x: (size - clipWidth) / 2,
        y: bodyRect.maxY - clipHeight * 0.55,
        width: clipWidth,
        height: clipHeight
    )
    let clip = CGPath(
        roundedRect: clipRect,
        cornerWidth: clipHeight * 0.42,
        cornerHeight: clipHeight * 0.42,
        transform: nil
    )
    ctx.addPath(clip)
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.97))
    ctx.fillPath()

    // Text lines inside the clipboard.
    let lineHeight = size * 0.052
    let lineSpacing = size * 0.105
    let lineWidths: [CGFloat] = [0.30, 0.24, 0.16]
    var lineY = bodyRect.maxY - size * 0.20
    for widthFactor in lineWidths {
        let lineRect = CGRect(
            x: bodyRect.minX + size * 0.075,
            y: lineY,
            width: size * widthFactor,
            height: lineHeight
        )
        let line = CGPath(
            roundedRect: lineRect,
            cornerWidth: lineHeight / 2,
            cornerHeight: lineHeight / 2,
            transform: nil
        )
        ctx.addPath(line)
        ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.92))
        ctx.fillPath()
        lineY -= lineSpacing
    }
}

func renderPNG(size: Int) -> Data? {
    let dimension = CGFloat(size)
    let image = NSImage(size: NSSize(width: dimension, height: dimension))
    image.lockFocus()
    drawIcon(size: dimension)
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}

let variants: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
for variant in variants {
    guard let data = renderPNG(size: variant.size) else {
        FileHandle.standardError.write(Data("failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    try data.write(to: iconsetDir.appendingPathComponent(variant.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("wrote \(outputURL.path)")
