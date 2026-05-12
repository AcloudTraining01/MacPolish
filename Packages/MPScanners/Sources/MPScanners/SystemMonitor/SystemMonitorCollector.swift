import Foundation
import Darwin
import MPCore

public struct SystemSnapshot: Sendable {
    public let timestamp: Date
    public let cpuUserPercent: Double
    public let cpuSystemPercent: Double
    public let cpuIdlePercent: Double
    public let memoryUsedBytes: UInt64
    public let memoryTotalBytes: UInt64
    public let memoryPressurePercent: Double

    public var cpuBusyPercent: Double { cpuUserPercent + cpuSystemPercent }

    public init(
        timestamp: Date = .now,
        cpuUserPercent: Double,
        cpuSystemPercent: Double,
        cpuIdlePercent: Double,
        memoryUsedBytes: UInt64,
        memoryTotalBytes: UInt64,
        memoryPressurePercent: Double
    ) {
        self.timestamp = timestamp
        self.cpuUserPercent = cpuUserPercent
        self.cpuSystemPercent = cpuSystemPercent
        self.cpuIdlePercent = cpuIdlePercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryPressurePercent = memoryPressurePercent
    }
}

public actor SystemMonitorCollector: MPCore.Scanner {
    public let category: ScanCategory = .systemMonitor
    private var currentResult: ScanResult?
    private var isCancelled = false
    private var lastCPUTicks: CPUTicks?

    private struct CPUTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
    }

    public init() {}

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        // Scanner conformance: a one-shot snapshot. The live polling happens via
        // `snapshotStream()` which the view drives directly.
        isCancelled = false
        currentResult = nil
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(ScanProgress(category: category, phase: .preparing))
                _ = readCPU()
                try? await Task.sleep(nanoseconds: 200_000_000)
                let snap = sampleOnce()
                let item = ScanItem(
                    path: URL(fileURLWithPath: "/dev/null"),
                    name: "CPU \(Int(snap.cpuBusyPercent))% — Memory \(Int(snap.memoryPressurePercent))%",
                    size: 0,
                    category: category,
                    riskLevel: .safe
                )
                currentResult = ScanResult(category: category, items: [item], totalSize: 0, scanDuration: 0)
                continuation.yield(ScanProgress(category: category, phase: .complete, itemsFound: 1))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func snapshotStream(intervalSeconds: Double = 1.0) -> AsyncStream<SystemSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                _ = readCPU()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                    if Task.isCancelled { break }
                    let snap = sampleOnce()
                    continuation.yield(snap)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() {
        currentResult = nil
        isCancelled = false
        lastCPUTicks = nil
    }

    public func sampleOnce() -> SystemSnapshot {
        let cpuPercent = sampleCPU()
        let mem = sampleMemory()
        return SystemSnapshot(
            cpuUserPercent: cpuPercent.user,
            cpuSystemPercent: cpuPercent.system,
            cpuIdlePercent: cpuPercent.idle,
            memoryUsedBytes: mem.used,
            memoryTotalBytes: mem.total,
            memoryPressurePercent: mem.total > 0
                ? min(100.0, Double(mem.used) / Double(mem.total) * 100.0)
                : 0
        )
    }

    private func sampleCPU() -> (user: Double, system: Double, idle: Double) {
        guard let now = readCPU() else { return (0, 0, 0) }
        guard let prev = lastCPUTicks else {
            lastCPUTicks = now
            return (0, 0, 100)
        }
        lastCPUTicks = now
        let dUser = subtract(now.user, prev.user)
        let dSystem = subtract(now.system, prev.system)
        let dIdle = subtract(now.idle, prev.idle)
        let dNice = subtract(now.nice, prev.nice)
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return (0, 0, 100) }
        let userP = Double(dUser + dNice) / Double(total) * 100.0
        let sysP = Double(dSystem) / Double(total) * 100.0
        let idleP = Double(dIdle) / Double(total) * 100.0
        return (userP, sysP, idleP)
    }

    private func subtract(_ a: UInt64, _ b: UInt64) -> UInt64 {
        a >= b ? a - b : 0
    }

    private func readCPU() -> CPUTicks? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var data = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &data) { dataPtr -> kern_return_t in
            dataPtr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: UInt64(data.cpu_ticks.0),
            system: UInt64(data.cpu_ticks.1),
            idle: UInt64(data.cpu_ticks.2),
            nice: UInt64(data.cpu_ticks.3)
        )
    }

    private func sampleMemory() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { statsPtr -> kern_return_t in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }

        let pageSize = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count)
                  + UInt64(stats.inactive_count)
                  + UInt64(stats.wire_count)
                  + UInt64(stats.compressor_page_count)) * pageSize
        var total: UInt64 = 0
        var sizeOfTotal = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &sizeOfTotal, nil, 0)
        return (used, total)
    }
}
