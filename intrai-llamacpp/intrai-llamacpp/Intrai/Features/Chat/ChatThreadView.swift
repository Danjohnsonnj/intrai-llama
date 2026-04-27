import SwiftUI
import MarkdownUI

struct ChatThreadView: View {
    @Bindable var viewModel: ChatViewModel
    let canCopyTranscript: Bool
    let onCopyTranscript: () -> Void
    private let bubbleRadius: CGFloat = 14
    @State private var isShowingRenameSheet = false
    @State private var renameTitleDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            header
            monitoringStrip
            Divider().opacity(0.6)
            transcript
            composer
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $isShowingRenameSheet) {
            renameChatSheet
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Text(selectedSessionTitle)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            Button {
                renameTitleDraft = selectedSessionTitle
                isShowingRenameSheet = true
            } label: {
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("Rename chat title")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
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
            Button {
                onCopyTranscript()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canCopyTranscript)
            .accessibilityLabel("Copy chat as Markdown")
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

    private var monitoringStrip: some View {
        HStack(spacing: 8) {
            statusPill(
                icon: contextIcon,
                title: contextLabel,
                tint: contextTint
            )
            statusPill(
                icon: healthIcon,
                title: healthLabel,
                tint: healthTint
            )
            if viewModel.isGenerating {
                statusPill(
                    icon: "dot.radiowaves.left.and.right",
                    title: streamLabel,
                    tint: .blue
                )
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.35))
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

            if let contextNotice = viewModel.contextNotice {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(contextNotice)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if viewModel.contextNoticeDetails != nil {
                            Button(viewModel.isShowingContextNoticeDetails ? "Hide" : "Details") {
                                viewModel.toggleContextNoticeDetails()
                            }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                    }

                    if viewModel.isShowingContextNoticeDetails, let detail = viewModel.contextNoticeDetails {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(detail)
                            Text(contextDiagnosticLine)
                            Text(latestGenerationLine)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
        if viewModel.isLoadingModel { return "Loading model" }
        if viewModel.isRestoringModel { return "Restoring model" }
        if viewModel.loadedModelName != nil { return "Model ready" }
        return "No model loaded"
    }

    private var contextLabel: String {
        switch viewModel.contextFidelityState {
        case .normal:
            return "Context healthy"
        case .nearLimit:
            return "Context near limit"
        case .compactedSummaryActive:
            return "Compaction active"
        case .blocked:
            return "Context blocked"
        }
    }

    private var contextIcon: String {
        switch viewModel.contextFidelityState {
        case .normal:
            return "checkmark.shield"
        case .nearLimit:
            return "exclamationmark.triangle"
        case .compactedSummaryActive:
            return "square.stack.3d.up"
        case .blocked:
            return "xmark.octagon"
        }
    }

    private var contextTint: Color {
        switch viewModel.contextFidelityState {
        case .normal:
            return .green
        case .nearLimit:
            return .orange
        case .compactedSummaryActive:
            return .yellow
        case .blocked:
            return .red
        }
    }

    private var healthLabel: String {
        switch viewModel.latestMonitoringHealth {
        case .healthy:
            return "Generation healthy"
        case .slow:
            return "Generation slow"
        case .compacted:
            return "Compacted response"
        case .cancelled:
            return "Generation cancelled"
        case .failed:
            return "Generation failed"
        case .contextLimited:
            return "Context limited"
        }
    }

    private var healthIcon: String {
        switch viewModel.latestMonitoringHealth {
        case .healthy:
            return "heart.text.square"
        case .slow:
            return "tortoise"
        case .compacted:
            return "text.justify"
        case .cancelled:
            return "slash.circle"
        case .failed:
            return "exclamationmark.octagon"
        case .contextLimited:
            return "xmark.octagon"
        }
    }

    private var healthTint: Color {
        switch viewModel.latestMonitoringHealth {
        case .healthy:
            return .green
        case .slow:
            return .orange
        case .compacted:
            return .yellow
        case .cancelled:
            return .orange
        case .failed:
            return .red
        case .contextLimited:
            return .red
        }
    }

    private var streamLabel: String {
        let snapshot = viewModel.liveGenerationSnapshot
        let chars = snapshot.streamedCharacterCount
        let speed = snapshot.approxCharsPerSecond.map { "\(Int($0.rounded())) chars/s" } ?? "warming up"
        return "Streaming \(chars) chars (\(speed))"
    }

    private var contextDiagnosticLine: String {
        guard let budget = viewModel.tokenBudgetResult else {
            return "No token budget details available yet."
        }
        let percent = Int((budget.utilization * 100).rounded())
        return "Budget \(budget.estimatedInputTokens)/\(budget.inputBudget) tokens (\(percent)%)"
    }

    private var latestGenerationLine: String {
        guard let metrics = viewModel.lastGenerationMetrics else {
            return "No generation metrics captured yet."
        }
        let ttft = metrics.timeToFirstTokenMs.map { "\(Int($0.rounded()))ms TTFT" } ?? "TTFT unavailable"
        let duration = "\(Int(metrics.generationDurationMs.rounded()))ms total"
        return "\(ttft), \(duration), outcome: \(metrics.endReason.rawValue)"
    }

    private var selectedSessionTitle: String {
        guard let sessionID = viewModel.selectedSessionID else {
            return "Chat"
        }
        return viewModel.sessions.first(where: { $0.id == sessionID })?.title ?? "Chat"
    }

    @ViewBuilder
    private var renameChatSheet: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Chat title", text: $renameTitleDraft)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                }
            }
            .navigationTitle("Rename chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isShowingRenameSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let title = renameTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty, let sessionID = viewModel.selectedSessionID else { return }
                        Task {
                            await viewModel.renameSession(id: sessionID, title: title)
                            isShowingRenameSheet = false
                        }
                    }
                    .disabled(renameTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
