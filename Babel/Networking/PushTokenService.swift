import Foundation

struct PushRegistrationRequest: Encodable {
    let user_id: String
    let device_token: String
    let push_provider: String
    let push_provider_name: String?
}

enum PushTokenServiceError: LocalizedError {
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Push registration endpoint returned an unexpected response."
        case .serverError(let message):
            return message
        }
    }
}

final class PushTokenService {
    static let shared = PushTokenService()

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func registerToken(userId: String, deviceToken: String, provider: String = "apn", providerName: String?) async throws {
        var request = URLRequest(url: AppConfig.tokenEndpoint.deletingLastPathComponent().appendingPathComponent("push/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = PushRegistrationRequest(user_id: userId, device_token: deviceToken, push_provider: provider, push_provider_name: providerName)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PushTokenServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let message = try? JSONDecoder().decode([String: String].self, from: data)["error"] {
                throw PushTokenServiceError.serverError(message)
            }
            throw PushTokenServiceError.invalidResponse
        }
    }
}
