import SwiftUI

struct ChatThreadView: View {
    @Bindable var viewModel: ChatViewModel
    private let bubbleRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            transcript
            composer
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current model")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let modelName = viewModel.loadedModelName {
                    Text(modelName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                } else {
                    Text("No model loaded")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if viewModel.isGenerating {
                Button("Cancel") {
                    Task { await viewModel.cancelGeneration() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.45))
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        messageBubble(for: message)
                            .id(message.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastID = viewModel.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if viewModel.lastFailedPrompt != nil {
                HStack {
                    Text("Last failed prompt ready to retry")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task { await viewModel.retryLastFailedPrompt() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $viewModel.draftMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(viewModel.isGenerating)
                Button("Send") {
                    Task { await viewModel.sendDraftMessage() }
                }
                .disabled(viewModel.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isGenerating)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private func messageBubble(for message: ChatMessageRecord) -> some View {
        let isUser = message.role == .user
        let statusLabel: String? = {
            if message.status == .failed { return "Failed" }
            if message.status == .cancelled { return "Cancelled" }
            return nil
        }()

        VStack(alignment: .leading, spacing: 6) {
            Text(isUser ? "You" : "Intrai")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(message.content.isEmpty && message.status == .streaming ? "..." : message.content)
                .font(.body)
                .textSelection(.enabled)
            if let statusLabel {
                Text(statusLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(message.status == .failed ? .red : .orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isUser
                ? Color.accentColor.opacity(0.13)
                : Color(uiColor: .secondarySystemBackground).opacity(0.9)
        )
        .clipShape(RoundedRectangle(cornerRadius: bubbleRadius))
    }
}
