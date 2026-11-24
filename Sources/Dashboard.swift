import Cocoa

final class DashboardView: NSView {
    var snapshot: Snapshot? { didSet { needsDisplay = true; updateAccessibility() } }
    var history: [(Date, Double?, Double)] = [] { didSet { needsDisplay = true } }
    var failure: String? { didSet { needsDisplay = true } }
    var temperatures = TemperatureSnapshot() { didSet { needsDisplay = true } }
    var selectedTemperatures: [TemperatureReading] = [] { didSet { needsDisplay = true; updateAccessibility() } }
    var fahrenheit = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 324, height: 432))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("MacSensors : processeur, mémoire et températures")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateAccessibility() {
        guard let s = snapshot else { return }
        let thermal = selectedTemperatures.map { "\($0.sensor.name) : \($0.formatted(fahrenheit: fahrenheit))" }.joined(separator: ". ")
        setAccessibilityValue("Processeur \(s.cpu.map { DisplayFormat.percent($0.total) } ?? "en cours de mesure"). Mémoire \(DisplayFormat.percent(s.memory.percent)), \(DisplayFormat.memoryPair(s.memory)). Pression mémoire \(s.memory.pressure.rawValue). \(thermal)")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        text("MacSensors", x: 18, y: 13, size: 13, weight: .semibold)
        text("EN DIRECT", x: 230, y: 15, size: 9, color: .secondaryLabelColor, weight: .medium)
        let cpu = snapshot?.cpu
        let memory = snapshot?.memory
        card(y: 40, height: 109)
        symbol("cpu", x: 29, y: 51, color: .systemBlue)
        text("Processeur", x: 52, y: 52, size: 12, weight: .medium)
        text(cpu.map { DisplayFormat.percent($0.total) } ?? "—", x: 205, y: 46, width: 88, size: 24, weight: .semibold, alignment: .right)
        text("\(ProcessInfo.processInfo.activeProcessorCount) cœurs · capacité totale = 100 %", x: 29, y: 74, size: 10, color: .secondaryLabelColor)
        graph(in: NSRect(x: 29, y: 96, width: 266, height: 28), color: .systemBlue, cpu: true)
        let u = cpu.map { DisplayFormat.percent($0.user) } ?? "—"
        let s = cpu.map { DisplayFormat.percent($0.system) } ?? "—"
        text("Utilisateur \(u)     Système \(s)", x: 29, y: 130, size: 10, color: .secondaryLabelColor)

        card(y: 157, height: 116)
        symbol("memorychip", x: 29, y: 168, color: .systemTeal)
        text("Mémoire RAM", x: 52, y: 169, size: 12, weight: .medium)
        text(memory.map { DisplayFormat.percent($0.percent) } ?? "—", x: 205, y: 163, width: 88, size: 24, weight: .semibold, alignment: .right)
        text(memory.map { DisplayFormat.memoryPair($0) + " utilisés" } ?? "Lecture des statistiques…", x: 29, y: 191, size: 10, color: .secondaryLabelColor)
        graph(in: NSRect(x: 29, y: 214, width: 266, height: 28), color: .systemTeal, cpu: false)
        let pressureColor: NSColor
        switch memory?.pressure ?? .unknown {
        case .normal: pressureColor = .systemGreen
        case .warning: pressureColor = .systemOrange
        case .critical: pressureColor = .systemRed
        case .unknown: pressureColor = .tertiaryLabelColor
        }
        pressureColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 29, y: 253, width: 6, height: 6)).fill()
        text("Pression mémoire : \(memory?.pressure.rawValue.lowercased() ?? "indisponible")", x: 41, y: 249, size: 10, color: .secondaryLabelColor)

        card(y: 281, height: 84)
        text("Températures", x: 29, y: 293, size: 12, weight: .medium)
        let primary = selectedTemperatures.first ?? temperatures.readings.first { $0.sensor.isIdentified && $0.celsius != nil }
        text(primary?.formatted(fahrenheit: fahrenheit) ?? "—", x: 183, y: 287, width: 110, size: 23, color: .systemOrange, weight: .semibold, alignment: .right)
        text(primary?.sensor.name ?? (temperatures.readings.isEmpty ? "Aucune sonde accessible" : "Choisir les températures dans Préférences"), x: 29, y: 319, width: 266, size: 10, color: .secondaryLabelColor)
        let extra = selectedTemperatures.dropFirst().prefix(2).map { "\($0.sensor.shortName) \($0.formatted(fahrenheit: fahrenheit))" }.joined(separator: "   ·   ")
        let subtitle = extra.isEmpty ? "\(temperatures.visibleReadings(includeUnidentified: false).filter { $0.sensor.source != "Calcul" }.count) relevés identifiés · sélection dans Préférences" : extra + (selectedTemperatures.count > 3 ? "  +\(selectedTemperatures.count - 3)" : "")
        text(subtitle, x: 29, y: 343, width: 266, size: 9, color: .secondaryLabelColor)
        text("Compressée", x: 22, y: 375, size: 10, color: .secondaryLabelColor)
        text(memory.map { DisplayFormat.gigabytes($0.compressed) } ?? "—", x: 220, y: 375, width: 81, size: 10, alignment: .right)
        text("Échange sur disque", x: 22, y: 392, size: 10, color: .secondaryLabelColor)
        text(memory?.swapUsed.map { DisplayFormat.gigabytes($0) } ?? "—", x: 220, y: 392, width: 81, size: 10, alignment: .right)
        if failure != nil {
            text("Mesure indisponible · nouvel essai automatique", x: 22, y: 411, size: 8, color: .systemOrange)
        } else {
            text("Historique : 60 s · designed by TavernierJP", x: 22, y: 411, size: 8, color: .tertiaryLabelColor)
        }
    }

    private func card(y: CGFloat, height: CGFloat) {
        NSColor.labelColor.withAlphaComponent(0.045).setFill()
        NSBezierPath(roundedRect: NSRect(x: 17, y: y, width: 290, height: height), xRadius: 9, yRadius: 9).fill()
    }

    private func symbol(_ name: String, x: CGFloat, y: CGFloat, color: NSColor) {
        color.setStroke()
        let outline = NSBezierPath(roundedRect: NSRect(x: x + 3, y: y + 3, width: name == "cpu" ? 10 : 13, height: 10), xRadius: 1.5, yRadius: 1.5)
        outline.lineWidth = 1.3
        outline.stroke()
        let pins = NSBezierPath()
        for offset in [5.0, 8.0, 11.0] {
            pins.move(to: NSPoint(x: x + offset, y: y))
            pins.line(to: NSPoint(x: x + offset, y: y + 3))
            pins.move(to: NSPoint(x: x + offset, y: y + 13))
            pins.line(to: NSPoint(x: x + offset, y: y + 16))
            if name == "cpu" {
                pins.move(to: NSPoint(x: x, y: y + offset))
                pins.line(to: NSPoint(x: x + 3, y: y + offset))
                pins.move(to: NSPoint(x: x + 13, y: y + offset))
                pins.line(to: NSPoint(x: x + 16, y: y + offset))
            }
        }
        pins.lineWidth = 1.2
        pins.stroke()
    }

    private func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat = 280,
                      size: CGFloat, color: NSColor = .labelColor, weight: NSFont.Weight = .regular,
                      alignment: NSTextAlignment = .left) {
        let p = NSMutableParagraphStyle()
        p.alignment = alignment
        p.lineBreakMode = .byTruncatingTail
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        (value as NSString).draw(in: NSRect(x: x, y: y, width: width, height: size + 7),
                                withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    }

    private func graph(in rect: NSRect, color: NSColor, cpu: Bool) {
        NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
        for t in [0.0, 0.5, 1.0] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: rect.minX, y: rect.minY + rect.height * t))
            line.line(to: NSPoint(x: rect.maxX, y: rect.minY + rect.height * t))
            line.lineWidth = 0.5
            line.stroke()
        }
        guard let newest = history.last?.0 else { return }
        let points = history.compactMap { entry -> NSPoint? in
            guard let value = cpu ? entry.1 : entry.2 else { return nil }
            let elapsed = newest.timeIntervalSince(entry.0)
            guard elapsed <= 60 else { return nil }
            return NSPoint(x: rect.maxX - rect.width * elapsed / 60,
                           y: rect.maxY - rect.height * min(100, max(0, value)) / 100)
        }
        guard let first = points.first, let last = points.last else { return }
        let line = NSBezierPath()
        line.move(to: first)
        for point in points.dropFirst() { line.line(to: point) }
        if points.count > 1 {
            let fill = line.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: last.x, y: rect.maxY))
            fill.line(to: NSPoint(x: first.x, y: rect.maxY))
            fill.close()
            color.withAlphaComponent(0.13).setFill()
            fill.fill()
            color.setStroke()
            line.lineWidth = 1.4
            line.lineJoinStyle = .round
            line.stroke()
        }
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: last.x - 1.8, y: last.y - 1.8, width: 3.6, height: 3.6)).fill()
    }

    func exportPNG(to url: URL, dark: Bool) throws {
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        context.cgContext.scaleBy(x: 2, y: 2)
        context.cgContext.translateBy(x: 0, y: bounds.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        appearance?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            draw(bounds)
        }
        NSGraphicsContext.restoreGraphicsState()
        if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: url) }
    }
}
