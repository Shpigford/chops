import SwiftUI
import SwiftData

struct SkillMetadataBar: View {
    @Bindable var skill: Skill
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillCollection.sortOrder) private var allCollections: [SkillCollection]
    @State private var showingCollectionPicker = false

    var body: some View {
        HStack(spacing: 16) {
            if skill.itemKind == .note {
                Text(displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(installedPathsSummary)

                Divider().frame(height: 16)

                Text(formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider().frame(height: 16)

                collectionPickerButton

                Spacer()

                Text(skill.fileModifiedDate.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(skill.toolSources) { tool in
                        ToolIcon(tool: tool, size: 14)
                    }
                }
                .help(installedPathsSummary)
                .accessibilityLabel("Installed in: \(installedPathsSummary)")

                Divider().frame(height: 16)

                if skill.isRemote, let server = skill.remoteServer {
                    Label {
                        Text(server.label)
                    } icon: {
                        Image(systemName: "server.rack")
                    }
                    .font(.caption)
                    .foregroundStyle(.indigo)
                }

                Divider().frame(height: 16)

                Text(skill.isRemote ? (skill.remotePath ?? "") : displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(skill.isRemote ? (skill.remotePath ?? "") : installedPathsSummary)

                Divider().frame(height: 16)

                Text(formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider().frame(height: 16)

                collectionPickerButton

                Spacer()

                Text(skill.fileModifiedDate.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var collectionPickerButton: some View {
        Button {
            showingCollectionPicker.toggle()
        } label: {
            Image(systemName: "tray")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Assign to Collection")
        .accessibilityLabel("Assign to Collection")
        .popover(isPresented: $showingCollectionPicker) {
            collectionPickerContent
        }
    }

    private var displayPath: String {
        let additionalCount = max(0, displayInstalledPaths.count - 1)
        let suffix = additionalCount > 0 ? " (+\(additionalCount))" : ""
        return abbreviatedFilePath + suffix
    }

    private var abbreviatedFilePath: String {
        skill.filePath.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(skill.fileSize), countStyle: .file)
    }

    private var installedPathsSummary: String {
        displayInstalledPaths
            .map { $0.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") }
            .joined(separator: "\n")
    }

    private var displayInstalledPaths: [String] {
        let otherPaths = skill.installedPaths
            .filter { $0 != skill.filePath }
            .sorted()
        return [skill.filePath] + otherPaths
    }

    private var collectionPickerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(skill.itemKind == .note ? "Category" : "Collections")
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(allCollections) { collection in
                let isAssigned = skill.collections.contains(where: { $0.name == collection.name })
                Button {
                    if isAssigned {
                        skill.collections.removeAll { $0.name == collection.name }
                    } else {
                        skill.collections.append(collection)
                    }
                    try? modelContext.save()
                } label: {
                    HStack {
                        Image(systemName: collection.icon)
                        Text(collection.name)
                        Spacer()
                        if isAssigned {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if allCollections.isEmpty {
                Text(skill.itemKind == .note ? "No categories yet" : "No collections yet")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 200)
    }
}
