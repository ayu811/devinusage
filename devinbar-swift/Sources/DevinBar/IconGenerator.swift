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
    if let devin = loadDevinIcon(),
       let template = extractForegroundTemplate(from: devin, size: size) {
        return template
    }
    return fallbackMenuBarIcon(size: size)
}

func devinAppIcon(size: CGFloat = 128) -> NSImage {
    if let devin = loadDevinIcon() {
        return resizedImage(devin, size: NSSize(width: size, height: size))
    }
    return fallbackAppIcon(size: size)
}

private func extractForegroundTemplate(from image: NSImage, size: CGFloat) -> NSImage? {
    // Supersample to avoid jagged edges: render at 4x, extract the symbol, then scale down.
    let scale: CGFloat = 4
    let superSize = size * scale
    let scaled = resizedImage(image, size: NSSize(width: superSize, height: superSize))
    guard let cgImage = scaled.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    let width = Int(superSize)
    let height = Int(superSize)
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let bitsPerComponent = 8
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: superSize, height: superSize))

    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * bytesPerPixel
            let r = CGFloat(pixels[index]) / 255.0
            let g = CGFloat(pixels[index + 1]) / 255.0
            let b = CGFloat(pixels[index + 2]) / 255.0
            let a = CGFloat(pixels[index + 3]) / 255.0

            // The foreground symbol is bright white; the background is a dark gradient.
            let brightness = max(r, g, b)
            let threshold: CGFloat = 0.78

            if a > 0.1 && brightness > threshold {
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = 255
            } else {
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = 0
            }
        }
    }

    guard let newCGImage = context.makeImage() else {
        return nil
    }

    let extracted = NSImage(cgImage: newCGImage, size: NSSize(width: superSize, height: superSize))

    // Scale down to target size with high-quality interpolation
    let final = NSImage(size: NSSize(width: size, height: size))
    final.lockFocus()
    defer { final.unlockFocus() }
    let ctx = NSGraphicsContext.current?.cgContext
    ctx?.interpolationQuality = .high
    extracted.draw(in: NSRect(origin: .zero, size: NSSize(width: size, height: size)),
                   from: NSRect(origin: .zero, size: NSSize(width: superSize, height: superSize)),
                   operation: .sourceOver,
                   fraction: 1.0)
    final.isTemplate = true
    return final
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
