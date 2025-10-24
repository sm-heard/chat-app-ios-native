import StreamChat
import SwiftUI

struct ChannelCreationView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: ChannelCreationViewModel
    @FocusState private var nameFieldFocused: Bool

    init(chatClient: ChatClient, currentUser: AuthenticatedUser) {
        _viewModel = StateObject(wrappedValue: ChannelCreationViewModel(chatClient: chatClient, currentUser: currentUser))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isGroup {
                    TextField("Channel name (optional)", text: $viewModel.channelName)
                        .textFieldStyle(.roundedBorder)
                        .padding([.horizontal, .top])
                        .focused($nameFieldFocused)
                }

                if viewModel.isLoading {
                    ProgressView("Loading users…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if viewModel.users.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                        Text("No other users yet")
                            .font(.headline)
                        Text("Invite someone else to sign in with Apple to start chatting.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(viewModel.users, id: \.id) { user in
                        Button {
                            viewModel.toggleSelection(for: user.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.name ?? user.id)
                                        .foregroundStyle(.primary)
                                    Text(user.isOnline ? "Online" : "Offline")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.selectedUserIds.contains(user.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }

                if let error = viewModel.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding([.horizontal, .bottom])
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: createChannel) {
                        if viewModel.isCreating {
                            ProgressView()
                        } else {
                            Text(viewModel.buttonTitle)
                        }
                    }
                    .disabled(!viewModel.canCreate || viewModel.isCreating)
                }
            }
        }
        .task {
            await viewModel.loadUsersIfNeeded()
        }
        .onAppear {
            nameFieldFocused = viewModel.isGroup
        }
    }

    private func createChannel() {
        Task {
            if await viewModel.createChannel() {
                dismiss()
            }
        }
    }
}

private final class ChannelCreationViewModel: ObservableObject {
    @Published var users: [ChatUser] = []
    @Published var selectedUserIds: Set<String> = []
    @Published var channelName: String = ""
    @Published var error: String?
    @Published var isLoading: Bool = false
    @Published var isCreating: Bool = false

    var canCreate: Bool {
        !selectedUserIds.isEmpty
    }

    var isGroup: Bool {
        selectedUserIds.count > 1
    }

    var buttonTitle: String {
        if isCreating {
            return "Creating…"
        }
        return isGroup ? "Create" : "Start Chat"
    }

    private let chatClient: ChatClient
    private let currentUser: AuthenticatedUser
    private var didLoadUsers = false

    init(chatClient: ChatClient, currentUser: AuthenticatedUser) {
        self.chatClient = chatClient
        self.currentUser = currentUser
    }

    func loadUsersIfNeeded() async {
        guard !didLoadUsers else { return }
        await loadUsers()
    }

    @MainActor
    func toggleSelection(for userId: String) {
        if selectedUserIds.contains(userId) {
            selectedUserIds.remove(userId)
        } else {
            selectedUserIds.insert(userId)
        }
    }

    @MainActor
    func createChannel() async -> Bool {
        guard canCreate else { return false }
        isCreating = true
        error = nil
        defer { isCreating = false }

        do {
            let members = Set(selectedUserIds).union([currentUser.id])
            if members.count == 2 {
                try await createDirectMessageChannel(with: Array(members))
            } else {
                let trimmedName = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
                try await createGroupChannel(name: trimmedName, members: members)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func loadUsers() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        let filter: Filter<UserListFilterScope> = .notEqual(.id, to: currentUser.id)
        let query = UserListQuery(filter: filter, sort: [.init(key: .name, isAscending: true)], pageSize: 50)
        let controller = chatClient.userListController(query: query)

        let result = await withCheckedContinuation { continuation in
            controller.synchronize { error in
                continuation.resume(returning: error)
            }
        }

        await MainActor.run {
            self.didLoadUsers = true
            self.isLoading = false
            if let result {
                self.error = result.localizedDescription
                self.users = []
            } else {
                self.users = Array(controller.users)
            }
        }
    }

    private func createDirectMessageChannel(with members: [String]) async throws {
        let controller = try chatClient.channelController(createDirectMessageChannelWith: Set(members), extraData: [:])
        if let error = await synchronize(controller) {
            throw error
        }
    }

    private func createGroupChannel(name: String, members: Set<String>) async throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortId = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))
        let channelId = ChannelId(type: .messaging, id: "group-\(shortId)")
        let controller = try chatClient.channelController(
            createChannelWithId: channelId,
            name: cleanName.isEmpty ? nil : cleanName,
            imageURL: nil,
            members: members
        )

        if let error = await synchronize(controller) {
            throw error
        }

        let others = members.subtracting([currentUser.id])
        if !others.isEmpty {
            if let addError = await addMembers(others, controller: controller) {
                throw addError
            }
        }
    }

    private func synchronize(_ controller: ChatChannelController) async -> Error? {
        await withCheckedContinuation { continuation in
            controller.synchronize { error in
                continuation.resume(returning: error)
            }
        }
    }

    private func addMembers(_ userIds: Set<String>, controller: ChatChannelController) async -> Error? {
        await withCheckedContinuation { continuation in
            controller.addMembers(userIds: userIds) { error in
                continuation.resume(returning: error)
            }
        }
    }
}
