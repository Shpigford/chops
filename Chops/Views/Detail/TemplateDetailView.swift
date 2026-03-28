import SwiftUI

struct TemplateDetailView: View {
    let templateType: WizardTemplateType
    @State private var templateManager = TemplateManager.shared
    @State private var content: String = ""
    @State private var hasChanges = false
    @State private var showingResetConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Editor
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .onChange(of: content) { _, _ in
                    hasChanges = true
                }

            Divider()

            // Footer
            HStack {
                Text("Template for \(templateType.displayName.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if hasChanges {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button("Reset to Default") {
                    showingResetConfirm = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.caption)

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!hasChanges)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            loadTemplate()
        }
        .onChange(of: templateType) { _, _ in
            loadTemplate()
        }
        .confirmationDialog(
            "Reset Template?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset to Default", role: .destructive) {
                templateManager.resetToDefault(templateType)
                loadTemplate()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your custom template with the default version.")
        }
        .navigationTitle(templateType.displayName)
    }

    private func loadTemplate() {
        if let template = templateManager.template(for: templateType) {
            content = template.content
            hasChanges = false
        }
    }

    private func save() {
        let template = WizardTemplate(
            type: templateType,
            content: content,
            lastModified: Date()
        )
        templateManager.save(template)
        hasChanges = false
    }
}

#Preview {
    TemplateDetailView(templateType: .skill)
        .frame(width: 600, height: 400)
}

