import SwiftUI

struct ProfileView: View {
    let user: AuthenticatedUser?

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Profile")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let user {
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

