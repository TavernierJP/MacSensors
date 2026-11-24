import Cocoa
import ImageIO

enum AppIdentity {
    static let name = "MacSensors"
    static let version = "1.2"
    static let credit = "designed by TavernierJP"
    static let publication = "Publié le 23 novembre 2026"
}

final class AboutView: NSView {
    override var isFlipped: Bool { true }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 350, height: 310))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("MacSensors. Version \(AppIdentity.version). \(AppIdentity.credit). \(AppIdentity.publication).")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        if let url = Bundle.main.url(forResource: "AboutIcon", withExtension: "png"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.translateBy(x: 135, y: 112)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: 80, height: 80))
            context.restoreGState()
        }
        centered(AppIdentity.name, y: 137, size: 20, weight: .bold)
        centered(AppIdentity.credit, y: 181, size: 12)
        centered("Version \(AppIdentity.version)", y: 201, size: 12, color: .secondaryLabelColor)
        centered(AppIdentity.publication, y: 235, size: 11, color: .secondaryLabelColor)
        centered("CPU · RAM · Températures", y: 271, size: 10, color: .tertiaryLabelColor)
    }
    private func centered(_ value: String, y: CGFloat, size: CGFloat, color: NSColor = .labelColor, weight: NSFont.Weight = .regular) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (value as NSString).draw(in: NSRect(x: 15, y: y, width: 320, height: size + 8),
                                withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }
}

enum ViewRenderer {
    static func png(_ view: NSView, to url: URL, dark: Bool) throws {
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let bounds = view.bounds
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        context.cgContext.scaleBy(x: 2, y: 2)
        context.cgContext.translateBy(x: 0, y: bounds.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        view.appearance?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill(); bounds.fill()
            view.draw(bounds)
        }
        NSGraphicsContext.restoreGraphicsState()
        if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: url) }
    }
}
