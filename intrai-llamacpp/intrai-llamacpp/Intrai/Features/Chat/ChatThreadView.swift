import SwiftUI
import MarkdownUI

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
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: modelStateIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(modelStateTint)
            Text(modelStatusLine)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
                if viewModel.messages.isEmpty {
                    ContentUnavailableView {
                        Label("No messages yet", systemImage: "message")
                    } description: {
                        Text(viewModel.loadedModelName == nil
                            ? "Load a model, then send your first message."
                            : "Send a message to start this conversation.")
                    }
                } else {
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

            if viewModel.loadedModelName == nil {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Load a model before sending messages.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
            markdownMessageText(message.content.isEmpty && message.status == .streaming ? "..." : message.content)
            if let statusLabel {
                Text(statusLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(message.status == .failed ? .red : .orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .background(
            isUser
                ? Color.accentColor.opacity(0.18)
                : Color(uiColor: .secondarySystemBackground).opacity(0.9)
        )
        .clipShape(RoundedRectangle(cornerRadius: bubbleRadius))
    }

    @ViewBuilder
    private func markdownMessageText(_ value: String) -> some View {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        } else {
            Markdown(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func statusPill(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }

    private var modelStateIcon: String {
        if viewModel.isLoadingModel { return "arrow.triangle.2.circlepath" }
        if viewModel.isRestoringModel { return "clock.arrow.circlepath" }
        return viewModel.loadedModelName == nil ? "exclamationmark.circle" : "checkmark.circle.fill"
    }

    private var modelStateTint: Color {
        if viewModel.isLoadingModel { return .blue }
        if viewModel.isRestoringModel { return .yellow }
        return viewModel.loadedModelName == nil ? .orange : .green
    }

    private var modelStatusLine: String {
        if viewModel.isLoadingModel { return "Loading selected model..." }
        if viewModel.isRestoringModel { return "Restoring previous model..." }
        if let modelName = viewModel.loadedModelName { return "Ready: \(modelName)" }
        return "No model loaded"
    }
}
