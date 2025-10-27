import Foundation
import NaturalLanguage

final class LanguageDetector {
    static let shared = LanguageDetector()

    private init() {}

    func detectLanguageCode(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return dominant.rawValue.lowercased()
    }

    func shouldTranslate(sourceLanguage: String?, targetLanguage: String) -> Bool {
        guard let source = sourceLanguage?.lowercased(), !source.isEmpty else {
            return true
        }
        return !languagesMatch(source, targetLanguage.lowercased())
    }

    func languagesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let left = lhs?.lowercased(), let right = rhs?.lowercased() else { return false }
        if left == right { return true }

        // Fallback to comparing base language.
        return baseCode(for: left) == baseCode(for: right)
    }

    private func baseCode(for code: String) -> String {
        guard let separatorIndex = code.firstIndex(of: "-") else {
            return code
        }
        return String(code[..<separatorIndex])
    }
}

enum LanguagePreferences {
    static var deviceLanguageCode: String {
        Locale.preferredLanguages.first?.lowercased() ?? "en"
    }
}
