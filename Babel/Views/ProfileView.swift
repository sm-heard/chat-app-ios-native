import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @State private var showingLanguagePicker = false

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Profile")
                .sheet(isPresented: $showingLanguagePicker) {
                    LanguageSelectionView(
                        selectedCode: languageSettings.preferredLanguageCode,
                        onSelect: { option in
                            languageSettings.setPreferredLanguage(code: option.code)
                            Task { await viewModel.updatePreferredLanguageIfNeeded(code: option.code) }
                            showingLanguagePicker = false
                        },
                        onCancel: { showingLanguagePicker = false }
                    )
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let user = viewModel.currentUser {
            List {
                Section(header: Text("Account")) {
                    ProfileRow(label: "Display Name", value: user.name ?? "—")
                    ProfileRow(label: "Email", value: user.email ?? "—")
                }

                Section(header: Text("Identifiers")) {
                    ProfileRow(label: "User ID", value: user.id)
                    if let appleId = user.appleUserId {
                        ProfileRow(label: "Apple ID", value: appleId)
                    }
                }

                Section(header: Text("Sign-In State")) {
                    ProfileRow(label: "Identity Token", value: tokenStatus(user.identityToken))
                    ProfileRow(label: "Refresh Token", value: tokenStatus(user.refreshToken))
                }

                Section(header: Text("Language")) {
                    Button {
                        showingLanguagePicker = true
                    } label: {
                        HStack {
                            Text("Preferred Language")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(languageSettings.preferredLanguageOption?.displayName ?? languageSettings.preferredLanguageCode?.uppercased() ?? "Select")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
        } else {
            ProgressView("Loading profile…")
                .progressViewStyle(.circular)
        }
    }

    private func tokenStatus(_ token: String?) -> String {
        guard let token, !token.isEmpty else {
            return "Missing"
        }
        return "Stored"
    }
}

private struct ProfileRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}
