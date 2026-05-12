import SwiftUI

public struct ChatView: View {
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        emptyState
                    }

                    ForEach(messages) { message in
                        ChatBubble(message: message)
                    }
                }
                .padding(20)
            }

            Divider()
                .overlay(Color.white.opacity(0.06))

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

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(red: 0.70, green: 0.45, blue: 1.0))
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
    }

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

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, content: trimmed))
        inputText = ""
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            Text(message.content)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(message.role == .user
                              ? Color(red: 0.70, green: 0.45, blue: 1.0).opacity(0.2)
                              : Color.white.opacity(0.06))
                )

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
