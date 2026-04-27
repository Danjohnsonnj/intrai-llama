import SwiftUI
import UniformTypeIdentifiers

public struct ChatRootView: View {
    @State private var viewModel: ChatViewModel
    @State private var isShowingModelImporter = false

    public init(viewModel: ChatViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            NavigationSplitView {
                SessionListView(viewModel: viewModel)
                    .navigationTitle("Intrai")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Load Model") {
                                isShowingModelImporter = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("New Chat") {
                                Task { await viewModel.createSession() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
            } detail: {
                ChatThreadView(viewModel: viewModel)
            }

            if viewModel.isRestoringModel {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading model...")
                        .font(.callout.weight(.medium))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.black.opacity(0.16), radius: 18, y: 8)
            }
        }
        .task {
            await viewModel.restoreLastModelIfAvailable()
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
}
