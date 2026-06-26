import SwiftUI

private func loadDevinAppIcon() -> NSImage? {
    loadIcon(named: "Devin")
}

private func loadDevinMenuBarIcon() -> NSImage? {
    loadIcon(named: "DevinMenuBar")
}

private func loadIcon(named name: String) -> NSImage? {
    let candidates = [
        // Packaged .app bundle
        Bundle.main.resourceURL?.appendingPathComponent("\(name).icns"),
        Bundle.main.resourceURL?.appendingPathComponent("\(name).png"),
        // Swift package root
        URL(fileURLWithPath: "Resources/\(name).icns"),
        URL(fileURLWithPath: "Resources/\(name).png"),
        URL(fileURLWithPath: "../devinbar-swift/Resources/\(name).icns"),
        URL(fileURLWithPath: "../devinbar-swift/Resources/\(name).png"),
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
    if let image = loadDevinMenuBarIcon() {
        let scaled = resizedImage(image, size: NSSize(width: size, height: size))
        scaled.isTemplate = true
        return scaled
    }
    return fallbackMenuBarIcon(size: size)
}

func devinAppIcon(size: CGFloat = 128) -> NSImage {
    if let devin = loadDevinAppIcon() {
        return resizedImage(devin, size: NSSize(width: size, height: size))
    }
    return fallbackAppIcon(size: size)
}

private func fallbackMenuBarIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let font = NSFont.systemFont(ofSize: size * 0.65, weight: .semibold)
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
    image.isTemplate = true
    return image
}

private func fallbackAppIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
    path.addClip()

    NSColor.black.setFill()
    rect.fill()

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
