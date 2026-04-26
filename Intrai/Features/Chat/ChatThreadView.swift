import SwiftUI

struct ChatThreadView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            composer
        }
    }

    private var header: some View {
        HStack {
            if let modelName = viewModel.loadedModelName {
                Text("Model: \(modelName)")
                    .font(.caption)
            } else {
                Text("No model loaded")
                    .font(.caption)
            }

            Spacer()

            if viewModel.isGenerating {
                Button("Cancel") {
                    Task { await viewModel.cancelGeneration() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == .user ? "You" : "Intrai")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.content.isEmpty && message.status == .streaming ? "..." : message.content)
                                .textSelection(.enabled)
                            if message.status == .failed {
                                Text("Failed")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            } else if message.status == .cancelled {
                                Text("Cancelled")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .id(message.id)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
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
            if let failedPrompt = viewModel.lastFailedPrompt {
                HStack {
                    Text("Last failed prompt ready to retry")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task { await viewModel.retryLastFailedPrompt() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $viewModel.draftMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isGenerating)
                Button("Send") {
                    Task { await viewModel.sendDraftMessage() }
                }
                .disabled(viewModel.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isGenerating)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
