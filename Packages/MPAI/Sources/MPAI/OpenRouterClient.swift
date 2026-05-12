import Foundation
import MPCore

public actor OpenRouterClient {
    private var apiKey: String?
    private var model: String

    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let httpReferer = "https://github.com/macpolish/MacPolish"
    private let appTitle = "MacPolish"

    public enum StreamEvent: Sendable {
        case contentDelta(String)
        case toolUseStart(id: String, name: String)
        case toolUseDelta(id: String, content: String)
        case toolUseEnd(id: String)
        case done
    }

    public init(apiKey: String? = nil, model: String = "anthropic/claude-opus-4.7") {
        self.apiKey = apiKey
        self.model = model
    }

    public func setAPIKey(_ key: String) {
        self.apiKey = key
    }

    public func setModel(_ model: String) {
        self.model = model
    }

    public func currentModel() -> String {
        model
    }

    public func send(
        messages: [ChatMessage],
        tools: [ToolDefinition] = [],
        stream: Bool = true
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            guard apiKey != nil else {
                continuation.finish(throwing: OpenRouterError.missingAPIKey)
                return
            }
            continuation.yield(.contentDelta("AI Assistant is not yet connected."))
            continuation.yield(.done)
            continuation.finish()
        }
    }
}

public enum OpenRouterError: LocalizedError {
    case missingAPIKey
    case invalidResponse(Int)
    case decodingError(String)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "OpenRouter API key is not configured."
        case .invalidResponse(let code): return "Server returned status \(code)."
        case .decodingError(let msg): return "Failed to decode response: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}
