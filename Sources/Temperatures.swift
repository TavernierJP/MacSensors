import Foundation
import Darwin

enum TemperatureGroup: String, Codable, CaseIterable {
    case summary = "Synthèses"
    case cpu = "Processeur"
    case gpu = "Processeur graphique"
    case battery = "Batterie"
    case storage = "Stockage"
    case soc = "Puce et alimentation"
    case other = "Autres relevés"
}

struct TemperatureSensor: Codable, Equatable {
    let id: String
    let name: String
    let shortName: String
    let group: TemperatureGroup
    let source: String
    // A numeric SMC value is not sufficient evidence of a temperature.
    var isIdentified: Bool { source == "HID" || source == "Calcul" || group != .other }
}

struct TemperatureReading: Codable {
    let sensor: TemperatureSensor
    var celsius: Double?
    var measuredAt: Date?
    func formatted(fahrenheit: Bool = false) -> String {
        if sensor.isIdentified { return TemperatureCodec.string(celsius, fahrenheit: fahrenheit) }
        guard let value = celsius else { return "—" }
        return String(format: "%.1f", locale: Locale(identifier: "fr_FR"), value) + " [brut]"
    }
}

struct TemperatureSnapshot: Codable {
    var date = Date()
    var readings: [TemperatureReading] = []
    var diagnostic: String? = "Recherche des sondes…"
    var channelCount: Int { readings.filter { $0.sensor.source != "Calcul" }.count }
    func visibleReadings(includeUnidentified: Bool) -> [TemperatureReading] {
        readings.filter { includeUnidentified || $0.sensor.isIdentified }
    }

    func resolve(_ selected: [String]) -> [TemperatureReading] {
        var resolved: [TemperatureReading] = []
        for id in selected {
            if id == "auto" {
                let preferred = ["smc:TCMb", "smc:TCMz", "cpu.average", "soc.average", "gpu.average"]
                let ranked = preferred.compactMap { key in readings.first { $0.sensor.id == key } }
                let match = ranked.first { $0.celsius != nil } ?? readings.first { $0.sensor.isIdentified && $0.celsius != nil }
                    ?? ranked.first ?? readings.first { $0.sensor.isIdentified }
                if let match = match, !resolved.contains(where: { $0.sensor.id == match.sensor.id }) { resolved.append(match) }
            } else if let reading = readings.first(where: { $0.sensor.id == id }), !resolved.contains(where: { $0.sensor.id == id }) {
                resolved.append(reading)
            } else if !readings.contains(where: { $0.sensor.id == id }) {
                // Retain the user's choice when a sensor temporarily disappears.
                resolved.append(TemperatureReading(sensor: TemperatureSensor(id: id, name: "Sonde indisponible", shortName: "T°", group: .other, source: ""), celsius: nil))
            }
        }
        return resolved
    }
}

enum TemperatureCodec {
    static func valid(_ value: Double) -> Double? {
        // Unpowered Apple Silicon clusters commonly return negative/zero sentinels.
        value.isFinite && value > 0 && value <= 130 ? value : nil
    }
    static func decode(type: String, bytes: [UInt8]) -> Double? {
        let raw: Double
        switch type {
        case "flt " where bytes.count >= 4:
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            raw = Double(Float(bitPattern: bits))
        case "sp78" where bytes.count >= 2:
            raw = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "fp88" where bytes.count >= 2:
            raw = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 256
        default: return nil
        }
        return valid(raw)
    }
    static func string(_ celsius: Double?, fahrenheit: Bool = false) -> String {
        guard let value = celsius else { return "—" }
        let degrees = fahrenheit ? value * 9 / 5 + 32 : value
        return String(format: "%.1f", locale: Locale(identifier: "fr_FR"), degrees) + (fahrenheit ? " °F" : " °C")
    }
    static func fourCC(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    static func keyString(_ code: UInt32) -> String {
        String(bytes: [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)], encoding: .ascii) ?? ""
    }
}

