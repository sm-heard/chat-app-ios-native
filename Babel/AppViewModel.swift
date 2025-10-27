import Foundation
import SwiftUI

#if canImport(StreamChat) && canImport(StreamChatSwiftUI)
import StreamChat
import StreamChatSwiftUI
#endif

#if canImport(StreamChatUI)
import StreamChatUI
#endif

#if canImport(AuthenticationServices)
import AuthenticationServices
import UIKit
#endif

@MainActor
final class AppViewModel: ObservableObject {
    enum ViewState: Equatable {
        case loading
        case signedOut
        case connecting
        case connected
    }

#if canImport(StreamChat) && canImport(StreamChatSwiftUI)
    @Published private(set) var chatClient: ChatClient?
#else
    @Published private(set) var chatClient: Any?
#endif
    @Published private(set) var state: ViewState = .loading
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showingAlert: Bool = false
    @Published private(set) var currentUser: AuthenticatedUser?

#if canImport(StreamChat) && canImport(StreamChatSwiftUI)
    private let chatController = ChatController()
#endif
#if canImport(AuthenticationServices)
    private let appleCoordinator = AppleSignInCoordinator()
#endif
    private var isConnecting = false

    init() {
#if canImport(StreamChatUI)
        configureStreamComponents()
#endif
    }

