import Foundation
import MPCore

public actor ToolExecutor {

    public struct ToolResult: Sendable {
        public let toolCallId: String
        public let name: String
        public let content: String
        public let requiresConfirmation: Bool

        public init(toolCallId: String, name: String, content: String, requiresConfirmation: Bool = false) {
            self.toolCallId = toolCallId
            self.name = name
            self.content = content
            self.requiresConfirmation = requiresConfirmation
        }
    }

    public init() {}

    public func execute(
        toolCallId: String,
        name: String,
        arguments: String,
        scanResults: [ScanCategory: ScanResult]
    ) async -> ToolResult {
        switch name {
        case "get_scan_summary":
            return getScanSummary(id: toolCallId, results: scanResults)
        case "get_disk_usage":
            return getDiskUsage(id: toolCallId)
        case "recommend_cleanup":
            return recommendCleanup(id: toolCallId, results: scanResults)
        case "start_scan":
            return startScan(id: toolCallId, arguments: arguments)
        case "clean_items":
            return cleanItems(id: toolCallId, arguments: arguments, results: scanResults)
        default:
            return ToolResult(
                toolCallId: toolCallId,
                name: name,
                content: "{\"error\": \"Unknown tool: \(name)\"}"
            )
        }
    }

    // MARK: - Read-only tools

    private func getScanSummary(
        id: String,
        results: [ScanCategory: ScanResult]
    ) -> ToolResult {
        if results.isEmpty {
            return ToolResult(
                toolCallId: id,
                name: "get_scan_summary",
                content: "{\"status\": \"no_scans\", \"message\": \"No scans have been run yet. Suggest running a Smart Scan.\"}"
            )
        }

        var categories: [[String: Any]] = []
        var grandTotal: Int64 = 0
        var grandItems = 0

        for (cat, result) in results {
            categories.append([
                "category": cat.rawValue,
                "items_found": result.items.count,
                "total_size_bytes": result.totalSize,
                "total_size_human": SizeFormatter.format(result.totalSize),
            ])
            grandTotal += result.totalSize
            grandItems += result.items.count
        }

        let summary: [String: Any] = [
            "total_items": grandItems,
            "total_size_bytes": grandTotal,
            "total_size_human": SizeFormatter.format(grandTotal),
            "categories": categories,
        ]

        let json = (try? JSONSerialization.data(withJSONObject: summary))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return ToolResult(toolCallId: id, name: "get_scan_summary", content: json)
    }

    private func getDiskUsage(id: String) -> ToolResult {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let values = try? homeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])

        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let used = total - available

        let result: [String: Any] = [
            "total_bytes": total,
            "total_human": SizeFormatter.format(total),
            "used_bytes": used,
            "used_human": SizeFormatter.format(used),
            "available_bytes": available,
            "available_human": SizeFormatter.format(available),
            "usage_percent": total > 0 ? Int(Double(used) / Double(total) * 100) : 0,
        ]

        let json = (try? JSONSerialization.data(withJSONObject: result))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return ToolResult(toolCallId: id, name: "get_disk_usage", content: json)
    }

    private func recommendCleanup(
        id: String,
        results: [ScanCategory: ScanResult]
    ) -> ToolResult {
        if results.isEmpty {
            return ToolResult(
                toolCallId: id,
                name: "recommend_cleanup",
                content: "{\"recommendations\": [], \"message\": \"Run a scan first to get recommendations.\"}"
            )
        }

        var recommendations: [[String: Any]] = []

        let sorted = results.sorted { $0.value.totalSize > $1.value.totalSize }
        for (cat, result) in sorted where !result.items.isEmpty {
            let safeItems = result.items.filter { $0.riskLevel == .safe }
            let safeSize = safeItems.reduce(0 as Int64) { $0 + $1.size }

            recommendations.append([
                "category": cat.rawValue,
                "total_items": result.items.count,
                "safe_items": safeItems.count,
                "safe_size_human": SizeFormatter.format(safeSize),
                "recommendation": safeItems.isEmpty
                    ? "Review items manually before cleaning"
                    : "Safe to clean \(safeItems.count) items (\(SizeFormatter.format(safeSize)))",
            ])
        }

        let json = (try? JSONSerialization.data(withJSONObject: ["recommendations": recommendations]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return ToolResult(toolCallId: id, name: "recommend_cleanup", content: json)
    }

    private func startScan(id: String, arguments: String) -> ToolResult {
        ToolResult(
            toolCallId: id,
            name: "start_scan",
            content: "{\"status\": \"initiated\", \"message\": \"Scan request forwarded to the UI. The user will see scan progress in the main window.\"}"
        )
    }

    // MARK: - Destructive tools

    private func cleanItems(
        id: String,
        arguments: String,
        results: [ScanCategory: ScanResult]
    ) -> ToolResult {
        ToolResult(
            toolCallId: id,
            name: "clean_items",
            content: "{\"status\": \"pending_confirmation\", \"message\": \"The user must confirm this action in the app UI.\"}",
            requiresConfirmation: true
        )
    }
}
