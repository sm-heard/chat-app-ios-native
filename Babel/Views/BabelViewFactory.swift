#if canImport(StreamChatSwiftUI) && canImport(StreamChat)
import StreamChat
import StreamChatSwiftUI
import SwiftUI

final class BabelViewFactory: ViewFactory {
    let chatClient: ChatClient

    init(chatClient: ChatClient) {
        self.chatClient = chatClient
    }

    func makeMessageTranslationFooterView(
        messageViewModel: MessageViewModel
    ) -> some View {
        BabelMessageTranslationFooterView(messageViewModel: messageViewModel)
    }

    func makeMessageContainerView(
        channel: ChatChannel,
        message: ChatMessage,
        width: CGFloat?,
        showsAllInfo: Bool,
        isInThread: Bool,
        scrolledId: Binding<String?>,
        quotedMessage: Binding<ChatMessage?>,
        onLongPress: @escaping (MessageDisplayInfo) -> Void,
        isLast: Bool
    ) -> some View {
        let viewModel = MessageViewModel(message: message, channel: channel)

        return VStack(alignment: message.isRightAligned ? .trailing : .leading, spacing: 0) {
            MessageContainerView(
                factory: self,
                channel: channel,
                message: message,
                width: width,
                showsAllInfo: showsAllInfo,
                isInThread: isInThread,
                isLast: isLast,
                scrolledId: scrolledId,
                quotedMessage: quotedMessage,
                onLongPress: onLongPress,
                viewModel: viewModel
            )

            BabelMessageTranslationFooterView(messageViewModel: viewModel)
                .padding(.top, 4)
        }
    }

    func makeComposerInputView(
        text: Binding<String>,
        selectedRangeLocation: Binding<Int>,
        command: Binding<ComposerCommand?>,
        addedAssets: [AddedAsset],
        addedFileURLs: [URL],
        addedCustomAttachments: [CustomAttachment],
        quotedMessage: Binding<ChatMessage?>,
        maxMessageLength: Int?,
        cooldownDuration: Int,
        onCustomAttachmentTap: @escaping (CustomAttachment) -> Void,
        shouldScroll: Bool,
        removeAttachmentWithId: @escaping (String) -> Void
    ) -> some View {
        BabelComposerInputView(
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
    }
}
#endif
