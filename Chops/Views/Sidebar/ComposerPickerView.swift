import SwiftUI

/// Shown when "Composer" is selected in the sidebar. Lets the user pick a template type.
struct ComposerPickerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            ForEach(WizardTemplateType.allCases) { templateType in
                Button {
                    appState.selectedTemplateType = templateType
                } label: {
                    Label(templateType.displayName, systemImage: templateType.icon)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Composer")
    }
}
