import Foundation
import MPCore

public actor TimeMachineScanner: MPCore.Scanner {
    public let category: ScanCategory = .timeMachine
    private var currentResult: ScanResult?
    private var isCancelled = false

    public init() {}

    public func scan() -> AsyncThrowingStream<ScanProgress, Error> {
        isCancelled = false
        currentResult = nil
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                var foundItems: [ScanItem] = []
                let totalBytes: Int64 = 0
                let startTime = Date()

                continuation.yield(ScanProgress(category: category, phase: .preparing))

                // Check if a backup is currently running
                if self.isBackupRunning() {
                    continuation.yield(ScanProgress(category: category, phase: .failed("Time Machine backup is currently in progress.")))
                    continuation.finish()
                    return
                }

                // List snapshots
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
                task.arguments = ["listlocalsnapshots", "/"]
                let pipe = Pipe()
                task.standardOutput = pipe
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        let lines = output.components(separatedBy: .newlines)
                        for line in lines {
                            guard !isCancelled else { break }
                            // tmutil listlocalsnapshots output looks like: com.apple.TimeMachine.2023-10-24-123456.local
                            if line.contains("com.apple.TimeMachine") {
                                // Extract date
                                let parts = line.components(separatedBy: ".")
                                if parts.count >= 3 {
                                    let dateStr = parts[2]
                                    
                                    // For size, tmutil doesn't give it easily. 
                                    // Finding snapshot sizes requires complicated apfs commands or delta calculations.
                                    // We will assign a placeholder size or 0 for now as it's complex to get accurately without root.
                                    let size: Int64 = 0 
                                    
                                    let item = ScanItem(
                                        path: URL(fileURLWithPath: "/.MobileBackups"), // Virtual path
                                        name: line,
                                        size: size,
                                        category: category,
                                        riskLevel: .cautionary, // It's a backup, user should be sure
                                        explanation: dateStr
                                    )
                                    foundItems.append(item)
                                }
                            }
                        }
                    }
                } catch {
                    // Ignore errors, might not have any
                }

                if !isCancelled {
                    self.currentResult = ScanResult(
                        category: category,
                        items: foundItems,
                        totalSize: totalBytes, // 0 for now
                        scanDuration: Date().timeIntervalSince(startTime)
                    )
                    continuation.yield(ScanProgress(category: category, phase: .complete, itemsFound: foundItems.count, bytesFound: totalBytes))
                }
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func isBackupRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        task.arguments = ["status"]
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains("Running = 1")
            }
        } catch {
            return false
        }
        return false
    }

    public func results() -> ScanResult? { currentResult }
    public func cancel() { isCancelled = true }
    public func reset() { currentResult = nil; isCancelled = false }
}
