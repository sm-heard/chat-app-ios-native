import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        Group {
#if canImport(StreamChatSwiftUI)
            if viewModel.isConnected {
                ChatContainerView()
            } else {
                ProgressView("Connecting…")
                    .progressViewStyle(.circular)
            }
#else
            MissingDependencyView()
#endif
        }
        .task {
            await viewModel.start()
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showingAlert) {
            Button("Retry") {
                Task { await viewModel.start(force: true) }
            }
        } message: {
            Text(viewModel.alertMessage)
        }
    }
}

struct MissingDependencyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Stream Chat dependency missing")
                .font(.headline)
            Text("Add StreamChat SwiftUI SDK via Swift Package Manager to enable chat UI.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#if canImport(StreamChatSwiftUI) && canImport(StreamChat)
import StreamChat
import StreamChatSwiftUI

struct ChatContainerView: View {
    var body: some View {
        NavigationView {
            ChatChannelListView()
                .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}
#endif
