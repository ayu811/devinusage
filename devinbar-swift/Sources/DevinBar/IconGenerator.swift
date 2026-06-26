import SwiftUI

private func loadDevinIcon() -> NSImage? {
    let candidates = [
        // Packaged .app bundle
        Bundle.main.resourceURL?.appendingPathComponent("Devin.icns"),
        Bundle.main.resourceURL?.appendingPathComponent("Devin.png"),
        // Swift package root
        URL(fileURLWithPath: "Resources/Devin.icns"),
        URL(fileURLWithPath: "Resources/Devin.png"),
        URL(fileURLWithPath: "../devinbar-swift/Resources/Devin.icns"),
        URL(fileURLWithPath: "../devinbar-swift/Resources/Devin.png"),
    ].compactMap { $0 }

    for url in candidates {
        if FileManager.default.fileExists(atPath: url.path),
           let image = NSImage(contentsOf: url) {
            return image
        }
    }
    return nil
}

private func resizedImage(_ image: NSImage, size: NSSize) -> NSImage {
    let newImage = NSImage(size: size)
    newImage.lockFocus()
    defer { newImage.unlockFocus() }

    let ctx = NSGraphicsContext.current?.cgContext
    ctx?.interpolationQuality = .high
    image.draw(in: NSRect(origin: .zero, size: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .sourceOver,
               fraction: 1.0)
    return newImage
}

func devinMenuBarIcon(size: CGFloat = 18) -> NSImage {
    if let devin = loadDevinIcon() {
        let scaled = resizedImage(devin, size: NSSize(width: size, height: size))
        scaled.isTemplate = false
        return scaled
    }
    return fallbackMenuBarIcon(size: size)
}

func devinAppIcon(size: CGFloat = 128) -> NSImage {
    if let devin = loadDevinIcon() {
        return resizedImage(devin, size: NSSize(width: size, height: size))
    }
    return fallbackAppIcon(size: size)
}

private func fallbackMenuBarIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let context = NSGraphicsContext.current?.cgContext
    let center = CGPoint(x: size / 2, y: size / 2)
    let radius = size / 2 - 1
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor.systemIndigo.cgColor, NSColor.purple.cgColor] as CFArray,
        locations: [0, 1]
    )
    context?.drawRadialGradient(
        gradient!,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: .drawsBeforeStartLocation
    )

    let font = NSFont.systemFont(ofSize: size * 0.65, weight: .bold)
    let text = NSAttributedString(
        string: "D",
        attributes: [
            .font: font,
            .foregroundColor: NSColor.white
        ]
    )
    let textSize = text.size()
    text.draw(in: NSRect(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 - 1,
        width: textSize.width,
        height: textSize.height
    ))
    image.isTemplate = false
    return image
}

private func fallbackAppIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
    path.addClip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(red: 0.35, green: 0.35, blue: 0.95, alpha: 1.0).cgColor,
            NSColor(red: 0.55, green: 0.25, blue: 0.85, alpha: 1.0).cgColor
        ] as CFArray,
        locations: [0, 1]
    )
    NSGraphicsContext.current?.cgContext.drawLinearGradient(
        gradient!,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )

    let font = NSFont.systemFont(ofSize: size * 0.55, weight: .bold)
    let text = NSAttributedString(
        string: "D",
        attributes: [
            .font: font,
            .foregroundColor: NSColor.white
        ]
    )
    let textSize = text.size()
    text.draw(in: NSRect(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 - size * 0.02,
        width: textSize.width,
        height: textSize.height
    ))
    image.isTemplate = false
    return image
}
