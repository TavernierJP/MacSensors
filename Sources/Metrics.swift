import Foundation
import Darwin

enum MetricsError: LocalizedError {
    case kernel(String, kern_return_t)
    var errorDescription: String? {
        switch self {
        case let .kernel(name, code): return "\(name) : erreur système \(code)"
        }
    }
}

struct CPUTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func usage(since previous: CPUTicks) -> CPUUsage? {
        // The kernel's 32-bit counters can wrap on machines with long uptimes.
        let u = Double(user &- previous.user) + Double(nice &- previous.nice)
        let s = Double(system &- previous.system)
        let i = Double(idle &- previous.idle)
        let total = u + s + i
        guard total > 0 else { return nil }
        return CPUUsage(user: 100 * u / total, system: 100 * s / total)
    }
}

struct CPUUsage: Codable {
    let user: Double
    let system: Double
    var total: Double { min(100, max(0, user + system)) }
    var idle: Double { max(0, 100 - total) }
}

enum MemoryPressure: String, Codable {
    case normal = "Normale"
    case warning = "Élevée"
    case critical = "Critique"
    case unknown = "Indisponible"
}

struct MemoryUsage: Codable {
    let physical: UInt64
    let used: UInt64
    let applications: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
    let swapUsed: UInt64?
    let pressure: MemoryPressure

    var percent: Double { physical > 0 ? 100 * Double(used) / Double(physical) : 0 }
    var available: UInt64 { physical > used ? physical - used : 0 }

    static func calculate(physical: UInt64, pageSize: UInt64, active: UInt64,
                          inactive: UInt64, wired: UInt64, compressed: UInt64,
                          purgeable: UInt64, external: UInt64,
                          swapUsed: UInt64?, pressure: MemoryPressure) -> MemoryUsage {
        // Resident app memory + wired memory + the compressor's physical pages.
        // Reclaimable file caches are excluded. Clamp independently sampled counters.
        let resident = active + inactive
        let reclaimable = external + purgeable
        let appPages = resident > reclaimable ? resident - reclaimable : 0
        let wiredBytes = min(physical, wired * pageSize)
        let compressedBytes = min(physical - wiredBytes, compressed * pageSize)
        let appBytes = min(physical - wiredBytes - compressedBytes, appPages * pageSize)
        let used = wiredBytes + compressedBytes + appBytes
        return MemoryUsage(physical: physical, used: used, applications: appBytes,
                           wired: wiredBytes, compressed: compressedBytes,
                           cached: min(physical - used, reclaimable * pageSize),
                           swapUsed: swapUsed, pressure: pressure)
    }
}

struct Snapshot: Codable {
    let date: Date
    let cpu: CPUUsage?
    let memory: MemoryUsage
}

final class MetricsReader {
    private let host = mach_host_self()
    private var previousTicks: CPUTicks?
    private var previousCPU: CPUUsage?
    private(set) var pressure: MemoryPressure = .unknown
    private var pressureSource: DispatchSourceMemoryPressure?

    init(observePressure: Bool = true) {
        if observePressure {
            let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
            source.setEventHandler { [weak self, weak source] in
                guard let flags = source?.data else { return }
                self?.pressure = flags.contains(.critical) ? .critical : flags.contains(.warning) ? .warning : .normal
            }
            source.resume()
            pressureSource = source
        }
    }

    deinit {
        pressureSource?.cancel()
        mach_port_deallocate(mach_task_self_, host)
    }

    func sample() throws -> Snapshot {
        let ticks = try readCPUTicks()
        let cpu = previousTicks.flatMap { ticks.usage(since: $0) } ?? previousCPU
        previousTicks = ticks
        previousCPU = cpu
        return Snapshot(date: Date(), cpu: cpu, memory: try readMemory())
    }

    private func readCPUTicks() throws -> CPUTicks {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw MetricsError.kernel("Processeur", result) }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                        idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private func readMemory() throws -> MemoryUsage {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw MetricsError.kernel("Mémoire", result) }
        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        let hasLevel = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0
        let currentPressure: MemoryPressure = hasLevel ? (level >= 4 ? .critical : level >= 2 ? .warning : .normal) : pressure
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        return MemoryUsage.calculate(physical: ProcessInfo.processInfo.physicalMemory,
                                    pageSize: UInt64(getpagesize()), active: UInt64(vm.active_count),
                                    inactive: UInt64(vm.inactive_count), wired: UInt64(vm.wire_count),
                                    compressed: UInt64(vm.compressor_page_count), purgeable: UInt64(vm.purgeable_count),
                                    external: UInt64(vm.external_page_count), swapUsed: hasSwap ? swap.xsu_used : nil,
                                    pressure: currentPressure)
    }
}

enum DisplayFormat {
    static func percent(_ value: Double) -> String { "\(Int(value.rounded())) %" }
    static func gigabytes(_ bytes: UInt64) -> String {
        // macOS Activity Monitor uses binary memory units labelled Go in French.
        String(format: "%.1f", locale: Locale(identifier: "fr_FR"), Double(bytes) / 1_073_741_824) + " Go"
    }
    static func memoryPair(_ memory: MemoryUsage) -> String {
        "\(gigabytes(memory.used)) / \(gigabytes(memory.physical))"
    }
}
