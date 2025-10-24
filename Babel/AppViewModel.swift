import Foundation
import SwiftUI

#if canImport(StreamChat) && canImport(StreamChatSwiftUI)
import StreamChat
import StreamChatSwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var chatClient: ChatClient?
    @Published private(set) var isConnected: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showingAlert: Bool = false

    private let chatController = ChatController()

    func start(force: Bool = false) async {
        if chatClient != nil && !force { return }

        do {
            let client = try await chatController.connect(force: force)
            chatClient = client
            showingAlert = false
            isConnected = true
        } catch {
            alertTitle = "Connection Failed"
            alertMessage = error.localizedDescription
            showingAlert = true
            isConnected = false
            chatClient = nil
        }
    }
}

private actor ChatController {
    private var cachedClient: ChatClient?
    private var streamChat: StreamChat?

    func connect(force: Bool) async throws -> ChatClient {
        if let client = cachedClient, !force {
            return client
        }

        let userId = try KeychainService.shared.fetchOrCreateUserId()
        print("Babel userId:", userId)     // or os_log if you prefer
        let tokenResponse = try await TokenService.shared.fetchToken(userId: userId, name: nil)

        let config = ChatClientConfig(apiKeyString: AppConfig.streamAPIKey)
        let client = ChatClient(config: config)

        try await connect(client: client, userId: userId, name: tokenResponse.user?.name, token: tokenResponse.token)

        streamChat = StreamChat(chatClient: client)
        cachedClient = client
        return client
    }

    private func connect(client: ChatClient, userId: String, name: String?, token: String) async throws {
        let authToken = try Token(rawValue: token)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.connectUser(
                userInfo: .init(id: userId, name: name),
                token: authToken
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

#else

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var chatClient: Any?
    @Published private(set) var isConnected: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showingAlert: Bool = false

    func start(force: Bool = false) async { }
}

#endif
