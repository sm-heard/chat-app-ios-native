import SwiftUI

struct LanguageSelectionView: View {
    let selectedCode: String?
    let onSelect: (LanguageOption) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            List(LanguageSettings.availableLanguages) { option in
                Button {
                    onSelect(option)
                } label: {
                    HStack {
                        Text(option.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if option.code == selectedCode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .navigationTitle("Select Language")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