enum SensorCatalog {
    // Community catalogs disagree on Tf* on M3. Leave that family raw rather
    // than assigning CPU/GPU core names. Prefer the CPU-die aggregate and the
    // documented Tp/Te/Tg families; labels denote zones, never physical cores.
    static let m3ProbeKeys = ["Te05", "Te0L", "Te0P", "Te0S", "Tp05", "Tp0D", "Tp0L", "Tp0b", "Tp0h", "Tp0n", "Tp1F", "Tp1R", "Tg05", "Tg0D", "Tg0L"]

    static func smc(_ key: String, m3: Bool) -> TemperatureSensor {
        var name = "Relevé SMC brut · \(key)"
        var short = key
        var group: TemperatureGroup = .other
        if ["TCMb", "TCMz"].contains(key) {
            name = "Température CPU · \(key)"; short = key == "TCMb" ? "CPU°" : "CPU°2"; group = .summary
        } else if m3 && (key.hasPrefix("Tp") || key.hasPrefix("Te")) {
            name = "CPU · zone \(key)"; group = .cpu
        } else if m3 && key.hasPrefix("Tg") {
            name = "GPU · zone \(key)"; group = .gpu
        } else if ["TB0T", "TB1T", "TB2T"].contains(key) {
            name = "Batterie (\(key))"; short = "BAT"; group = .battery
        }
        return TemperatureSensor(id: "smc:" + key, name: name, shortName: short, group: group, source: "SMC")
    }

    static func hid(_ label: String, occurrence: Int = 0) -> TemperatureSensor {
        let lower = label.lowercased()
        let number = label.range(of: "[0-9]+$", options: .regularExpression).map { String(label[$0]) } ?? ""
        let group: TemperatureGroup
        var short: String
        if lower.contains("pacc") || lower.contains("eacc") { group = .cpu; short = (lower.contains("pacc") ? "P" : "E") + number }
        else if lower.contains("gpu") { group = .gpu; short = "GPU" + number }
        else if lower.contains("battery") { group = .battery; short = "BAT" }
        else if lower.contains("nand") { group = .storage; short = "SSD" + number }
        else if lower.contains("pmu") || lower.contains("soc") { group = .soc; short = (lower.contains("tdie") ? "Die" : lower.contains("tdev") ? "Dev" : "SoC") + number }
        else { group = .other; short = "T°" }
        let suffix = occurrence > 0 ? " #\(occurrence + 1)" : ""
        if occurrence > 0 { short += ".\(occurrence + 1)" }
        return TemperatureSensor(id: "hid:" + label + suffix, name: label + suffix, shortName: short, group: group, source: "HID")
    }

    static func summaries(_ readings: [TemperatureReading]) -> [TemperatureReading] {
        var result: [TemperatureReading] = []
        for (group, id, label, short) in [(TemperatureGroup.cpu, "cpu", "CPU", "CPU°"), (.gpu, "gpu", "GPU", "GPU°"), (.soc, "soc", "SoC / PMU", "SoC°")] {
            let members = readings.filter { $0.sensor.group == group && $0.sensor.source != "Calcul" }
            guard !members.isEmpty else { continue }
            // Prefer the curated SMC zones; do not double-count duplicate HID paths.
            let smc = members.filter { $0.sensor.source == "SMC" }
            let values = (smc.isEmpty ? members : smc).compactMap { $0.celsius }.compactMap(TemperatureCodec.valid)
            for (kind, name) in [("average", "moyenne"), ("maximum", "maximum")] {
                let value: Double? = values.isEmpty ? nil : kind == "average" ? values.reduce(0, +) / Double(values.count) : values.max()
                result.append(TemperatureReading(sensor: TemperatureSensor(id: "\(id).\(kind)", name: "\(label) · \(name) des relevés disponibles", shortName: short + (kind == "maximum" ? "↑" : ""), group: .summary, source: "Calcul"), celsius: value, measuredAt: value == nil ? nil : Date()))
            }
        }
        return result
    }
}

