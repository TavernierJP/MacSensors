import Cocoa

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let body = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 204, yRadius: 204)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.19, blue: 0.32, alpha: 1), ending: NSColor(calibratedRed: 0.10, green: 0.48, blue: 0.58, alpha: 1))!
    gradient.draw(in: body, angle: 60)
    let chip = NSBezierPath(roundedRect: NSRect(x: 295, y: 295, width: 434, height: 434), xRadius: 55, yRadius: 55)
    NSColor.white.withAlphaComponent(0.92).setStroke()
    chip.lineWidth = 24
    chip.stroke()
    for coordinate in stride(from: 370, through: 654, by: 71) {
        let c = CGFloat(coordinate)
        let pins = NSBezierPath()
        pins.move(to: NSPoint(x: c, y: 235)); pins.line(to: NSPoint(x: c, y: 295))
        pins.move(to: NSPoint(x: c, y: 729)); pins.line(to: NSPoint(x: c, y: 789))
        pins.move(to: NSPoint(x: 235, y: c)); pins.line(to: NSPoint(x: 295, y: c))
        pins.move(to: NSPoint(x: 729, y: c)); pins.line(to: NSPoint(x: 789, y: c))
        pins.lineWidth = 22
        pins.lineCapStyle = .round
        pins.stroke()
    }
    for (i, height) in [115, 205].enumerated() {
        NSColor(calibratedRed: 0.35 + Double(i) * 0.15, green: 0.95, blue: 0.84, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 373 + i * 96, y: 365, width: 66, height: height), xRadius: 15, yRadius: 15).fill()
    }
    // Temperature channel: a contrasting thermometer inside the processor icon.
    NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 578, y: 399, width: 45, height: 239), xRadius: 22, yRadius: 22).fill()
    NSBezierPath(ovalIn: NSRect(x: 556, y: 351, width: 88, height: 88)).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon render failed") }
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: folder.appendingPathComponent(name)) }
}
