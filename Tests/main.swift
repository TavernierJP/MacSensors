import Foundation
import Darwin

func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fputs("FAIL: \(description)\n", stderr); exit(1) }
    print("PASS: \(description)")
}

let initial = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
let next = CPUTicks(user: 125, system: 75, idle: 900, nice: 0)
let cpu = next.usage(since: initial)!
expect(cpu.total == 50 && cpu.user == 25 && cpu.system == 25, "CPU aggregates all ticks and normalizes to 100 percent")
expect(initial.usage(since: initial) == nil, "No elapsed ticks does not invent a zero-percent measurement")
let beforeWrap = CPUTicks(user: UInt32.max - 9, system: 10, idle: 100, nice: 0)
let afterWrap = CPUTicks(user: 10, system: 10, idle: 120, nice: 0)
expect(afterWrap.usage(since: beforeWrap)!.total == 50, "32-bit tick wrap remains accurate")
let memory = MemoryUsage.calculate(physical: 1000, pageSize: 1, active: 300, inactive: 200,
                                   wired: 100, compressed: 50, purgeable: 30, external: 170,
                                   swapUsed: 0, pressure: .normal)
expect(memory.used == 450 && memory.cached == 200 && memory.percent == 45, "RAM excludes reclaimable file cache and counts compressed pages once")
expect(memory.applications + memory.wired + memory.compressed == memory.used, "Memory breakdown equals the used total")
let inconsistent = MemoryUsage.calculate(physical: 100, pageSize: 16, active: 1, inactive: 1,
                                         wired: 4, compressed: 4, purgeable: 20, external: 20,
                                         swapUsed: nil, pressure: .unknown)
expect(inconsistent.used <= inconsistent.physical && inconsistent.applications == 0,
       "Asynchronous or inconsistent kernel counters never underflow or exceed installed RAM")

expect(TemperatureCodec.decode(type: "sp78", bytes: [0x32, 0x80]) == 50.5, "SMC signed fixed-point temperature decodes to Celsius")
expect(TemperatureCodec.decode(type: "flt ", bytes: [0x00, 0x00, 0x2d, 0x42]) == 43.25, "Apple Silicon little-endian float temperature decodes correctly")
expect(TemperatureCodec.decode(type: "sp78", bytes: [0xff, 0x80]) == nil, "Negative sleeping-sensor sentinel is not shown as a temperature")
expect(TemperatureCodec.decode(type: "flt ", bytes: [0x00, 0x00, 0xc0, 0x7f]) == nil, "NaN sensor values are rejected")
expect(TemperatureCodec.valid(0) == nil && TemperatureCodec.valid(150) == nil, "Zero and out-of-range readings do not pollute averages")
expect(TemperatureCodec.decode(type: "ui32", bytes: [0, 0, 0, 42]) == nil, "Non-temperature data types are excluded")
expect(TemperatureCodec.keyString(TemperatureCodec.fourCC("Tf04")) == "Tf04", "SMC key identifiers round-trip with correct byte ordering")
expect(SensorCatalog.smc("Tp05", m3: true).group == .cpu && SensorCatalog.smc("Tg05", m3: true).group == .gpu,
       "M3 CPU and GPU zones use distinct catalog entries")
expect(SensorCatalog.smc("Tp05", m3: false).group == .other, "M3-specific labels are not silently applied to other chips")
let cpuA = TemperatureReading(sensor: SensorCatalog.smc("Tp05", m3: true), celsius: 50)
let cpuB = TemperatureReading(sensor: SensorCatalog.smc("Tp0D", m3: true), celsius: 70)
let cpuHID = TemperatureReading(sensor: SensorCatalog.hid("pACC MTR Temp Sensor1"), celsius: 100)
let gpu = TemperatureReading(sensor: SensorCatalog.smc("Tg05", m3: true), celsius: 45)
let all = [cpuA, cpuB, cpuHID, gpu]
let summaries = SensorCatalog.summaries(all)
expect(summaries.first { $0.sensor.id == "cpu.average" }?.celsius == 60, "CPU average excludes duplicate HID paths when SMC zones are available")
expect(summaries.first { $0.sensor.id == "cpu.maximum" }?.celsius == 70, "CPU maximum uses the available CPU zones only")
let catalog = TemperatureSnapshot(readings: summaries + all, diagnostic: nil)
expect(catalog.resolve(["cpu.average", gpu.sensor.id]).count == 2, "Multiple independently selected temperatures can be displayed")
expect(catalog.resolve(["cpu.average", "cpu.average"]).count == 1, "A selected sensor is not duplicated in the menu bar")
expect(catalog.resolve([]).isEmpty, "Hiding temperatures preserves an empty selection")
expect(catalog.resolve(["auto"]).first?.sensor.id == "cpu.average", "Automatic selection prefers the CPU aggregate")
expect(catalog.resolve(["smc:missing"]).first?.celsius == nil, "Missing selected sensors retain a placeholder instead of an invented value")
let asleep = SensorCatalog.summaries([TemperatureReading(sensor: cpuA.sensor, celsius: nil)])
expect(asleep.allSatisfy { $0.celsius == nil }, "All-asleep CPU zones remain unavailable instead of reporting zero degrees")
expect(SensorCatalog.hid("gas gauge battery").group == .battery && SensorCatalog.hid("NAND CH0 temp").group == .storage,
       "Explicit HID battery and NAND names receive the correct groups")
