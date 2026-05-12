import Foundation
import MPCore

public actor InspectorPopover {

    private let client: OpenRouterClient

    public init(client: OpenRouterClient) {
        self.client = client
    }

    public struct InspectorResult: Sendable {
        public let path: String
        public let explanation: String
        public let owner: String
        public let isSafeToDelete: Bool
        public let recommendation: String

        public init(path: String, explanation: String, owner: String, isSafeToDelete: Bool, recommendation: String) {
            self.path = path
            self.explanation = explanation
            self.owner = owner
            self.isSafeToDelete = isSafeToDelete
            self.recommendation = recommendation
        }
    }

    public func explain(path: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let metadata = gatherMetadata(for: path)
                let messages = [
                    ChatMessage(role: .system, content: """
                    You are MacPolish's file inspector. Given a macOS file or folder path and its metadata, \
                    explain in 2-3 sentences: (1) what it is and which app created it, (2) whether it is safe \
                    to delete, (3) a one-line recommendation. Be concise and accurate. \
                    If you are not certain, say so. Do not use markdown formatting.
                    """),
                    ChatMessage(role: .user, content: """
                    Path: \(path)
                    \(metadata)
                    """),
                ]

                let stream = await client.send(messages: messages, tools: [], stream: true)
                do {
                    for try await event in stream {
                        if case .contentDelta(let text) = event {
                            continuation.yield(text)
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func gatherMetadata(for path: String) -> String {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        var lines: [String] = []

        if let attrs = try? fm.attributesOfItem(atPath: path) {
            if let size = attrs[.size] as? Int64 {
                lines.append("Size: \(SizeFormatter.format(size))")
            }
            if let modified = attrs[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                lines.append("Last modified: \(formatter.string(from: modified))")
            }
            if let type = attrs[.type] as? FileAttributeType {
                lines.append("Type: \(type == .typeDirectory ? "Directory" : "File")")
            }
        }

        let ext = url.pathExtension
        if !ext.isEmpty {
            lines.append("Extension: .\(ext)")
        }

        if let bundle = Bundle(url: url) {
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                lines.append("Bundle name: \(name)")
            }
            if let identifier = bundle.bundleIdentifier {
                lines.append("Bundle ID: \(identifier)")
            }
        }

        let components = url.pathComponents
        if components.count >= 3 {
            if components[1] == "Library" {
                lines.append("Location: System Library")
            } else if components[1] == "Users" && components.count >= 4 && components[3] == "Library" {
                lines.append("Location: User Library")
            } else if components[1] == "Applications" {
                lines.append("Location: Applications")
            }
        }

        return lines.joined(separator: "\n")
    }
}
