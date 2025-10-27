import Foundation

struct TranslationKey: Hashable {
    let messageId: String
    let targetLanguage: String
}

struct TranslationEntry: Equatable {
    let translation: String
    let detectedLanguage: String?
    let quality: String?
    let fetchedAt: Date
}

enum TranslationDisplayMode: String {
    case translated
    case original
}

extension Notification.Name {
    static let translationEntryUpdated = Notification.Name("BabelTranslationEntryUpdated")
    static let translationEntryFailed = Notification.Name("BabelTranslationEntryFailed")
    static let translationDisplayModeChanged = Notification.Name("BabelTranslationDisplayModeChanged")
}

enum TranslationNotificationKey {
    static let messageId = "messageId"
    static let targetLanguage = "targetLanguage"
    static let entry = "entry"
    static let error = "error"
    static let mode = "mode"
}

@MainActor
final class TranslationStore {
    static let shared = TranslationStore()

    private let timeToLive: TimeInterval = 2 * 60 * 60 // 2 hours
    private var entries: [TranslationKey: TranslationEntry] = [:]
    private var displayModes: [String: TranslationDisplayMode] = [:]

    private init() {}

    func cachedEntry(for key: TranslationKey) -> TranslationEntry? {
        guard let entry = entries[key] else { return nil }
        if Date().timeIntervalSince(entry.fetchedAt) > timeToLive {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry
    }

    func store(entry: TranslationEntry, for key: TranslationKey) {
        entries[key] = entry
        NotificationCenter.default.post(
            name: .translationEntryUpdated,
            object: nil,
            userInfo: [
                TranslationNotificationKey.messageId: key.messageId,
                TranslationNotificationKey.targetLanguage: key.targetLanguage,
                TranslationNotificationKey.entry: entry
            ]
        )
    }

    func markFailure(for key: TranslationKey, error: Error) {
        NotificationCenter.default.post(
            name: .translationEntryFailed,
            object: nil,
            userInfo: [
                TranslationNotificationKey.messageId: key.messageId,
                TranslationNotificationKey.targetLanguage: key.targetLanguage,
                TranslationNotificationKey.error: error
            ]
        )
    }

    func displayMode(for messageId: String) -> TranslationDisplayMode {
        displayModes[messageId] ?? .translated
    }

    @discardableResult
    func toggleDisplayMode(for messageId: String) -> TranslationDisplayMode {
        let next: TranslationDisplayMode = displayModes[messageId] == .translated ? .original : .translated
        displayModes[messageId] = next
        NotificationCenter.default.post(
            name: .translationDisplayModeChanged,
            object: nil,
            userInfo: [
                TranslationNotificationKey.messageId: messageId,
                TranslationNotificationKey.mode: next.rawValue
            ]
        )
        return next
    }

    func setDisplayMode(_ mode: TranslationDisplayMode, for messageId: String) {
        displayModes[messageId] = mode
        NotificationCenter.default.post(
            name: .translationDisplayModeChanged,
            object: nil,
            userInfo: [
                TranslationNotificationKey.messageId: messageId,
                TranslationNotificationKey.mode: mode.rawValue
            ]
        )
    }
}

actor TranslationCoordinator {
    static let shared = TranslationCoordinator()

    private var tasks: [TranslationKey: Task<TranslationEntry, Error>] = [:]

    func ensureTranslation(
        key: TranslationKey,
        text: String,
        sourceLanguage: String?,
        targetLanguage: String
    ) {
        Task {
            if let cached = await MainActor.run(body: { TranslationStore.shared.cachedEntry(for: key) }) {
                await MainActor.run {
                    TranslationStore.shared.store(entry: cached, for: key)
                }
                return
            }

            if tasks[key] != nil {
                return
            }

            let task = Task<TranslationEntry, Error> {
                let result = try await AIService.shared.translate(
                    text: text,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    messageId: key.messageId
                )
                return TranslationEntry(
                    translation: result.translation,
                    detectedLanguage: result.detectedLanguage,
                    quality: result.quality,
                    fetchedAt: Date()
                )
            }

            tasks[key] = task

            do {
                let entry = try await task.value
                await MainActor.run {
                    TranslationStore.shared.store(entry: entry, for: key)
                }
            } catch {
                await MainActor.run {
                    TranslationStore.shared.markFailure(for: key, error: error)
                }
            }

            tasks[key] = nil
        }
    }
}
