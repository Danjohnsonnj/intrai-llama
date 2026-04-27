import SwiftUI
import UniformTypeIdentifiers
import UIKit

public struct ChatRootView: View {
    @State private var viewModel: ChatViewModel
    @State private var isShowingModelImporter = false
    @State private var isShowingGlobalSettings = false
    @State private var copyToastMessage: String?

    public init(viewModel: ChatViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            NavigationSplitView {
                VStack(spacing: 10) {
                    sidebarUtilityPanel
                    SessionListView(viewModel: viewModel)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .navigationTitle("Intrai")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingGlobalSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("Global settings")
                    }
                }
            } detail: {
                ChatThreadView(viewModel: viewModel)
            }

            if viewModel.isRestoringModel || viewModel.isLoadingModel {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(viewModel.isRestoringModel ? "Restoring model" : "Loading model")
                        .font(.headline.weight(.semibold))
                    Text(viewModel.isRestoringModel
                        ? "We are loading your previously selected model."
                        : "We are preparing the selected model for chat.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.2), radius: 20, y: 8)
            }

            if let copyToastMessage {
                VStack {
                    Spacer()
                    Text(copyToastMessage)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
                        .padding(.bottom, 22)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(false)
            }
        }
        .task {
            await viewModel.restoreLastModelIfAvailable()
            await viewModel.bootstrap()
        }
        .sheet(isPresented: $isShowingGlobalSettings) {
            NavigationStack {
                Form {
                    Section("Global behavior (coming soon)") {
                        LabeledContent("System prompt") {
                            Text("Not configured")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("User memory") {
                            Text("Not configured")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Scope") {
                        Text("These controls are global to the app, not per chat.")
                        Text("A future option can apply system prompt updates to existing chats.")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Global settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            isShowingGlobalSettings = false
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingModelImporter,
            allowedContentTypes: [UTType(filenameExtension: "gguf", conformingTo: .data) ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                // loadModel() opens security-scoped access, copies into app storage, then loads.
                Task { await viewModel.loadModel(from: url) }
            case .failure(let error):
                viewModel.reportUserFacingError("Model import failed: \(error.localizedDescription)")
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.clearError()
                }
            }
        )) {
            Button("OK", role: .cancel) {}
            if viewModel.lastFailedPrompt != nil {
                Button("Retry") {
                    Task { await viewModel.retryLastFailedPrompt() }
                }
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var sidebarUtilityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Load model") {
                    isShowingModelImporter = true
                }
                .buttonStyle(.borderedProminent)

                Button("New chat") {
                    Task { await viewModel.createSession() }
                }
                .buttonStyle(.bordered)

                Button("Copy chat as Markdown") {
                    copyChatAsMarkdownToClipboard()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.messages.isEmpty)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: modelStatusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(modelStatusColor)
                Text(modelStatusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func copyChatAsMarkdownToClipboard() {
        guard let markdown = viewModel.markdownTranscriptForSelectedSession(), !markdown.isEmpty else {
            return
        }

        UIPasteboard.general.string = markdown
        withAnimation {
            copyToastMessage = "Copied chat as Markdown"
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation {
                copyToastMessage = nil
            }
        }
    }

    private var modelStatusText: String {
        if viewModel.isLoadingModel {
            return "Loading selected model..."
        }
        if viewModel.isRestoringModel {
            return "Restoring previous model..."
        }
        if let loadedModelName = viewModel.loadedModelName {
            return "Ready: \(loadedModelName)"
        }
        return "No model loaded"
    }

    private var modelStatusIcon: String {
        if viewModel.isLoadingModel {
            return "arrow.triangle.2.circlepath"
        }
        if viewModel.isRestoringModel {
            return "clock.arrow.circlepath"
        }
        return viewModel.loadedModelName == nil ? "exclamationmark.circle" : "checkmark.circle.fill"
    }

    private var modelStatusColor: Color {
        if viewModel.isLoadingModel {
            return .blue
        }
        if viewModel.isRestoringModel {
            return .yellow
        }
        return viewModel.loadedModelName == nil ? .orange : .green
    }
}
