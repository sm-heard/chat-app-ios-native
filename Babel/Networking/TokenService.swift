import Foundation

struct TokenResponse: Decodable {
    struct User: Decodable {
        let id: String
        let name: String?
        let image: URL?
    }

    let token: String
    let user: User?
    let apiKey: String
}

enum TokenServiceError: LocalizedError {
    case invalidResponse
    case invalidStatusCode(Int)
    case missingToken
    case apiKeyMismatch

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
        }
    }
}

final class TokenService {
    static let shared = TokenService()

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchToken(userId: String, name: String?) async throws -> TokenResponse {
        var request = URLRequest(url: AppConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any?] = [
            "user_id": userId,
            "name": name
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }, options: [])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
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

