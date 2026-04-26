import SwiftUI

struct SessionListView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        List(selection: $viewModel.selectedSessionID) {
            ForEach(viewModel.sessions) { session in
                Text(session.title)
                    .tag(session.id)
                    .contextMenu {
                        Button("Rename") {
                            Task { await viewModel.renameSession(id: session.id, title: "\(session.title) (Renamed)") }
                        }
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.deleteSession(id: session.id) }
                        }
                    }
            }
        }
        .onChange(of: viewModel.selectedSessionID) { _, newValue in
            guard let sessionID = newValue else { return }
            Task { await viewModel.loadMessages(for: sessionID) }
        }
    }
}
