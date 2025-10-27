#if canImport(StreamChatSwiftUI) && canImport(StreamChat)
import StreamChat
import StreamChatSwiftUI
import SwiftUI

struct BabelComposerInputView: View {
    let text: Binding<String>
    let selectedRangeLocation: Binding<Int>
    let command: Binding<ComposerCommand?>
    let addedAssets: [AddedAsset]
    let addedFileURLs: [URL]
    let addedCustomAttachments: [CustomAttachment]
    let quotedMessage: Binding<ChatMessage?>
    let maxMessageLength: Int?
    let cooldownDuration: Int
    let onCustomAttachmentTap: (CustomAttachment) -> Void
    let shouldScroll: Bool
    let removeAttachmentWithId: (String) -> Void

    @EnvironmentObject private var viewModel: MessageComposerViewModel
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @Injected(\.fonts) private var fonts
    @Injected(\.colors) private var colors

    @State private var selectedTone: ToneStyle = .neutral
    @State private var isRewriting = false
    @State private var rewriteError: String?
    @State private var originalTextBeforeRewrite: String?

    @State private var suggestions: [String] = []
    @State private var isFetchingSuggestions = false
    @State private var suggestionsError: String?

    @State private var isTranslating = false
    @State private var translateError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toneAndActionsSection
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(action: { applySuggestion(suggestion) }) {
                                Text(suggestion)
                                    .font(fonts.footnote)
                                    .foregroundColor(Color(colors.text))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(colors.background6))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            if let suggestionsError {
                Text(suggestionsError)
                    .font(fonts.footnote)
                    .foregroundColor(.orange)
            } else if let rewriteError {
                Text(rewriteError)
                    .font(fonts.footnote)
                    .foregroundColor(.orange)
            } else if let translateError {
                Text(translateError)
                    .font(fonts.footnote)
                    .foregroundColor(.orange)
            }

            DefaultViewFactory.shared.makeComposerInputView(
                text: text,
                selectedRangeLocation: selectedRangeLocation,
                command: command,
                addedAssets: addedAssets,
                addedFileURLs: addedFileURLs,
                addedCustomAttachments: addedCustomAttachments,
                quotedMessage: quotedMessage,
                maxMessageLength: maxMessageLength,
                cooldownDuration: cooldownDuration,
                onCustomAttachmentTap: onCustomAttachmentTap,
                shouldScroll: shouldScroll,
                removeAttachmentWithId: removeAttachmentWithId
            )
            .environmentObject(viewModel)
        }
    }

    private var toneAndActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Tone", selection: $selectedTone) {
                Text("Formal").tag(ToneStyle.formal)
                Text("Neutral").tag(ToneStyle.neutral)
                Text("Casual").tag(ToneStyle.casual)
            }
            .pickerStyle(.segmented)
            .disabled(isRewriting || viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .onChange(of: selectedTone) { newValue in
                handleToneChange(style: newValue)
            }

            HStack(spacing: 12) {
                Button(action: fetchSuggestions) {
                    if isFetchingSuggestions {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Suggestions")
                    }
                }
                .disabled(isFetchingSuggestions)

                if let targetLanguage = detectTargetLanguage() {
                    Button(action: { translateAndReplace(targetLanguage: targetLanguage) }) {
                        if isTranslating {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text("Translate to \(localizedName(for: targetLanguage))")
                        }
                    }
                    .disabled(isTranslating || viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .font(fonts.footnote)
        }
    }

    private func handleToneChange(style: ToneStyle) {
        guard !viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard style != .neutral else {
            if let original = originalTextBeforeRewrite {
                text.wrappedValue = original
                originalTextBeforeRewrite = nil
            }
            rewriteError = nil
            return
        }

        if originalTextBeforeRewrite == nil {
            originalTextBeforeRewrite = text.wrappedValue
        }

        rewriteError = nil
        isRewriting = true
        Task {
            do {
                let result = try await AIService.shared.rewrite(
                    text: originalTextBeforeRewrite ?? text.wrappedValue,
                    targetLanguage: preferredLanguageCode,
                    style: style
                )
                await MainActor.run {
                    text.wrappedValue = result.rewritten
                    isRewriting = false
                }
            } catch {
                await MainActor.run {
                    rewriteError = error.localizedDescription
                    isRewriting = false
                    selectedTone = .neutral
                    if let original = originalTextBeforeRewrite {
                        text.wrappedValue = original
                        originalTextBeforeRewrite = nil
                    }
                }
            }
        }
    }

    private func fetchSuggestions() {
        suggestionsError = nil
        isFetchingSuggestions = true
        Task {
            do {
                let history = gatherRecentMessages()
                guard !history.isEmpty else {
                    await MainActor.run {
                        suggestions = []
                        suggestionsError = "Not enough context for suggestions."
                        isFetchingSuggestions = false
                    }
                    return
                }

                let result = try await AIService.shared.smartReplies(
                    messages: history,
                    targetLanguage: preferredLanguageCode
                )
                await MainActor.run {
                    suggestions = result.suggestions
                    suggestionsError = nil
                    isFetchingSuggestions = false
                }
            } catch {
                await MainActor.run {
                    suggestionsError = error.localizedDescription
                    suggestions = []
                    isFetchingSuggestions = false
                }
            }
        }
    }

    private func applySuggestion(_ suggestion: String) {
        text.wrappedValue = suggestion
        suggestions = []
    }

    private func translateAndReplace(targetLanguage: String) {
        guard !viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        translateError = nil
        isTranslating = true
        Task {
            do {
                let result = try await AIService.shared.translate(
                    text: text.wrappedValue,
                    sourceLanguage: preferredLanguageCode,
                    targetLanguage: targetLanguage,
                    messageId: nil
                )
                await MainActor.run {
                    text.wrappedValue = result.translation
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    translateError = error.localizedDescription
                    isTranslating = false
                }
            }
        }
    }

    private func gatherRecentMessages() -> [SmartReplyContextMessage] {
        let currentUserId = viewModel.channelController.client.currentUserId
        let messages = viewModel.channelController.messages

        return messages
            .suffix(6)
            .compactMap { message -> SmartReplyContextMessage? in
                guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let role: SmartReplyContextMessage.Role = message.author.id == currentUserId ? .user : .other
                let lang = userLanguage(for: message.author) ?? LanguageDetector.shared.detectLanguageCode(for: message.text)
                return SmartReplyContextMessage(role: role, text: message.text, language: lang)
            }
    }

    private func detectTargetLanguage() -> String? {
        let currentUserId = viewModel.channelController.client.currentUserId

        for message in viewModel.channelController.messages.reversed() {
            guard message.author.id != currentUserId else { continue }
            guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let language = userLanguage(for: message.author), !LanguageDetector.shared.languagesMatch(language, preferredLanguageCode) {
                return language
            }
            if let detected = LanguageDetector.shared.detectLanguageCode(for: message.text), !LanguageDetector.shared.languagesMatch(detected, preferredLanguageCode) {
                return detected
            }
        }

        return nil
    }

    private func localizedName(for languageCode: String) -> String {
        Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode.uppercased()
    }

    private var preferredLanguageCode: String {
        languageSettings.preferredLanguageCode ?? LanguagePreferences.deviceLanguageCode
    }

    private func userLanguage(for user: ChatUser) -> String? {
        if let languageCode = user.language?.languageCode, !languageCode.isEmpty {
            return languageCode
        }
        if case let .string(extraLanguage)? = user.extraData["language"], !extraLanguage.isEmpty {
            return extraLanguage
        }
        return nil
    }
}
#endif