    func start(force: Bool = false) async {
        if isConnecting && !force { return }
        state = .loading
        isConnecting = true
        defer { isConnecting = false }

        do {
            if force {
                chatClient = nil
            }

            guard var user = try KeychainService.shared.loadAuthenticatedUser() else {
                currentUser = nil
                state = .signedOut
                return
            }

#if canImport(AuthenticationServices)
            normalizeUser(&user)
#endif

#if canImport(AuthenticationServices)
            do {
                if let credential = try await appleCoordinator.refreshCredentialIfAvailable(for: user) {
                    user = try makeAuthenticatedUser(from: credential, existingUser: user)
                    try KeychainService.shared.saveAuthenticatedUser(user)
                }
            } catch AppleSignInCoordinator.Error.credentialRevoked {
                try? KeychainService.shared.deleteAuthenticatedUser()
                currentUser = nil
                state = .signedOut
                presentAlert(title: "Sign In Required", message: "Your Apple sign-in has been revoked. Please sign in again.")
                return
            } catch {
                // Silent refresh failed; we'll fall back to stored credentials.
            }
#endif

            guard hasValidAppleCredentials(for: user) else {
                try? KeychainService.shared.deleteAuthenticatedUser()
                currentUser = nil
                state = .signedOut
                presentAlert(title: "Sign In Required", message: "Please sign in with Apple to continue.")
                return
            }

            currentUser = user

#if canImport(StreamChat) && canImport(StreamChatSwiftUI)
            state = .connecting
            let (client, tokenResponse) = try await chatController.connect(user: user, force: force)
            chatClient = client
            showingAlert = false
            alertTitle = ""
            alertMessage = ""
            state = .connected

            if let tokenResponse {
                let mergedUser = merge(user: user, with: tokenResponse)
                if mergedUser != user {
                    try KeychainService.shared.saveAuthenticatedUser(mergedUser)
                    currentUser = mergedUser
                } else {
                    currentUser = user
                }
            } else {
                currentUser = user
            }

            if let language = currentUser?.language, !language.isEmpty,
               LanguageSettings.shared.preferredLanguageCode != language {
                LanguageSettings.shared.setPreferredLanguage(code: language)
            }
#if canImport(UserNotifications)
            await PushNotificationManager.shared.requestAuthorizationIfNeeded()
#endif
#else
            state = .connected
#endif
        } catch {
            chatClient = nil
            if let tokenError = error as? TokenServiceError,
               case .missingIdentityToken = tokenError {
                currentUser = nil
                state = .signedOut
                presentAlert(title: "Sign In Required", message: tokenError.localizedDescription)
                try? KeychainService.shared.deleteAuthenticatedUser()
#if canImport(UserNotifications)
                PushNotificationManager.shared.clearCachedToken()
#endif
            } else {
                state = currentUser == nil ? .signedOut : .connecting
                presentAlert(title: "Connection Failed", message: error.localizedDescription)
            }
        }
    }

#if canImport(AuthenticationServices)
    func handleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                presentAlert(title: "Sign In Failed", message: "Unsupported authorization credential.")
                return
            }

            let existingUser: AuthenticatedUser? = (try? KeychainService.shared.loadAuthenticatedUser()).map { stored in
#if canImport(AuthenticationServices)
                var normalized = stored
                normalizeUser(&normalized)
                return normalized
#else
                return stored
#endif
            }

            do {
                let user = try makeAuthenticatedUser(from: credential, existingUser: existingUser)
                try KeychainService.shared.saveAuthenticatedUser(user)
                currentUser = user
                state = .loading
                Task { [weak self] in
                    await self?.start(force: true)
                }
            } catch let error as AppleCredentialError {
                presentAlert(title: "Sign In Failed", message: error.localizedDescription)
            } catch {
                presentAlert(title: "Sign In Failed", message: error.localizedDescription)
            }
        case .failure(let error):
            presentAlert(title: "Sign In Failed", message: error.localizedDescription)
        }
    }

    private enum AppleCredentialError: LocalizedError {
        case missingIdentityToken

        var errorDescription: String? {
            switch self {
            case .missingIdentityToken:
                return "Missing identity token from Apple. Please try again."
            }
        }
    }

    private func makeAuthenticatedUser(
        from credential: ASAuthorizationAppleIDCredential,
        existingUser: AuthenticatedUser?
    ) throws -> AuthenticatedUser {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default

        var name = credential.fullName.flatMap { formatter.string(from: $0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nameValue = name, nameValue.isEmpty {
            name = nil
        }
        if name == nil {
            name = existingUser?.name
        }

        var email = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let emailValue = email, emailValue.isEmpty {
            email = nil
        }
        if email == nil {
            email = existingUser?.email
        }

        guard
            let identityData = credential.identityToken,
            let identityToken = String(data: identityData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !identityToken.isEmpty
        else {
            throw AppleCredentialError.missingIdentityToken
        }

        let authorizationCode = credential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let appleId = credential.user
        let streamId = sanitizeStreamUserId(from: appleId, fallback: existingUser?.id)

        return AuthenticatedUser(
            id: streamId,
            appleUserId: appleId,
            name: name,
            email: email,
            identityToken: identityToken,
            refreshToken: existingUser?.refreshToken,
            authorizationCode: authorizationCode ?? existingUser?.authorizationCode,
            language: existingUser?.language
        )
    }
#endif

#if canImport(AuthenticationServices)
private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    enum Error: Swift.Error {
        case credentialRevoked
        case requestInProgress
    }

    private let provider = ASAuthorizationAppleIDProvider()
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Swift.Error>?
    private var controller: ASAuthorizationController?

    func refreshCredentialIfAvailable(for user: AuthenticatedUser) async throws -> ASAuthorizationAppleIDCredential? {
        let rawUserId = user.appleUserId ?? user.id
        let state = try await credentialState(for: rawUserId)
        switch state {
        case .authorized:
            return try await requestCredential(userId: rawUserId)
        case .revoked, .notFound, .transferred:
            throw Error.credentialRevoked
        @unknown default:
            throw Error.credentialRevoked
        }
    }

    private func credentialState(for userId: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            provider.getCredentialState(forUserID: userId) { state, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }

    private func requestCredential(userId: String) async throws -> ASAuthorizationAppleIDCredential {
        if continuation != nil {
            throw Error.requestInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                if self.continuation != nil {
                    continuation.resume(throwing: Error.requestInProgress)
                    return
                }

                let request = self.provider.createRequest()
                request.requestedScopes = []
                request.user = userId

                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                self.controller = controller
                self.continuation = continuation
                controller.performRequests()
            }
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let anchor = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return anchor
        }
        if let window = UIApplication.shared.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { cleanUp() }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: ASAuthorizationError(.failed))
            return
        }
        continuation?.resume(returning: credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Swift.Error) {
        defer { cleanUp() }
        continuation?.resume(throwing: error)
    }

    private func cleanUp() {
        continuation = nil
        controller = nil
    }
}
#endif

#if canImport(AuthenticationServices)
    private func normalizeUser(_ user: inout AuthenticatedUser) {
        let rawAppleId = user.appleUserId ?? user.id
        user.appleUserId = rawAppleId
        user.id = sanitizeStreamUserId(from: rawAppleId, fallback: user.id)
    }

    private func sanitizeStreamUserId(from raw: String, fallback: String?) -> String {
        let pattern = "[^A-Za-z0-9@_-]"
        let sanitized = raw.replacingOccurrences(of: pattern, with: "-", options: .regularExpression)
        if !sanitized.isEmpty {
            return sanitized
        }
        if let fallback, !fallback.isEmpty {
            return fallback
        }
        return UUID().uuidString.replacingOccurrences(of: pattern, with: "-", options: .regularExpression)
    }
#endif

#if canImport(StreamChat) && canImport(StreamChatSwiftUI)
    private func merge(user: AuthenticatedUser, with response: TokenResponse) -> AuthenticatedUser {
        var merged = merge(user: user, with: response.user)
        if let identity = response.appleIdentityToken?.trimmingCharacters(in: .whitespacesAndNewlines), !identity.isEmpty {
            merged.identityToken = identity
        }
        if let refresh = response.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines), !refresh.isEmpty {
            merged.refreshToken = refresh
        }
        if let appleId = response.appleUserId, !appleId.isEmpty {
            merged.appleUserId = appleId
    #if canImport(AuthenticationServices)
            merged.id = sanitizeStreamUserId(from: appleId, fallback: merged.id)
    #endif
        }
        merged.authorizationCode = nil
        return merged
    }

    private func merge(user: AuthenticatedUser, with payload: TokenResponse.User?) -> AuthenticatedUser {
        guard let payload else { return user }
        var merged = user
        if let name = payload.name, !name.isEmpty {
            merged.name = name
        }
        if let email = payload.email, !email.isEmpty {
            merged.email = email
        }
        if let language = payload.language, !language.isEmpty {
            merged.language = language
        }
        return merged
    }
