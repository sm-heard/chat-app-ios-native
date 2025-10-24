import Foundation

struct TokenResponse: Decodable {
    struct User: Decodable {
        let id: String
        let name: String?
        let image: URL?
        let email: String?
    }

    let token: String
    let user: User?
    let apiKey: String
    let refreshToken: String?
    let appleIdentityToken: String?
    let appleUserId: String?
}

private struct TokenErrorResponse: Decodable {
    let error: String
}

enum TokenServiceError: LocalizedError {
    case invalidResponse
    case invalidStatusCode(Int)
    case missingToken
    case apiKeyMismatch
    case missingIdentityToken
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Token endpoint returned an unexpected response."
        case .invalidStatusCode(let code):
            return "Token endpoint failed with status code \(code)."
        case .missingToken:
            return "Token endpoint response was missing a token."
        case .apiKeyMismatch:
            return "Stream API key mismatch. Check your server configuration."
        case .missingIdentityToken:
            return "Missing Sign in with Apple credentials. Please sign in again."
        case .serverMessage(let message):
            return message
        }
    }
}

final class TokenService {
    static let shared = TokenService()

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchToken(
        userId: String,
        name: String?,
        email: String?,
        identityToken: String?,
        authorizationCode: String?,
        refreshToken: String?,
        appleUserId: String?
    ) async throws -> TokenResponse {
        let identityTokenValue = identityToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshTokenValue = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasIdentityToken = identityTokenValue?.isEmpty == false
        let hasRefreshToken = refreshTokenValue?.isEmpty == false

        guard hasIdentityToken || hasRefreshToken else {
            throw TokenServiceError.missingIdentityToken
        }

        var request = URLRequest(url: AppConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any?] = [
            "user_id": userId,
            "name": name,
            "email": email,
            "identityToken": identityTokenValue,
            "authorizationCode": authorizationCode,
            "refreshToken": refreshTokenValue,
            "apple_user_id": appleUserId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }, options: [])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw TokenServiceError.missingIdentityToken
            }

            if let serverError = try? JSONDecoder().decode(TokenErrorResponse.self, from: data) {
                throw TokenServiceError.serverMessage(serverError.error)
            }

            throw TokenServiceError.invalidStatusCode(httpResponse.statusCode)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        guard !tokenResponse.token.isEmpty else {
            throw TokenServiceError.missingToken
        }

        guard tokenResponse.apiKey == AppConfig.streamAPIKey else {
            throw TokenServiceError.apiKeyMismatch
        }

        return tokenResponse
    }
}
