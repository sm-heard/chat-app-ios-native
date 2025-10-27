import Foundation
import Combine

struct LanguageOption: Identifiable, Equatable {
    let code: String
    let displayName: String

    var id: String { code }

    static func == (lhs: LanguageOption, rhs: LanguageOption) -> Bool {
        lhs.code == rhs.code
    }
}

final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()

    @Published private(set) var preferredLanguageCode: String? {
        didSet {
            if let code = preferredLanguageCode {
                UserDefaults.standard.set(code, forKey: Self.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.storageKey)
            }
        }
    }

    private init() {
        preferredLanguageCode = UserDefaults.standard.string(forKey: Self.storageKey)
    }

    func setPreferredLanguage(code: String) {
        preferredLanguageCode = code
    }

    func clear() {
        preferredLanguageCode = nil
    }

    var preferredLanguageOption: LanguageOption? {
        guard let code = preferredLanguageCode else { return nil }
        return Self.availableLanguages.first(where: { $0.code == code })
    }

    static let availableLanguages: [LanguageOption] = [
        LanguageOption(code: "en", displayName: "English"),
        LanguageOption(code: "es", displayName: "Spanish"),
        LanguageOption(code: "fr", displayName: "French"),
        LanguageOption(code: "de", displayName: "German"),
        LanguageOption(code: "it", displayName: "Italian"),
        LanguageOption(code: "pt", displayName: "Portuguese"),
        LanguageOption(code: "ja", displayName: "Japanese"),
        LanguageOption(code: "ko", displayName: "Korean"),
        LanguageOption(code: "zh", displayName: "Chinese (Simplified)"),
        LanguageOption(code: "zh-TW", displayName: "Chinese (Traditional)"),
        LanguageOption(code: "ar", displayName: "Arabic"),
        LanguageOption(code: "hi", displayName: "Hindi")
    ]

    static let storageKey = "preferred_language_code"
}
