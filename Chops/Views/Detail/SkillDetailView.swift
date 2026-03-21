import SwiftUI
import SwiftData

struct SkillDetailView: View {
    @Bindable var skill: Skill
    @Environment(\.modelContext) private var modelContext
    @AppStorage("preferPreview") private var preferPreview = false
    @State private var document = SkillEditorDocument()

    var body: some View {
        @Bindable var document = document

        VStack(spacing: 0) {
            if preferPreview {
                SkillPreviewView(content: document.editorContent)
            } else {
                SkillEditorView(document: document)
            }

            Divider()

            SkillMetadataBar(skill: skill)
        }
        .navigationTitle(skill.name)
        .onAppear {
            document.load(from: skill)
        }
        .onChange(of: skill.filePath) {
            document.load(from: skill)
        }
        .focusedValue(\.saveAction, SaveAction(action: { document.save(to: skill) }))
        .alert("Save Error", isPresented: $document.showingSaveError) {
            Button("OK") {}
        } message: {
            Text(document.saveErrorMessage)
        }
        .toolbar {
            ToolbarItem {
                Picker("Mode", selection: $preferPreview) {
                    Image(systemName: "pencil").tag(false)
                    Image(systemName: "eye").tag(true)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button {
                    skill.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: skill.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(skill.isFavorite ? .yellow : .secondary)
                }
            }
            ToolbarItem {
                Button {
                    NSWorkspace.shared.selectFile(skill.filePath, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }
                .help("Show in Finder")
            }
        }
    }
}
