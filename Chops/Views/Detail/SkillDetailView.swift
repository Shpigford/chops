import SwiftUI
import SwiftData

struct SkillDetailView: View {
    @Bindable var skill: Skill
    @Environment(\.modelContext) private var modelContext
    @State private var isPreviewMode = false

    var body: some View {
        VStack(spacing: 0) {
            SkillEditorView(skill: skill, isPreviewMode: $isPreviewMode)

            Divider()

            SkillMetadataBar(skill: skill)
        }
        .navigationTitle(skill.name)
        .onChange(of: skill.filePath) {
            isPreviewMode = false
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isPreviewMode.toggle()
                } label: {
                    Image(systemName: isPreviewMode ? "book.fill" : "book")
                }
                .help(isPreviewMode ? "Edit" : "Preview")
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
