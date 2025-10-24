import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        content
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

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Checking account…")
                .progressViewStyle(.circular)
        case .signedOut:
#if canImport(AuthenticationServices)
            SignInView(viewModel: viewModel)
#else
            Text("Sign in with Apple is unavailable on this device.")
                .multilineTextAlignment(.center)
                .padding()
#endif
        case .connecting:
            ProgressView("Connecting…")
                .progressViewStyle(.circular)
        case .connected:
#if canImport(StreamChatSwiftUI) && canImport(StreamChat)
            ChatContainerView(viewModel: viewModel)
#else
            MissingDependencyView()
#endif
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
    @ObservedObject var viewModel: AppViewModel
    @State private var showingChannelCreator = false

    var body: some View {
        TabView {
            NavigationView {
                ChatChannelListView(title: "Babel")
                    .navigationTitle("Chats")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showingChannelCreator = true
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .disabled(viewModel.chatClient == nil || viewModel.currentUser == nil)
                        }
                    }
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Chats", systemImage: "bubble.left.and.bubble.right")
            }
            .sheet(isPresented: $showingChannelCreator) {
                if let chatClient = viewModel.chatClient, let currentUser = viewModel.currentUser {
                    ChannelCreationView(chatClient: chatClient, currentUser: currentUser)
                } else {
                    ProgressView("Loading…")
                        .padding()
                }
            }

            ProfileView(user: viewModel.currentUser)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}
#endif

#if canImport(AuthenticationServices)
import AuthenticationServices

struct SignInView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text("Welcome to Babel")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Sign in with Apple to sync your chats across devices.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                viewModel.handleSignIn(result: result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            Spacer()
        }
        .padding()
    }
}
#endif
