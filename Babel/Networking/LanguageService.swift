import Foundation

enum LanguageServiceError: LocalizedError {
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Language update failed due to an unexpected server response."
        case .serverError(let message):
            return message
        }
    }
}

final class LanguageService {
    static let shared = LanguageService()

    private init() {}

    func updateLanguage(code: String, userId: String) async throws {
        let url = AppConfig.tokenEndpoint
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("language")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["user_id": userId, "language": code]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LanguageServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let message = try? JSONDecoder().decode([String: String].self, from: data)["error"] {
                throw LanguageServiceError.serverError(message)
            }
            throw LanguageServiceError.invalidResponse
        }
    }
}