private final class SMCReader {
    private var connection: UInt32 = 0
    private var information: [String: (UInt32, String)] = [:]
    private(set) var diagnostic = "SMC non initialisé"
    deinit { ms_smc_close(connection) }
    func open() -> Bool {
        if connection != 0 { return true }
        let code = ms_smc_open(&connection)
        diagnostic = code == 0 ? "SMC connecté" : String(format: "SMC inaccessible (0x%08x)", UInt32(bitPattern: code))
        return code == 0 && connection != 0
    }
    func info(_ key: String) -> (UInt32, String)? {
        if let cached = information[key] { return cached }
        var size: UInt32 = 0, type: UInt32 = 0
        guard ms_smc_info(connection, TemperatureCodec.fourCC(key), &size, &type) == 0, size > 0, size <= 32 else { return nil }
        let metadata = (size, TemperatureCodec.keyString(type))
        information[key] = metadata
        return metadata
    }
    func bytes(_ key: String) -> (String, [UInt8])? {
        guard let (size, type) = info(key) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard ms_smc_read(connection, TemperatureCodec.fourCC(key), size, &bytes) == 0 else { return nil }
        return (type, Array(bytes.prefix(Int(size))))
    }
    func temperature(_ key: String) -> Double? {
        guard let (type, bytes) = bytes(key) else { return nil }
        return TemperatureCodec.decode(type: type, bytes: bytes)
    }
    func temperatureKeys() -> [String] {
        guard open(), let (_, bytes) = bytes("#KEY"), bytes.count >= 4 else { return [] }
        let count = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count > 0 && count <= 16_384 else { return [] }
        var keys: [String] = []
        for index in 0..<count {
            var code: UInt32 = 0
            guard ms_smc_key(connection, index, &code) == 0 else { continue }
            let key = TemperatureCodec.keyString(code)
            guard key.count == 4, key.hasPrefix("T"), !key.hasPrefix("Ta"),
                  let (_, type) = info(key), ["flt ", "sp78", "fp88"].contains(type) else { continue }
            keys.append(key)
        }
        return keys.sorted()
    }
}

final class TemperatureReader {
    private var smc = SMCReader()
    private var hid: UnsafeMutableRawPointer?
    private var channels: [String: (key: String?, hidIndex: Int?)] = [:]
    private(set) var latest = TemperatureSnapshot()
    private var hasDiscovered = false
    deinit { if let hid = hid { ms_hid_close(hid) } }

    private var isM3: Bool {
        for name in ["machdep.cpu.brand_string", "hw.model"] {
            var length = 0
            guard sysctlbyname(name, nil, &length, nil, 0) == 0, length > 0, length < 1024 else { continue }
            var value = [CChar](repeating: 0, count: length)
            if sysctlbyname(name, &value, &length, nil, 0) == 0 {
                let text = String(cString: value)
                if text.contains("M3") || text.hasPrefix("Mac15,") { return true }
            }
        }
        return false
    }

    func discover() -> TemperatureSnapshot {
        channels.removeAll()
        smc = SMCReader()
        if let hid = hid { ms_hid_close(hid) }; hid = ms_hid_open()
        var readings: [TemperatureReading] = []
        let m3 = isM3
        if smc.open() {
            var keys = Set(smc.temperatureKeys())
            // Key enumeration is not available on every firmware. Probe the bounded
            // M3 catalog as well, including zones that are asleep during discovery.
            if m3 { keys.formUnion(SensorCatalog.m3ProbeKeys) }
            keys.formUnion(["TCMb", "TCMz", "TB0T", "TB1T", "TB2T"])
            for key in keys.sorted() {
                guard smc.info(key) != nil else { continue }
                let descriptor = SensorCatalog.smc(key, m3: m3)
                let value = smc.temperature(key)
                guard value != nil || descriptor.group == .cpu || descriptor.group == .gpu else { continue }
                readings.append(TemperatureReading(sensor: descriptor, celsius: value, measuredAt: value == nil ? nil : Date()))
                channels[descriptor.id] = (key, nil)
            }
        }
        var duplicates: [String: Int] = [:]
        if let hid = hid {
            for index in 0..<min(Int(ms_hid_count(hid)), 1024) {
                var label = [CChar](repeating: 0, count: 512)
                guard ms_hid_label(hid, index, &label, label.count) != 0 else { continue }
                let product = String(cString: label)
                let descriptor = SensorCatalog.hid(product, occurrence: duplicates[product, default: 0])
                duplicates[product, default: 0] += 1
                let value = readHID(index)
                readings.append(TemperatureReading(sensor: descriptor, celsius: value, measuredAt: value == nil ? nil : Date()))
                channels[descriptor.id] = (nil, index)
            }
        }
        readings.sort { $0.sensor.name.localizedStandardCompare($1.sensor.name) == .orderedAscending }
        latest = TemperatureSnapshot(date: Date(), readings: SensorCatalog.summaries(readings) + readings,
                                     diagnostic: readings.isEmpty ? "\(smc.diagnostic). Aucun relevé HID accessible." : nil)
        hasDiscovered = true
        return latest
    }

