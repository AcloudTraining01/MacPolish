import Foundation
import MPCore

public actor OpenRouterClient {
    public enum KeySource: Sendable, Equatable {
        case none
        case bundled
        case user
    }

    private var userAPIKey: String?
    private var bundledAPIKey: String?
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

    public init(
        apiKey: String? = nil,
        bundledKey: String? = nil,
        model: String = "anthropic/claude-opus-4.7"
    ) {
        self.userAPIKey = apiKey
        self.bundledAPIKey = bundledKey
        self.model = model
    }

    public func setAPIKey(_ key: String?) {
        self.userAPIKey = (key?.isEmpty == true) ? nil : key
    }

    public func setBundledKey(_ key: String?) {
        self.bundledAPIKey = (key?.isEmpty == true) ? nil : key
    }

    public func keySource() -> KeySource {
        if userAPIKey != nil { return .user }
        if bundledAPIKey != nil { return .bundled }
        return .none
    }

    private var activeKey: String? {
        userAPIKey ?? bundledAPIKey
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
            guard let apiKey = activeKey else {
                continuation.finish(throwing: OpenRouterError.missingAPIKey)
                return
            }

            let task = Task {
                do {
                    let request = try buildRequest(
                        messages: messages,
                        tools: tools,
                        stream: stream,
                        apiKey: apiKey
                    )

                    if stream {
                        try await handleSSEStream(request: request, continuation: continuation)
                    } else {
                        try await handleSingleResponse(request: request, continuation: continuation)
                    }
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: OpenRouterError.networkError(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request building

    private func buildRequest(
        messages: [ChatMessage],
        tools: [ToolDefinition],
        stream: Bool,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(httpReferer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(appTitle, forHTTPHeaderField: "X-Title")

        var body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": messages.map { msg -> [String: String] in
                ["role": msg.role.rawValue, "content": msg.content]
            }
        ]

        if !tools.isEmpty {
            let toolsData = try JSONEncoder().encode(tools)
            let toolsJSON = try JSONSerialization.jsonObject(with: toolsData)
            body["tools"] = toolsJSON
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - SSE streaming

    private func handleSSEStream(
        request: URLRequest,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.finish(throwing: OpenRouterError.invalidResponse(0))
            return
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 2000 { break }
            }
            continuation.finish(throwing: OpenRouterError.invalidResponse(httpResponse.statusCode))
            return
        }

        var lineBuffer = ""
        for try await byte in bytes {
            let char = Character(UnicodeScalar(byte))
            if char == "\n" {
                if lineBuffer.hasPrefix("data: ") {
                    let payload = String(lineBuffer.dropFirst(6))
                    if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                        continuation.yield(.done)
                        break
                    }
                    parseSSEChunk(payload, continuation: continuation)
                }
                lineBuffer = ""
            } else {
                lineBuffer.append(char)
            }
        }
        continuation.finish()
    }

    private func parseSSEChunk(
        _ payload: String,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else {
            return
        }

        if let content = delta["content"] as? String, !content.isEmpty {
            continuation.yield(.contentDelta(content))
        }

        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for toolCall in toolCalls {
                let index = toolCall["index"] as? Int ?? 0
                let id = toolCall["id"] as? String ?? "call_\(index)"

                if let function = toolCall["function"] as? [String: Any] {
                    if let name = function["name"] as? String {
                        continuation.yield(.toolUseStart(id: id, name: name))
                    }
                    if let args = function["arguments"] as? String, !args.isEmpty {
                        continuation.yield(.toolUseDelta(id: id, content: args))
                    }
                }
            }
        }

        if let finishReason = choices.first?["finish_reason"] as? String {
            if finishReason == "tool_calls" || finishReason == "stop" {
                // Tool call IDs get their end events here
            }
        }
    }

    // MARK: - Non-streaming

    private func handleSingleResponse(
        request: URLRequest,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            continuation.finish(throwing: OpenRouterError.invalidResponse(code))
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            continuation.finish(throwing: OpenRouterError.decodingError("Missing choices in response"))
            return
        }

        if let content = message["content"] as? String {
            continuation.yield(.contentDelta(content))
        }

        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for toolCall in toolCalls {
                let id = toolCall["id"] as? String ?? UUID().uuidString
                if let function = toolCall["function"] as? [String: Any],
                   let name = function["name"] as? String {
                    continuation.yield(.toolUseStart(id: id, name: name))
                    if let args = function["arguments"] as? String {
                        continuation.yield(.toolUseDelta(id: id, content: args))
                    }
                    continuation.yield(.toolUseEnd(id: id))
                }
            }
        }

        continuation.yield(.done)
        continuation.finish()
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
