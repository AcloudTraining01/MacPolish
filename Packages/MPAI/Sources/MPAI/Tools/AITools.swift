import Foundation
import MPCore

public enum AITools {
    public static let systemPrompt = """
    You are MacPolish AI Assistant — a helpful macOS system maintenance expert embedded in the MacPolish app.

    You have access to the following tools:
    - get_scan_summary: Returns the latest scan results summary
    - get_disk_usage: Returns disk space usage breakdown
    - recommend_cleanup: Analyzes scan results and recommends safe cleanup actions
    - start_scan: Starts a scan for the specified category
    - clean_items: Cleans selected items (DESTRUCTIVE — requires user confirmation)

    Guidelines:
    - Be concise and helpful
    - When recommending cleanup, always explain what will be removed and why it is safe
    - For destructive actions, always use the clean_items tool which will prompt the user for confirmation
    - Never claim to have cleaned something unless the clean_items tool was called and confirmed
    - If asked about a file or folder, explain what it is, who created it, and whether it is safe to remove
    - Reference actual scan data when available
    """

    public static let definitions: [ToolDefinition] = [
        getScanSummary,
        getDiskUsage,
        recommendCleanup,
        startScan,
        cleanItems,
    ]

    public static let readOnlyToolNames: Set<String> = [
        "get_scan_summary",
        "get_disk_usage",
        "recommend_cleanup",
        "start_scan",
    ]

    public static let destructiveToolNames: Set<String> = [
        "clean_items",
    ]

    public static func isDestructive(_ toolName: String) -> Bool {
        destructiveToolNames.contains(toolName)
    }

    // MARK: - Tool Definitions

    static let getScanSummary = ToolDefinition(
        function: .init(
            name: "get_scan_summary",
            description: "Get a summary of the latest scan results including items found, total size, and categories.",
            parameters: .init(type: "object", properties: [:], required: [])
        )
    )

    static let getDiskUsage = ToolDefinition(
        function: .init(
            name: "get_disk_usage",
            description: "Get current disk usage information including total space, used space, and free space.",
            parameters: .init(type: "object", properties: [:], required: [])
        )
    )

    static let recommendCleanup = ToolDefinition(
        function: .init(
            name: "recommend_cleanup",
            description: "Analyze the latest scan results and provide a ranked list of cleanup recommendations with safety assessment.",
            parameters: .init(type: "object", properties: [:], required: [])
        )
    )

    static let startScan = ToolDefinition(
        function: .init(
            name: "start_scan",
            description: "Start a scan for a specific category. Valid categories: system_junk, trash_bins, mail_attachments, malware, smart_scan",
            parameters: .init(
                type: "object",
                properties: [
                    "category": .init(
                        type: "string",
                        description: "The scan category to run. One of: system_junk, trash_bins, mail_attachments, malware, smart_scan"
                    )
                ],
                required: ["category"]
            )
        )
    )

    static let cleanItems = ToolDefinition(
        function: .init(
            name: "clean_items",
            description: "Clean (delete) selected scan items. This is DESTRUCTIVE and will prompt the user for confirmation before proceeding. Items are quarantined first for safety.",
            parameters: .init(
                type: "object",
                properties: [
                    "category": .init(
                        type: "string",
                        description: "The scan category of items to clean"
                    ),
                    "item_count": .init(
                        type: "string",
                        description: "Number of items to clean (as string)"
                    )
                ],
                required: ["category"]
            )
        )
    )
}
