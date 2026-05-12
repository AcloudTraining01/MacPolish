import Foundation

public struct ChatMessage: Identifiable, Codable, Sendable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let timestamp: Date

    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public struct ToolDefinition: Codable, Sendable {
    public let type: String
    public let function: FunctionDefinition

    public struct FunctionDefinition: Codable, Sendable {
        public let name: String
        public let description: String
        public let parameters: ParameterSchema
    }

    public struct ParameterSchema: Codable, Sendable {
        public let type: String
        public let properties: [String: PropertySchema]
        public let required: [String]
    }

    public struct PropertySchema: Codable, Sendable {
        public let type: String
        public let description: String
    }

    public init(type: String = "function", function: FunctionDefinition) {
        self.type = type
        self.function = function
    }
}

public struct OpenRouterModel: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let provider: String
    public let contextLength: Int

    public static let curated: [OpenRouterModel] = [
        .init(id: "anthropic/claude-opus-4.7", name: "Claude Opus 4.7", provider: "Anthropic", contextLength: 200_000),
        .init(id: "anthropic/claude-sonnet-4.6", name: "Claude Sonnet 4.6", provider: "Anthropic", contextLength: 200_000),
        .init(id: "openai/gpt-4-turbo", name: "GPT-4 Turbo", provider: "OpenAI", contextLength: 128_000),
        .init(id: "openai/gpt-4o", name: "GPT-4o", provider: "OpenAI", contextLength: 128_000),
        .init(id: "meta-llama/llama-3.1-405b-instruct", name: "Llama 3.1 405B", provider: "Meta", contextLength: 131_072),
        .init(id: "google/gemini-2.0-flash", name: "Gemini 2.0 Flash", provider: "Google", contextLength: 1_000_000),
    ]
}
