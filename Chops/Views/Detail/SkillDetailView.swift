import SwiftUI
import SwiftData

struct SkillDetailView: View {
    private enum ActiveAlert: Identifiable {
        case confirmDelete
        case deleteError(String)

        var id: String {
            switch self {
            case .confirmDelete:
                return "confirm-delete"
            case .deleteError(let message):
                return "delete-error-\(message)"
            }
        }
    }

    @Bindable var skill: Skill
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @AppStorage("preferPreview") private var preferPreview = false
    @State private var document = SkillEditorDocument()
    @State private var activeAlert: ActiveAlert?

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
        .onReceive(NotificationCenter.default.publisher(for: .saveCurrentSkill)) { _ in
            document.save(to: skill)
        }
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
            if !skill.isRemote {
                ToolbarItem {
                    Button {
                        NSWorkspace.shared.selectFile(skill.filePath, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Show in Finder")
                }
            }
            ToolbarItem {
                Button {
                    activeAlert = .confirmDelete
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete Skill")
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmDelete:
                return Alert(
                    title: Text("Delete Skill?"),
                    message: Text("This will permanently delete \"\(skill.name)\" from disk."),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteSkill()
                    },
                    secondaryButton: .cancel()
                )
            case .deleteError(let message):
                return Alert(
                    title: Text("Delete Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func deleteSkill() {
        do {
            try skill.deleteFromDisk()
            appState.selectedSkill = nil
            modelContext.delete(skill)
            try modelContext.save()
        } catch {
            activeAlert = .deleteError(error.localizedDescription)
        }
    }
}
