import Foundation
import IOKit
import MPCore

public struct BatterySnapshot: Sendable {
    public let cycleCount: Int
    public let designCapacityMAh: Int
    public let maxCapacityMAh: Int
    public let currentCapacityMAh: Int
    public let temperatureCelsius: Double
    public let isCharging: Bool
    public let isPluggedIn: Bool

    public var healthPercent: Double {
        guard designCapacityMAh > 0 else { return 0 }
        return min(100.0, Double(maxCapacityMAh) / Double(designCapacityMAh) * 100.0)
    }

    public var stateOfChargePercent: Double {
        guard maxCapacityMAh > 0 else { return 0 }
        return min(100.0, Double(currentCapacityMAh) / Double(maxCapacityMAh) * 100.0)
    }

    public init(
        cycleCount: Int,
        designCapacityMAh: Int,
        maxCapacityMAh: Int,
        currentCapacityMAh: Int,
        temperatureCelsius: Double,
        isCharging: Bool,
        isPluggedIn: Bool
    ) {
        self.cycleCount = cycleCount
        self.designCapacityMAh = designCapacityMAh
        self.maxCapacityMAh = maxCapacityMAh
        self.currentCapacityMAh = currentCapacityMAh
        self.temperatureCelsius = temperatureCelsius
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
    }
}

public actor BatteryReader: MPCore.Scanner {
    public let category: ScanCategory = .batteryHealth
    private var currentResult: ScanResult?
    private var snapshot: BatterySnapshot?
    private var isCancelled = false

    public init() {}

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        snapshot = nil
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(ScanProgress(category: category, phase: .preparing))
                let snap = Self.readSnapshot()
                snapshot = snap

                if let snap {
                    let summary = ScanItem(
                        path: URL(fileURLWithPath: "/AppleSmartBattery"),
                        name: "Battery — \(Int(snap.healthPercent))% health",
                        size: 0,
                        category: category,
                        riskLevel: snap.healthPercent < 80 ? .cautionary : .safe,
                        lastModified: nil,
                        explanation: "\(snap.cycleCount) cycles, \(snap.maxCapacityMAh)/\(snap.designCapacityMAh) mAh"
                    )
                    currentResult = ScanResult(
                        category: category,
                        items: [summary],
                        totalSize: 0,
                        scanDuration: 0
                    )
                    continuation.yield(ScanProgress(category: category, phase: .complete, itemsFound: 1))
                } else {
                    continuation.yield(ScanProgress(category: category, phase: .failed("No internal battery detected")))
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func currentSnapshot() -> BatterySnapshot? { snapshot }
    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() {
        currentResult = nil
        snapshot = nil
        isCancelled = false
    }

    private static func readSnapshot() -> BatterySnapshot? {
        let matching = IOServiceMatching("AppleSmartBattery") as CFDictionary
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service, &properties, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let cycleCount = (dict["CycleCount"] as? Int) ?? 0
        let designCapacity = (dict["DesignCapacity"] as? Int) ?? 0
        let maxCapacity = (dict["AppleRawMaxCapacity"] as? Int)
            ?? (dict["MaxCapacity"] as? Int) ?? 0
        let currentCapacity = (dict["AppleRawCurrentCapacity"] as? Int)
            ?? (dict["CurrentCapacity"] as? Int) ?? 0
        let temperatureRaw = (dict["Temperature"] as? Int) ?? 0
        let isCharging = (dict["IsCharging"] as? Bool) ?? false
        let isPluggedIn = (dict["ExternalConnected"] as? Bool) ?? false

        return BatterySnapshot(
            cycleCount: cycleCount,
            designCapacityMAh: designCapacity,
            maxCapacityMAh: maxCapacity,
            currentCapacityMAh: currentCapacity,
            temperatureCelsius: Double(temperatureRaw) / 100.0,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn
        )
    }
}
