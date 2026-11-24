import Cocoa
import ServiceManagement

struct DiagnosticSnapshot: Codable {
    let metrics: Snapshot
    let temperatures: TemperatureSnapshot
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let reader = MetricsReader()
    private let thermal = TemperatureMonitor()
    private let defaults = UserDefaults.standard
    private let dashboard = DashboardView()
    private let menu = NSMenu()
    private let temperatureChoices = NSMenu()
    private let temperatureValues = NSMenu()
    private var choiceItems: [String: NSMenuItem] = [:]
    private var valueItems: [String: NSMenuItem] = [:]
    private var inventoryIDs: [String] = []
    private var inventoryDiagnostic: String?
    private var lastStatusSignature = ""
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var snapshot: Snapshot?
    private var intervalItems: [NSMenuItem] = []
    private var cpuItem: NSMenuItem!
    private var ramItem: NSMenuItem!
    private var memoryUnitItem: NSMenuItem!
    private var compactItem: NSMenuItem!
    private var fahrenheitItem: NSMenuItem!
    private var advancedItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var isMenuOpen = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var aboutWindow: NSWindow?

    private var interval: Double {
        let stored = defaults.double(forKey: "refreshInterval")
        return [1.0, 2.0, 5.0].contains(stored) ? stored : 1
    }
    private var selectedIDs: [String] { defaults.stringArray(forKey: "temperatures") ?? ["auto"] }
    private var fahrenheit: Bool { defaults.bool(forKey: "fahrenheit") }
    private var showUnidentified: Bool { defaults.bool(forKey: "showUnidentified") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        defaults.register(defaults: ["showCPU": true, "showRAM": true, "compact": true])
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "MacSensorsStatusItem"
        statusItem.isVisible = true
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.setAccessibilityLabel(AppIdentity.name)
        buildMenu()
        statusItem.menu = menu
        refresh(); pollTemperatures(forceDiscovery: true); restartTimer()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.timer?.invalidate() })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh(); self?.restartTimer(); self?.pollTemperatures(forceDiscovery: true)
        })
        if let index = CommandLine.arguments.firstIndex(of: "--ui-check"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try ViewRenderer.png(dashboard, to: directory.appendingPathComponent("preview-dark.png"), dark: true)
                    try ViewRenderer.png(AboutView(), to: directory.appendingPathComponent("about-dark.png"), dark: true)
                    let report: [String: Any] = ["statusItemVisible": statusItem.isVisible, "menuItems": menu.items.count,
                                                "cpuMeasured": snapshot?.cpu != nil, "temperatureChannels": thermal.latest.channelCount]
                    try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted).write(to: directory.appendingPathComponent("ui-check.json"))
                } catch { try? error.localizedDescription.write(to: directory.appendingPathComponent("ui-error.txt"), atomically: true, encoding: .utf8) }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.isVisible = true; statusItem?.button?.performClick(nil); return false
    }

    @discardableResult private func item(_ title: String, action: Selector?, into target: NSMenu? = nil) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: "")
        value.target = self; (target ?? menu).addItem(value); return value
    }
    private func submenu(_ title: String, parent: NSMenu) -> NSMenu {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let child = NSMenu(); child.autoenablesItems = false; row.submenu = child; parent.addItem(row); return child
    }
    private func buildMenu() {
        menu.delegate = self; menu.autoenablesItems = false
        let detail = NSMenuItem(); detail.view = dashboard; menu.addItem(detail)
        let allTemperatures = NSMenuItem(title: "Toutes les températures", action: nil, keyEquivalent: "")
        temperatureValues.autoenablesItems = false; allTemperatures.submenu = temperatureValues; menu.addItem(allTemperatures)
        menu.addItem(.separator())
        item("Ouvrir le Moniteur d’activité", action: #selector(openActivityMonitor))
        let preferences = submenu("Préférences", parent: menu)
        cpuItem = item("Afficher l’utilisation CPU", action: #selector(toggleCPU), into: preferences)
        ramItem = item("Afficher l’utilisation RAM", action: #selector(toggleRAM), into: preferences)
        let temperatureRow = NSMenuItem(title: "Températures dans la barre de menus", action: nil, keyEquivalent: "")
        temperatureChoices.autoenablesItems = false; temperatureRow.submenu = temperatureChoices; preferences.addItem(temperatureRow)
        preferences.addItem(.separator())
        memoryUnitItem = item("Afficher la RAM en Go", action: #selector(toggleMemoryUnits), into: preferences)
        compactItem = item("Affichage compact sur deux lignes", action: #selector(toggleCompact), into: preferences)
        fahrenheitItem = item("Températures en Fahrenheit", action: #selector(toggleFahrenheit), into: preferences)
        advancedItem = item("Afficher les relevés SMC non identifiés (avancé)", action: #selector(toggleAdvanced), into: preferences)
        preferences.addItem(.separator())
        for seconds in [1, 2, 5] {
            let i = item("Actualiser toutes les \(seconds) s", action: #selector(changeInterval(_:)), into: preferences)
            i.tag = seconds; intervalItems.append(i)
        }
        item("Rechercher les sondes à nouveau", action: #selector(rescan), into: preferences)
        menu.addItem(.separator())
        loginItem = item("Ouvrir à l’ouverture de session", action: #selector(toggleLogin))
        item("À propos de MacSensors", action: #selector(showAbout))
        item("Quitter MacSensors", action: #selector(quit)).keyEquivalent = "q"
        rebuildTemperatureMenus(force: true); updatePreferences()
    }

    private func rebuildTemperatureMenus(force: Bool = false) {
        let readings = thermal.latest.visibleReadings(includeUnidentified: showUnidentified)
        let ids = readings.map { $0.sensor.id }
        if force || ids != inventoryIDs || inventoryDiagnostic != thermal.latest.diagnostic {
            inventoryDiagnostic = thermal.latest.diagnostic
            inventoryIDs = ids; choiceItems.removeAll(); valueItems.removeAll()
            temperatureChoices.removeAllItems(); temperatureValues.removeAllItems()
            let auto = item("Automatique · CPU en priorité", action: #selector(toggleTemperature(_:)), into: temperatureChoices)
            auto.representedObject = "auto"; choiceItems["auto"] = auto
            item("Masquer les températures", action: #selector(hideTemperatures), into: temperatureChoices)
            temperatureChoices.addItem(.separator())
            if readings.isEmpty {
                item("Aucune sonde accessible", action: nil, into: temperatureChoices).isEnabled = false
                item(thermal.latest.diagnostic ?? "Recherche des sondes…", action: nil, into: temperatureValues).isEnabled = false
            }
            for group in TemperatureGroup.allCases {
                let members = readings.filter { $0.sensor.group == group }
                guard !members.isEmpty else { continue }
                let choices = submenu(group.rawValue, parent: temperatureChoices)
                let values = submenu(group.rawValue, parent: temperatureValues)
                for reading in members {
                    let choice = item(reading.sensor.name, action: #selector(toggleTemperature(_:)), into: choices)
                    choice.representedObject = reading.sensor.id; choiceItems[reading.sensor.id] = choice
                    let value = item(reading.sensor.name, action: nil, into: values)
                    valueItems[reading.sensor.id] = value
                }
            }
        }
        for reading in readings {
            let value = reading.formatted(fahrenheit: fahrenheit)
            let title = "\(reading.sensor.name) : \(value)"
            if let row = valueItems[reading.sensor.id], row.title != title { row.title = title }
        }
        updatePreferences()
    }

    func menuWillOpen(_ menu: NSMenu) { isMenuOpen = true; refresh(); pollTemperatures(); rebuildTemperatureMenus() }
    func menuDidClose(_ menu: NSMenu) { isMenuOpen = false }
    private func restartTimer() {
        timer?.invalidate()
        let value = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh(); self?.pollTemperatures() }
        value.tolerance = min(0.3, interval * 0.1); RunLoop.main.add(value, forMode: .common); timer = value
    }
    private func refresh() {
        do {
            let value = try reader.sample(); snapshot = value; dashboard.snapshot = value; dashboard.failure = nil
            if dashboard.history.last.map({ value.date.timeIntervalSince($0.0) >= 0.8 }) ?? true {
                dashboard.history.append((value.date, value.cpu?.total, value.memory.percent))
                dashboard.history.removeAll { value.date.timeIntervalSince($0.0) > 60 }
            }
        } catch { snapshot = nil; dashboard.snapshot = nil; dashboard.failure = error.localizedDescription }
        updateDisplay()
    }
    private func pollTemperatures(forceDiscovery: Bool = false) {
        thermal.poll(selected: selectedIDs, includeAll: isMenuOpen, includeUnidentified: showUnidentified, forceDiscovery: forceDiscovery) { [weak self] _ in
            self?.updateDisplay(); self?.rebuildTemperatureMenus()
        }
    }
    private func updateDisplay() {
        let chosen = thermal.latest.resolve(selectedIDs)
        dashboard.temperatures = thermal.latest; dashboard.selectedTemperatures = chosen; dashboard.fahrenheit = fahrenheit
        var values: [(String, String)] = []
        if defaults.bool(forKey: "showCPU") { values.append(("CPU", snapshot?.cpu.map { String(format: "%3.0f%%", $0.total) } ?? "—")) }
        if defaults.bool(forKey: "showRAM") {
            values.append(("RAM", snapshot.map { defaults.bool(forKey: "memoryInGB") ? DisplayFormat.gigabytes($0.memory.used) : String(format: "%3.0f%%", $0.memory.percent) } ?? "—"))
        }
        for reading in chosen { values.append((reading.sensor.shortName, reading.formatted(fahrenheit: fahrenheit))) }
        if !selectedIDs.isEmpty && chosen.isEmpty { values.append(("T°", "—")) }
        let title = values.isEmpty ? AppIdentity.name : values.map { "\($0.0) \($0.1)" }.joined(separator: "  ")
        let compact = defaults.bool(forKey: "compact") && !values.isEmpty
        let signature = "\(compact):\(title)"
        if signature != lastStatusSignature {
            if compact { statusItem.button?.title = ""; statusItem.button?.image = compactImage(values) }
            else { statusItem.button?.image = nil; statusItem.button?.title = title }
            lastStatusSignature = signature
        }
        statusItem.button?.setAccessibilityValue(title)
        var tooltip = [AppIdentity.name]
        if let s = snapshot { tooltip.append("CPU : \(s.cpu.map { DisplayFormat.percent($0.total) } ?? "—") · RAM : \(DisplayFormat.memoryPair(s.memory))") }
        tooltip += chosen.map { "\($0.sensor.name) : \($0.formatted(fahrenheit: fahrenheit))" }
        if chosen.isEmpty, let reason = thermal.latest.diagnostic { tooltip.append(reason) }
        statusItem.button?.toolTip = tooltip.joined(separator: "\n")
    }
    private func compactImage(_ values: [(String, String)]) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let labelFont = NSFont.systemFont(ofSize: 8, weight: .medium)
        let widths = values.map { max(($0.0 as NSString).size(withAttributes: [.font: labelFont]).width, ($0.1 as NSString).size(withAttributes: [.font: font]).width) + 10 }
        let image = NSImage(size: NSSize(width: widths.reduce(0, +), height: 22), flipped: false) { _ in
            var x: CGFloat = 0
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            for (index, pair) in values.enumerated() {
                (pair.0 as NSString).draw(in: NSRect(x: x, y: 12, width: widths[index], height: 10), withAttributes: [.font: labelFont, .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
                (pair.1 as NSString).draw(in: NSRect(x: x, y: 0, width: widths[index], height: 12), withAttributes: [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
                x += widths[index]
            }
            return true
        }
        image.isTemplate = true; return image
    }
    private func updatePreferences() {
        cpuItem?.state = defaults.bool(forKey: "showCPU") ? .on : .off
        ramItem?.state = defaults.bool(forKey: "showRAM") ? .on : .off
        memoryUnitItem?.state = defaults.bool(forKey: "memoryInGB") ? .on : .off
        compactItem?.state = defaults.bool(forKey: "compact") ? .on : .off
        fahrenheitItem?.state = fahrenheit ? .on : .off
        advancedItem?.state = showUnidentified ? .on : .off
        for row in intervalItems { row.state = Double(row.tag) == interval ? .on : .off }
        for (id, row) in choiceItems { row.state = selectedIDs.contains(id) ? .on : .off }
        if isMenuOpen { loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    }
    private func changed() { updatePreferences(); updateDisplay(); pollTemperatures() }
    @objc private func toggleCPU() { defaults.set(!defaults.bool(forKey: "showCPU"), forKey: "showCPU"); changed() }
    @objc private func toggleRAM() { defaults.set(!defaults.bool(forKey: "showRAM"), forKey: "showRAM"); changed() }
    @objc private func toggleMemoryUnits() { defaults.set(!defaults.bool(forKey: "memoryInGB"), forKey: "memoryInGB"); changed() }
    @objc private func toggleCompact() { defaults.set(!defaults.bool(forKey: "compact"), forKey: "compact"); changed() }
    @objc private func toggleFahrenheit() { defaults.set(!fahrenheit, forKey: "fahrenheit"); changed() }
    @objc private func toggleAdvanced() { defaults.set(!showUnidentified, forKey: "showUnidentified"); rebuildTemperatureMenus(force: true); changed() }
    @objc private func toggleTemperature(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var selected = selectedIDs
        if id == "auto" { selected = selected.contains(id) ? [] : [id] }
        else { selected.removeAll { $0 == "auto" }; if selected.contains(id) { selected.removeAll { $0 == id } } else { selected.append(id) } }
        defaults.set(selected, forKey: "temperatures"); changed()
    }
    @objc private func hideTemperatures() { defaults.set([String](), forKey: "temperatures"); changed() }
    @objc private func changeInterval(_ sender: NSMenuItem) { defaults.set(Double(sender.tag), forKey: "refreshInterval"); restartTimer(); updatePreferences() }
    @objc private func rescan() { pollTemperatures(forceDiscovery: true) }
    @objc private func toggleLogin() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") || Bundle.main.bundleURL.path.hasPrefix(NSHomeDirectory() + "/Applications/") else {
            alert("Installez d’abord MacSensors", "Glissez MacSensors dans Applications avant d’activer l’ouverture à la connexion."); return
        }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register(); if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() } }
            updatePreferences()
        } catch { alert("Ouverture à la connexion", error.localizedDescription) }
    }
    @objc private func openActivityMonitor() { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"), configuration: .init()) { _, _ in } }
    @objc private func showAbout() {
        if aboutWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 310), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "À propos de MacSensors"; window.contentView = AboutView(); window.isReleasedWhenClosed = false
            window.center(); aboutWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); aboutWindow?.makeKeyAndOrderFront(nil)
    }
    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let value = NSAlert(); value.messageText = title; value.informativeText = message; value.addButton(withTitle: "OK"); value.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--sample") || CommandLine.arguments.contains("--sensors") {
    let sensors = TemperatureReader()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
    do {
        let temperature = sensors.discover()
        if CommandLine.arguments.contains("--sensors") { print(String(decoding: try encoder.encode(temperature), as: UTF8.self)) }
        else {
            let reader = MetricsReader(observePressure: false); _ = try reader.sample(); Thread.sleep(forTimeInterval: 1)
            let value = DiagnosticSnapshot(metrics: try reader.sample(), temperatures: temperature)
            print(String(decoding: try encoder.encode(value), as: UTF8.self))
        }
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if let flag = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > flag + 1 {
    do {
        let dark = CommandLine.arguments.contains("--dark")
        let path = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
        if CommandLine.arguments.contains("--about") { try ViewRenderer.png(AboutView(), to: path, dark: dark) }
        else {
            let dashboard = DashboardView(); let reader = MetricsReader(observePressure: false)
            let sensors = TemperatureReader(); let temperature = sensors.discover()
            dashboard.temperatures = temperature; dashboard.selectedTemperatures = temperature.resolve(["auto"])
            _ = try reader.sample()
            for _ in 0..<12 { Thread.sleep(forTimeInterval: 0.12); let value = try reader.sample(); dashboard.snapshot = value; dashboard.history.append((value.date, value.cpu?.total, value.memory.percent)) }
            try ViewRenderer.png(dashboard, to: path, dark: dark)
        }
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