#endif

    func updatePreferredLanguageIfNeeded(code: String) async {
        guard let currentUser else { return }
        if currentUser.language == code { return }
        do {
            try await LanguageService.shared.updateLanguage(code: code, userId: currentUser.id)
            var updatedUser = currentUser
            updatedUser.language = code
            self.currentUser = updatedUser
            try? KeychainService.shared.saveAuthenticatedUser(updatedUser)
        } catch {
            presentAlert(title: "Language Update Failed", message: error.localizedDescription)
        }
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }

    private func hasValidAppleCredentials(for user: AuthenticatedUser) -> Bool {
        let identity = user.identityToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let refresh = user.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identityAvailable = identity.map { !$0.isEmpty } ?? false
        let refreshAvailable = refresh.map { !$0.isEmpty } ?? false
        let appleId = user.appleUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? user.id
        let hasAppleId = !appleId.isEmpty
        return hasAppleId && (identityAvailable || refreshAvailable)
    }

#if canImport(StreamChatUI)
    private func configureStreamComponents() {
        var components = Components.default
        components.messageAutoTranslationEnabled = true
        components.messageLayoutOptionsResolver = BabelMessageLayoutOptionsResolver()
        Components.default = components
    }
#endif
}

#if canImport(StreamChat) && canImport(StreamChatSwiftUI)
private actor ChatController {
    private var cachedClient: ChatClient?
    private var cachedUserId: String?
    private var streamChat: StreamChat?

    func connect(user: AuthenticatedUser, force: Bool) async throws -> (ChatClient, TokenResponse?) {
        if !force,
           let client = cachedClient,
           cachedUserId == user.id {
            return (client, nil)
        }

        if force {
            cachedClient = nil
            cachedUserId = nil
            streamChat = nil
        }

        let tokenResponse = try await TokenService.shared.fetchToken(
            userId: user.id,
            name: user.name,
            email: user.email,
            identityToken: user.identityToken,
            authorizationCode: user.authorizationCode,
            refreshToken: user.refreshToken,
            appleUserId: user.appleUserId ?? user.id,
            language: LanguageSettings.shared.preferredLanguageCode
        )

        let config = ChatClientConfig(apiKeyString: AppConfig.streamAPIKey)
        let client = ChatClient(config: config)

        try await connect(
            client: client,
            userId: user.id,
            name: tokenResponse.user?.name ?? user.name,
            token: tokenResponse.token
        )

        streamChat = StreamChat(chatClient: client)
        cachedClient = client
        cachedUserId = user.id

        await ensureGeneralChannel(for: client, userId: user.id)

        return (client, tokenResponse)
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

    private func ensureGeneralChannel(for client: ChatClient, userId: String) async {
        let generalChannelId = ChannelId(type: .messaging, id: "babel-general")
        let controller = client.channelController(for: generalChannelId)
        _ = await synchronize(controller)
    }

    private func synchronize(_ controller: ChatChannelController) async -> Error? {
        await withCheckedContinuation { continuation in
            controller.synchronize { error in
                continuation.resume(returning: error)
            }
        }
    }
}
#endif