    func sample(selected: [String], includeAll: Bool = false, includeUnidentified: Bool = false) -> TemperatureSnapshot {
        if !hasDiscovered { return discover() }
        let selectedIDs = Set(latest.resolve(selected).map { $0.sensor.id })
        var required = selectedIDs
        let dependencies: [(String, TemperatureGroup)] = [("cpu.", .cpu), ("gpu.", .gpu), ("soc.", .soc)]
        for (prefix, group) in dependencies where selectedIDs.contains(where: { $0.hasPrefix(prefix) }) {
            let members = latest.readings.filter { $0.sensor.group == group && $0.sensor.source != "Calcul" }
            let smc = members.filter { $0.sensor.source == "SMC" }
            required.formUnion((smc.isEmpty ? members : smc).map { $0.sensor.id })
        }
        var physical = latest.readings.filter { $0.sensor.source != "Calcul" }
        for index in physical.indices where required.contains(physical[index].sensor.id) || (includeAll && (includeUnidentified || physical[index].sensor.isIdentified)) {
            guard let channel = channels[physical[index].sensor.id] else { continue }
            let value = channel.key.flatMap { smc.temperature($0) } ?? channel.hidIndex.flatMap { readHID($0) }
            physical[index].celsius = value
            physical[index].measuredAt = value == nil ? nil : Date()
        }
        latest = TemperatureSnapshot(date: Date(), readings: SensorCatalog.summaries(physical) + physical, diagnostic: latest.diagnostic)
        return latest
    }

    private func readHID(_ index: Int) -> Double? {
        guard let hid = hid else { return nil }
        var value: Double = 0
        guard ms_hid_temperature(hid, index, &value) != 0 else { return nil }
        return TemperatureCodec.valid(value)
    }
}

final class TemperatureMonitor {
    private let queue = DispatchQueue(label: "local.tavernierjp.macsensors.temperatures", qos: .utility)
    private let reader = TemperatureReader()
    private var busy = false
    private var lastPoll = Date.distantPast
    private var lastDiscovery = Date.distantPast
    private(set) var latest = TemperatureSnapshot()

    // Called on the main thread. The reader and its IOKit handles live on one serial queue.
    func poll(selected: [String], includeAll: Bool, includeUnidentified: Bool = false, forceDiscovery: Bool = false, completion: @escaping (TemperatureSnapshot) -> Void) {
        guard !busy else { return }
        if selected.isEmpty && !includeAll && !forceDiscovery { return }
        let needsDiscovery = forceDiscovery || lastDiscovery == .distantPast || (latest.readings.isEmpty && Date().timeIntervalSince(lastDiscovery) >= 60)
        guard needsDiscovery || Date().timeIntervalSince(lastPoll) >= 2 else { return }
        if !needsDiscovery && selected.isEmpty && !includeAll { return }
        busy = true
        lastPoll = Date()
        if needsDiscovery { lastDiscovery = Date() }
        queue.async { [self] in
            let snapshot = needsDiscovery ? reader.discover() : reader.sample(selected: selected, includeAll: includeAll, includeUnidentified: includeUnidentified)
            DispatchQueue.main.async { [self] in latest = snapshot; busy = false; completion(snapshot) }
        }
    }
}
