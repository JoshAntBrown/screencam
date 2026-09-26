import AppKit

// Draws the ScreenCam icon at 1024×1024 (bottom-left origin) and writes an .iconset.
func draw(_ ctx: CGContext) {
    let cs = CGColorSpaceCreateDeviceRGB()
    func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }
    func gradient(_ a: UInt32, _ b: UInt32) -> CGGradient {
        CGGradient(colorsSpace: cs, colors: [color(a), color(b)] as CFArray, locations: [0, 1])!
    }

    // Base tile (Apple icon grid: 824pt tile inset 100pt, with drop shadow)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(color(0x1B1E33)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    ctx.drawLinearGradient(gradient(0x2E3358, 0x121427), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Screen
    let screen = CGRect(x: 190, y: 330, width: 644, height: 430)
    let screenPath = CGPath(roundedRect: screen, cornerWidth: 44, cornerHeight: 44, transform: nil)
    ctx.saveGState()
    ctx.addPath(screenPath); ctx.clip()
    ctx.drawLinearGradient(gradient(0x5B8CFF, 0x8A5CF6), start: CGPoint(x: screen.minX, y: screen.maxY),
                           end: CGPoint(x: screen.maxX, y: screen.minY), options: [])
    // A couple of soft "window" shapes on the screen
    ctx.setFillColor(color(0xFFFFFF, 0.22))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 240, y: 520, width: 300, height: 190), cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(color(0xFFFFFF, 0.14))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 240, y: 380, width: 200, height: 110), cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(screenPath); ctx.setStrokeColor(color(0xFFFFFF, 0.35)); ctx.setLineWidth(6); ctx.strokePath()

    // Stand
    ctx.setFillColor(color(0x8E93B8))
    ctx.fill(CGRect(x: 472, y: 250, width: 80, height: 80))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 382, y: 222, width: 260, height: 40), cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.fillPath()

    // Record dot
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color(0xFF3B30, 0.8))
    ctx.setFillColor(color(0xFF3B30)); ctx.fillEllipse(in: CGRect(x: 740, y: 680, width: 56, height: 56))
    ctx.restoreGState()

    // Webcam bubble overlapping the bottom-right of the screen
    let c = CGPoint(x: 700, y: 360), r: CGFloat = 170
    let bubble = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.5))
    ctx.setFillColor(color(0xFFFFFF)); ctx.fillEllipse(in: bubble)
    ctx.restoreGState()
    let inner = bubble.insetBy(dx: 18, dy: 18)
    ctx.saveGState()
    ctx.addEllipse(in: inner); ctx.clip()
    ctx.drawLinearGradient(gradient(0xFFB36B, 0xFF6A5C), start: CGPoint(x: inner.midX, y: inner.maxY),
                           end: CGPoint(x: inner.midX, y: inner.minY), options: [])
    // Person silhouette
    ctx.setFillColor(color(0xFFFFFF, 0.95))
    ctx.fillEllipse(in: CGRect(x: c.x - 52, y: c.y - 8, width: 104, height: 104))
    ctx.fillEllipse(in: CGRect(x: c.x - 120, y: c.y - 250, width: 240, height: 230))
    ctx.restoreGState()
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
        draw(ctx)
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
