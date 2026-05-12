import Foundation
import UserNotifications
import MPCore

public actor ProactiveDigest {

    private let client: OpenRouterClient
    private let notificationCenter = UNUserNotificationCenter.current()
    private static let lastDigestKey = "ProactiveDigest.lastDigestDate"
    private static let intervalDays: Double = 7

    public init(client: OpenRouterClient) {
        self.client = client
    }

    public func requestPermissionIfNeeded() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    public func shouldRunDigest() -> Bool {
        guard let lastDate = UserDefaults.standard.object(forKey: Self.lastDigestKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastDate) >= Self.intervalDays * 86400
    }

    public func generateAndNotify(scanResults: [ScanCategory: ScanResult]) async {
        guard shouldRunDigest() else { return }

        let summary = buildSummaryText(from: scanResults)
        let aiSummary = await generateAISummary(from: summary)
        let displayText = aiSummary ?? summary

        let content = UNMutableNotificationContent()
        content.title = "MacPolish Weekly Digest"
        content.body = displayText
        content.sound = .default
        content.categoryIdentifier = "DIGEST"

        let request = UNNotificationRequest(
            identifier: "com.macpolish.digest.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try? await notificationCenter.add(request)
        UserDefaults.standard.set(Date(), forKey: Self.lastDigestKey)
    }

    private func buildSummaryText(from results: [ScanCategory: ScanResult]) -> String {
        if results.isEmpty {
            return "No recent scan data available. Tap to run a Smart Scan."
        }

        var totalSize: Int64 = 0
        var totalItems = 0
        var unusedApps = 0

        for (_, result) in results {
            totalSize += result.totalSize
            totalItems += result.items.count
        }

        var text = "You have \(SizeFormatter.format(totalSize)) of recoverable space"
        if totalItems > 0 {
            text += " across \(totalItems) items"
        }
        if unusedApps > 0 {
            text += " and \(unusedApps) apps you haven't opened recently"
        }
        text += ". Tap to review."
        return text
    }

    private func generateAISummary(from rawSummary: String) async -> String? {
        let messages = [
            ChatMessage(role: .system, content: """
            You are MacPolish AI. Write a single concise macOS notification body (under 100 characters). \
            Summarize the scan results naturally. Do not use markdown. Be friendly and actionable.
            """),
            ChatMessage(role: .user, content: "Scan results: \(rawSummary)"),
        ]

        let stream = await client.send(messages: messages, stream: false)
        var result = ""
        do {
            for try await event in stream {
                if case .contentDelta(let text) = event {
                    result += text
                }
            }
        } catch {
            return nil
        }
        return result.isEmpty ? nil : result
    }
}
