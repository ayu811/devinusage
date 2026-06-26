import SwiftUI

func devinMenuBarIcon(size: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let context = NSGraphicsContext.current?.cgContext

    // Gradient background circle
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor.systemIndigo.cgColor, NSColor.purple.cgColor] as CFArray,
        locations: [0, 1]
    )
    let center = CGPoint(x: size / 2, y: size / 2)
    let radius = size / 2 - 1
    context?.drawRadialGradient(
        gradient!,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: .drawsBeforeStartLocation
    )

    // White "D" letter
    let fontSize = size * 0.65
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let text = NSAttributedString(
        string: "D",
        attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: NSParagraphStyle.default
        ]
    )
    let textSize = text.size()
    let textRect = NSRect(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 - 1,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect)

    image.isTemplate = false
    return image
}

func devinAppIcon(size: CGFloat = 128) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let context = NSGraphicsContext.current?.cgContext
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
    path.addClip()

    // Gradient background
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(red: 0.35, green: 0.35, blue: 0.95, alpha: 1.0).cgColor,
            NSColor(red: 0.55, green: 0.25, blue: 0.85, alpha: 1.0).cgColor
        ] as CFArray,
        locations: [0, 1]
    )
    context?.drawLinearGradient(
        gradient!,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )

    // White "D" letter
    let fontSize = size * 0.55
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let text = NSAttributedString(
        string: "D",
        attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: NSParagraphStyle.default
        ]
    )
    let textSize = text.size()
    let textRect = NSRect(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 - size * 0.02,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect)

    image.isTemplate = false
    return image
}
