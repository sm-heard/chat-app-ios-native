#if canImport(StreamChatSwiftUI) && canImport(StreamChat)
import StreamChat
import StreamChatSwiftUI
import SwiftUI

struct BabelMessageTranslationFooterView: View {
    @ObservedObject var messageViewModel: MessageViewModel
    @ObservedObject private var languageSettings = LanguageSettings.shared

    @Injected(\.fonts) private var fonts
    @Injected(\.colors) private var colors

    @State private var translationEntry: TranslationEntry?
    @State private var displayMode: TranslationDisplayMode = .translated
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var isExplaining = false
    @State private var explanationText: String?
    @State private var explanationTips: String?
    @State private var explanationError: String?
    @State private var showExplanationAlert = false

    private let notificationCenter = NotificationCenter.default

    var body: some View {
        Group {
            if shouldDisplayFooter {
                VStack(alignment: .leading, spacing: 6) {
                    if needsTranslation {
                        translationContent
                    }
                    controlRow
                    if let errorMessage {
                        Text(errorMessage)
                            .font(fonts.footnote)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onReceive(notificationCenter.publisher(for: .translationEntryUpdated)) { notification in
            handleTranslationUpdate(notification: notification)
        }
        .onReceive(notificationCenter.publisher(for: .translationEntryFailed)) { notification in
            handleTranslationFailure(notification: notification)
        }
        .onReceive(languageSettings.$preferredLanguageCode) { _ in
            translationEntry = nil
            loadIfNeeded()
        }
        .alert(isPresented: $showExplanationAlert) {
            if let explanationText {
                let message = explanationTips.map { explanationText + "\n\n" + $0 } ?? explanationText
                return Alert(
                    title: Text("Explanation"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"), action: clearExplanation)
                )
            } else {
                return Alert(
                    title: Text("Explain Failed"),
                    message: Text(explanationError ?? "Unable to explain this message."),
                    dismissButton: .default(Text("OK"), action: clearExplanation)
                )
            }
        }
    }

    private var translationContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let entry = translationEntry, displayMode == .translated {
                Text(entry.translation)
                    .font(fonts.body)
                    .foregroundColor(Color(colors.text))
                if let detected = entry.detectedLanguage,
                   let languageName = Locale.current.localizedString(forLanguageCode: detected) {
                    Text("Translated from \(languageName)")
                        .font(fonts.footnote)
                        .foregroundColor(Color(colors.subtitleText))
                }
            } else if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                    Text("Translating…")
                        .font(fonts.footnote)
                        .foregroundColor(Color(colors.subtitleText))
                }
            }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            if needsTranslation, translationEntry != nil {
                Button(action: toggleDisplayMode) {
                    Text(displayMode == .translated ? "Show original" : "Show translation")
                }
                .font(fonts.footnote)
                .foregroundColor(Color(colors.subtitleText))
                .disabled(isLoading)
            }

            Button(action: explainMessage) {
                if isExplaining {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                } else {
                    Text("Explain")
                }
            }
            .font(fonts.footnote)
            .foregroundColor(Color(colors.subtitleText))
            .disabled(isExplaining)

            Spacer(minLength: 0)
        }
    }

    private var shouldDisplayFooter: Bool {
        let message = messageViewModel.message
        guard !message.isSentByCurrentUser else { return false }
        return !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var needsTranslation: Bool {
        let targetLanguage = languageSettings.preferredLanguageCode ?? LanguagePreferences.deviceLanguageCode
        let message = messageViewModel.message
        guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if let authorLanguage = message.author.language?.languageCode, !authorLanguage.isEmpty {
            return !LanguageDetector.shared.languagesMatch(authorLanguage, targetLanguage)
        }

        let detected = LanguageDetector.shared.detectLanguageCode(for: message.text)
        return LanguageDetector.shared.shouldTranslate(sourceLanguage: detected, targetLanguage: targetLanguage)
    }

    private func loadIfNeeded() {
        guard shouldDisplayFooter else {
            translationEntry = nil
            isLoading = false
            errorMessage = nil
            return
        }

        guard needsTranslation else {
            translationEntry = nil
            isLoading = false
            errorMessage = nil
            return
        }

        let message = messageViewModel.message
        displayMode = TranslationStore.shared.displayMode(for: message.id)
        let targetLanguage = languageSettings.preferredLanguageCode ?? LanguagePreferences.deviceLanguageCode
        let key = TranslationKey(messageId: message.id, targetLanguage: targetLanguage)
        if let cached = TranslationStore.shared.cachedEntry(for: key) {
            translationEntry = cached
            isLoading = false
        } else {
            isLoading = true
            Task {
                await TranslationCoordinator.shared.ensureTranslation(
                    key: key,
                    text: message.text,
                    sourceLanguage: LanguageDetector.shared.detectLanguageCode(for: message.text),
                    targetLanguage: targetLanguage
                )
            }
        }
    }

    private func handleTranslationUpdate(notification: Notification) {
        guard needsTranslation else { return }
        let targetLanguage = languageSettings.preferredLanguageCode ?? LanguagePreferences.deviceLanguageCode
        guard let target = notification.userInfo?[TranslationNotificationKey.targetLanguage] as? String,
              target == targetLanguage,
              let messageId = notification.userInfo?[TranslationNotificationKey.messageId] as? String,
              messageId == messageViewModel.message.id,
              let entry = notification.userInfo?[TranslationNotificationKey.entry] as? TranslationEntry
        else { return }

        translationEntry = entry
        isLoading = false
        errorMessage = nil
    }

    private func handleTranslationFailure(notification: Notification) {
        guard needsTranslation else { return }
        let targetLanguage = languageSettings.preferredLanguageCode ?? LanguagePreferences.deviceLanguageCode
        guard let messageId = notification.userInfo?[TranslationNotificationKey.messageId] as? String,
              messageId == messageViewModel.message.id,
              let target = notification.userInfo?[TranslationNotificationKey.targetLanguage] as? String,
              target == targetLanguage
        else { return }

        isLoading = false
        if let error = notification.userInfo?[TranslationNotificationKey.error] as? Error {
            errorMessage = error.localizedDescription
        } else {
            errorMessage = "Translation unavailable."
        }
    }

    private func toggleDisplayMode() {
        let messageId = messageViewModel.message.id
        displayMode = TranslationStore.shared.toggleDisplayMode(for: messageId)
    }

    private func explainMessage() {
        guard !messageViewModel.message.text.isEmpty else { return }
        isExplaining = true
        explanationError = nil
        showExplanationAlert = false
        Task {
            do {
                let result = try await AIService.shared.explain(
                    text: messageViewModel.message.text,
                    targetLanguage: languageSettings.preferredLanguageCode ?? LanguagePreferences.deviceLanguageCode
                )
                await MainActor.run {
                    explanationText = result.explanation
                    explanationTips = result.tips
                    isExplaining = false
                    showExplanationAlert = true
                }
            } catch {
                await MainActor.run {
                    explanationError = error.localizedDescription
                    isExplaining = false
                    showExplanationAlert = true
                }
            }
        }
    }

    private func clearExplanation() {
        explanationText = nil
        explanationTips = nil
        explanationError = nil
        showExplanationAlert = false
    }
}
#endif
