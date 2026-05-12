import SwiftUI
import MPCore

public struct ChatView: View {
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isStreaming = false
    @State private var streamingText = ""
    @State private var pendingToolCalls: [PendingToolCall] = []
    @State private var showConfirmation = false
    @State private var confirmationToolCall: PendingToolCall?

    private let client: OpenRouterClient
    private let toolExecutor: ToolExecutor
    private let scanResults: [ScanCategory: ScanResult]

    public init(
        client: OpenRouterClient,
        toolExecutor: ToolExecutor = ToolExecutor(),
        scanResults: [ScanCategory: ScanResult] = [:]
    ) {
        self.client = client
        self.toolExecutor = toolExecutor
        self.scanResults = scanResults
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty && !isStreaming {
                            emptyState
                        }

                        ForEach(messages) { message in
                            ChatBubble(message: message)
                        }

                        if isStreaming && !streamingText.isEmpty {
                            streamingBubble
                        }

                        if !pendingToolCalls.isEmpty {
                            toolCallsView
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(20)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: streamingText) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.06))

            inputBar
        }
        .alert("Confirm Cleanup", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {
                confirmationToolCall = nil
            }
            Button("Clean", role: .destructive) {
                if let tc = confirmationToolCall {
                    Task { await executeConfirmedTool(tc) }
                }
            }
        } message: {
            Text("The AI assistant wants to clean items. This action cannot be undone. Continue?")
        }
    }

    // MARK: - Components

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color(red: 0.70, green: 0.45, blue: 1.0).opacity(0.5))

            Text("MacPolish AI Assistant")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("Ask about your Mac, get cleanup recommendations,\nor explain any file or process.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    private var streamingBubble: some View {
        HStack {
            Text(streamingText)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))
                )
            Spacer(minLength: 60)
        }
    }

    private var toolCallsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pendingToolCalls, id: \.id) { tc in
                HStack(spacing: 8) {
                    if tc.isExecuting {
                        ProgressView()
                            .controlSize(.small)
                    } else if tc.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "function")
                            .foregroundStyle(.orange)
                    }
                    Text(tc.name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask MacPolish AI...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                )
                .onSubmit { sendMessage() }
                .disabled(isStreaming)

            Button(action: sendMessage) {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(red: 0.70, green: 0.45, blue: 1.0))
            }
            .buttonStyle(.plain)
            .disabled(!isStreaming && inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        inputText = ""

        Task { await streamResponse() }
    }

    private func streamResponse() async {
        isStreaming = true
        streamingText = ""
        pendingToolCalls = []

        var allMessages = [
            ChatMessage(role: .system, content: AITools.systemPrompt)
        ] + messages

        let stream = await client.send(
            messages: allMessages,
            tools: AITools.definitions,
            stream: true
        )

        var toolCallArgs: [String: String] = [:]

        do {
            for try await event in stream {
                switch event {
                case .contentDelta(let text):
                    streamingText += text

                case .toolUseStart(let id, let name):
                    let tc = PendingToolCall(id: id, name: name)
                    pendingToolCalls.append(tc)
                    toolCallArgs[id] = ""

                case .toolUseDelta(let id, let content):
                    toolCallArgs[id, default: ""] += content

                case .toolUseEnd(let id):
                    if let idx = pendingToolCalls.firstIndex(where: { $0.id == id }) {
                        pendingToolCalls[idx].isComplete = true
                    }

                case .done:
                    break
                }
            }
        } catch {
            if streamingText.isEmpty {
                streamingText = "Error: \(error.localizedDescription)"
            }
        }

        if !streamingText.isEmpty {
            messages.append(ChatMessage(role: .assistant, content: streamingText))
            streamingText = ""
        }

        for tc in pendingToolCalls where !tc.isComplete {
            let args = toolCallArgs[tc.id] ?? "{}"
            if AITools.isDestructive(tc.name) {
                confirmationToolCall = PendingToolCall(id: tc.id, name: tc.name, arguments: args)
                showConfirmation = true
            } else {
                await executeReadOnlyTool(tc, arguments: args)
            }
        }

        isStreaming = false
    }

    private func executeReadOnlyTool(_ tc: PendingToolCall, arguments: String) async {
        if let idx = pendingToolCalls.firstIndex(where: { $0.id == tc.id }) {
            pendingToolCalls[idx].isExecuting = true
        }

        let result = await toolExecutor.execute(
            toolCallId: tc.id,
            name: tc.name,
            arguments: arguments,
            scanResults: scanResults
        )

        if let idx = pendingToolCalls.firstIndex(where: { $0.id == tc.id }) {
            pendingToolCalls[idx].isExecuting = false
            pendingToolCalls[idx].isComplete = true
        }

        messages.append(ChatMessage(role: .tool, content: result.content))
    }

    private func executeConfirmedTool(_ tc: PendingToolCall) async {
        let result = await toolExecutor.execute(
            toolCallId: tc.id,
            name: tc.name,
            arguments: tc.arguments ?? "{}",
            scanResults: scanResults
        )
        messages.append(ChatMessage(role: .tool, content: result.content))
        confirmationToolCall = nil
    }
}

// MARK: - Supporting types

struct PendingToolCall: Identifiable {
    let id: String
    let name: String
    var arguments: String?
    var isExecuting = false
    var isComplete = false

    init(id: String, name: String, arguments: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .tool {
                    Label("Tool Result", systemImage: "function")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.7))
                }

                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(bubbleColor)
            )

            if message.role == .assistant || message.role == .tool { Spacer(minLength: 60) }
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: return Color(red: 0.70, green: 0.45, blue: 1.0).opacity(0.2)
        case .tool: return Color.orange.opacity(0.08)
        default: return Color.white.opacity(0.06)
        }
    }
}
