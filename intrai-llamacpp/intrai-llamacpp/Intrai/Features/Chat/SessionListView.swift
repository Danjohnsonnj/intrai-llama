import SwiftUI

struct SessionListView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var sessionPendingRename: ChatSessionRecord?
    @State private var renameTitleDraft: String = ""

    var body: some View {
        List(selection: $viewModel.selectedSessionID) {
            ForEach(viewModel.sessions) { session in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 3) {
                            Text("Last updated:")
                            Text(lastUpdatedLabel(for: session.updatedAt))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Menu {
                        Button("Rename") {
                            renameTitleDraft = session.title
                            sessionPendingRename = session
                        }
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.deleteSession(id: session.id) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(rowBackgroundColor(for: session))
                        .padding(.vertical, 2)
                )
                .tag(session.id)
                .contextMenu {
                    Button("Rename") {
                        renameTitleDraft = session.title
                        sessionPendingRename = session
                    }
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteSession(id: session.id) }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteSession(id: session.id) }
                    }
                    Button("Rename") {
                        renameTitleDraft = session.title
                        sessionPendingRename = session
                    }
                    .tint(.blue)
                }
            }
        }
        .onChange(of: viewModel.selectedSessionID) { _, newValue in
            guard let sessionID = newValue else { return }
            Task { await viewModel.loadMessages(for: sessionID) }
        }
        .sheet(item: $sessionPendingRename) { session in
            renameChatSheet(session: session)
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.sessions.isEmpty {
                ContentUnavailableView {
                    Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Create a new chat to get started.")
                }
            }
        }
    }

    private func rowBackgroundColor(for session: ChatSessionRecord) -> Color {
        if viewModel.selectedSessionID == session.id {
            return Color.accentColor.opacity(0.14)
        }
        return Color(uiColor: .secondarySystemBackground).opacity(0.5)
    }

    private func lastUpdatedLabel(for updatedAt: Date, now: Date = .now) -> String {
        let elapsedSeconds = max(0, now.timeIntervalSince(updatedAt))
        if elapsedSeconds < 60 {
            return "moments ago"
        }

        if elapsedSeconds < 3600 {
            let roundedMinutes = Int((elapsedSeconds / 60).rounded())
            if roundedMinutes >= 60 {
                return "1 hour ago"
            }
            return roundedMinutes == 1 ? "1 minute ago" : "\(roundedMinutes) minutes ago"
        }

        if elapsedSeconds < 86_400 {
            let roundedHours = Int((elapsedSeconds / 3600).rounded())
            if roundedHours >= 24 {
                return "1 day ago"
            }
            return roundedHours == 1 ? "1 hour ago" : "\(roundedHours) hours ago"
        }

        let days = Int(elapsedSeconds / 86_400)
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    @ViewBuilder
    private func renameChatSheet(session: ChatSessionRecord) -> some View {
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
                    Button("Cancel") { sessionPendingRename = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let title = renameTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        Task {
                            await viewModel.renameSession(id: session.id, title: title)
                            sessionPendingRename = nil
                        }
                    }
                    .disabled(renameTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
