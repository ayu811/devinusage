import SwiftUI

private func loadIcon(named name: String) -> NSImage? {
    let candidates = [
        Bundle.main.resourceURL?.appendingPathComponent("\(name).icns"),
        Bundle.main.resourceURL?.appendingPathComponent("\(name).png"),
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

func devinMenuBarIcon() -> NSImage {
    let image = loadIcon(named: "DevinMenuBar") ?? NSImage()
    image.isTemplate = true
    return image
}

func devinAppIcon(size: CGFloat = 128) -> NSImage {
    let image = loadIcon(named: "DevinBarApp") ?? loadIcon(named: "Devin") ?? NSImage()
    let scaled = NSImage(size: NSSize(width: size, height: size))
    scaled.lockFocus()
    if let context = NSGraphicsContext.current?.cgContext {
        context.interpolationQuality = .high
    }
    image.draw(in: NSRect(origin: .zero, size: scaled.size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .sourceOver,
               fraction: 1.0)
    scaled.unlockFocus()
    return scaled
}
