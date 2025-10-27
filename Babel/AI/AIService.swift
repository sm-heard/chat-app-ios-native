import Foundation

enum AITask: String {
    case translate
    case explain
    case tone
    case smartReplies = "smart_replies"
}

struct TranslationResult: Equatable {
    let translation: String
    let detectedLanguage: String?
    let quality: String?
}

struct ExplainResult: Equatable {
    let explanation: String
    let tips: String?
}

struct ToneResult: Equatable {
    let rewritten: String
    let notes: String?
}

struct SmartRepliesResult: Equatable {
    let suggestions: [String]
}

struct SmartReplyContextMessage: Encodable, Equatable {
    enum Role: String, Encodable {
        case user
        case other
    }

    let role: Role
    let text: String
    let language: String?
}

enum AIServiceError: LocalizedError {
    case invalidResponse
    case invalidStatusCode(Int)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "AI endpoint returned an unexpected response."
        case .invalidStatusCode(let code):
            return "AI endpoint failed with status code \(code)."
        case .serverMessage(let message):
            return message
        }
    }
}

final class AIService {
    static let shared = AIService()

    private let session: URLSession
    private let endpoint: URL

    private init(session: URLSession = .shared) {
        self.session = session
        self.endpoint = AIService.makeEndpoint()
    }

    private static func makeEndpoint() -> URL {
        let tokenURL = AppConfig.tokenEndpoint
        let apiBase = tokenURL
            .deletingLastPathComponent() // /api/stream
            .deletingLastPathComponent() // /api
        return apiBase.appendingPathComponent("ai")
    }

    func translate(
        text: String,
        sourceLanguage: String?,
        targetLanguage: String,
        messageId: String?
    ) async throws -> TranslationResult {
        struct Payload: Encodable {
            let text: String
            let target: String
            let source: String?
            let message_id: String?
        }

        struct Response: Decodable {
            let translation: String
            let detectedLanguage: String?
            let detected_language: String?
            let quality: String?

            var resolvedDetectedLanguage: String? {
                detectedLanguage ?? detected_language
            }
        }

        let payload = Payload(text: text, target: targetLanguage, source: sourceLanguage, message_id: messageId)
        let response: Response = try await perform(task: .translate, payload: payload)

        return TranslationResult(
            translation: response.translation,
            detectedLanguage: response.resolvedDetectedLanguage,
            quality: response.quality
        )
    }

    func explain(text: String, targetLanguage: String) async throws -> ExplainResult {
        struct Payload: Encodable {
            let text: String
            let target: String
        }

        struct Response: Decodable {
            let explanation: String
            let tips: String?
        }

        let payload = Payload(text: text, target: targetLanguage)
        let response: Response = try await perform(task: .explain, payload: payload)
        return ExplainResult(explanation: response.explanation, tips: response.tips?.nilIfEmpty)
    }

    func rewrite(text: String, targetLanguage: String, style: ToneStyle) async throws -> ToneResult {
        struct Payload: Encodable {
            let text: String
            let target: String
            let style: String
        }

        struct Response: Decodable {
            let rewritten: String
            let notes: String?
        }

        let payload = Payload(text: text, target: targetLanguage, style: style.rawValue)
        let response: Response = try await perform(task: .tone, payload: payload)
        return ToneResult(rewritten: response.rewritten, notes: response.notes?.nilIfEmpty)
    }

    func smartReplies(messages: [SmartReplyContextMessage], targetLanguage: String) async throws -> SmartRepliesResult {
        struct Payload: Encodable {
            let messages: [SmartReplyContextMessage]
            let target: String
        }

        struct Response: Decodable {
            let suggestions: [String]
        }

        let payload = Payload(messages: messages, target: targetLanguage)
        let response: Response = try await perform(task: .smartReplies, payload: payload)
        let suggestions = response.suggestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !suggestions.isEmpty else {
            throw AIServiceError.serverMessage("No smart replies available")
        }
        return SmartRepliesResult(suggestions: suggestions)
    }

    private func perform<Request: Encodable, Response: Decodable>(
        task: AITask,
        payload: Request
    ) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let envelope = RequestEnvelope(task: task.rawValue, payload: payload)
        request.httpBody = try JSONEncoder().encode(envelope)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let serverMessage = try? JSONDecoder().decode(ServerErrorResponse.self, from: data) {
                throw AIServiceError.serverMessage(serverMessage.error)
            }
            throw AIServiceError.invalidStatusCode(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AIServiceError.invalidResponse
        }
    }
}

private struct ServerErrorResponse: Decodable {
    let error: String
}

private struct RequestEnvelope<Payload: Encodable>: Encodable {
    let task: String
    let payload: Payload
}

enum ToneStyle: String {
    case formal
    case neutral
    case casual
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