expect(SensorCatalog.hid("PMU tdie1").shortName != SensorCatalog.hid("PMU tdie2").shortName,
       "Selected PMU temperature channels have distinct compact labels")

// Regression cases from the user's MacSensors 1.1 screenshot.
let rawHot = TemperatureReading(sensor: SensorCatalog.smc("Tf06", m3: true), celsius: 83.7)
let rawConstant = TemperatureReading(sensor: SensorCatalog.smc("Tf0C", m3: true), celsius: 1)
let centralCPU = TemperatureReading(sensor: SensorCatalog.smc("TCMb", m3: true), celsius: 46.1)
let withRaw = TemperatureSnapshot(readings: [rawHot, rawConstant, centralCPU] + summaries + all, diagnostic: nil)
expect(!rawHot.sensor.isIdentified && !rawConstant.sensor.isIdentified, "Numeric SMC Tf keys are not assumed to be identified temperatures")
expect(!withRaw.visibleReadings(includeUnidentified: false).contains { $0.sensor.id == "smc:Tf06" }, "Ambiguous high raw values are hidden from the standard sensor list")
expect(withRaw.visibleReadings(includeUnidentified: true).contains { $0.sensor.id == "smc:Tf06" }, "Advanced mode retains the user's raw SMC channel")
expect(!rawHot.formatted().contains("°") && rawHot.formatted().contains("brut"), "Unidentified SMC data never receives a Celsius unit")
expect(rawHot.formatted(fahrenheit: true) == rawHot.formatted(), "Fahrenheit conversion is not applied to unknown raw data")
expect(withRaw.resolve(["auto"]).first?.sensor.id == "smc:TCMb", "Automatic selection prefers a known CPU-die channel over an arbitrary raw maximum")
expect(SensorCatalog.summaries([rawHot, rawConstant, cpuA, cpuB]).first { $0.sensor.id == "cpu.average" }?.celsius == 60, "Unknown raw channels are excluded from CPU averages")
expect(TemperatureSnapshot(readings: [rawHot], diagnostic: nil).resolve(["auto"]).isEmpty, "Automatic mode never picks an unidentified raw channel as a temperature")
expect(SensorCatalog.smc("Tf04", m3: true).group == .other, "Disputed legacy Tf CPU/GPU labels remain unconfirmed")

let reader = MetricsReader(observePressure: false)
do {
    _ = try reader.sample()
    // macOS may cache HOST_CPU_LOAD_INFO briefly; the production cadence is 1 s.
    Thread.sleep(forTimeInterval: 1.1)
    var last: Snapshot?
    for _ in 0..<4 {
        let sample = try reader.sample()
        expect(sample.memory.physical == ProcessInfo.processInfo.physicalMemory, "Live RAM matches installed physical memory")
        expect(sample.memory.used > 0 && sample.memory.percent <= 100, "Live memory measurement is within physical limits")
        expect(sample.cpu != nil && sample.cpu!.total >= 0 && sample.cpu!.total <= 100, "Live CPU sample is available and within 0–100 percent")
        last = sample
        Thread.sleep(forTimeInterval: 0.25)
    }
    print("LIVE CPU: \(DisplayFormat.percent(last!.cpu!.total)); RAM: \(DisplayFormat.memoryPair(last!.memory))")
} catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
