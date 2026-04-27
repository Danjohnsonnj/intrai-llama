import SwiftUI
import UniformTypeIdentifiers

public struct ChatRootView: View {
    @State private var viewModel: ChatViewModel
    @State private var isShowingModelImporter = false

    public init(viewModel: ChatViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationSplitView {
            SessionListView(viewModel: viewModel)
                .navigationTitle("Intrai")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Load Model") {
                            isShowingModelImporter = true
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Chat") {
                            Task { await viewModel.createSession() }
                        }
                    }
                }
        } detail: {
            ChatThreadView(viewModel: viewModel)
        }
        .task {
            await viewModel.bootstrap()
        }
        .fileImporter(
            isPresented: $isShowingModelImporter,
            allowedContentTypes: [UTType(filenameExtension: "gguf", conformingTo: .data) ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
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
}
