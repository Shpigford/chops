import SwiftUI
import SwiftData

struct CollectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \SkillCollection.sortOrder) private var collections: [SkillCollection]
    @State private var showingNewCollection = false
    @State private var newCollectionName = ""
    @State private var newCollectionIcon = "folder"
    @State private var editingCollectionID: PersistentIdentifier?
    @State private var editingName = ""
    @State private var errorMessage: String?
    @FocusState private var isRenameFocused: Bool

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hasDuplicateName(_ name: String, excluding collectionID: PersistentIdentifier? = nil) -> Bool {
        collections.contains { collection in
            collection.persistentModelID != collectionID &&
            collection.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func commitRename(_ collection: SkillCollection) {
        errorMessage = nil
        let trimmed = normalizedName(editingName)
        guard !trimmed.isEmpty else {
            editingCollectionID = nil
            return
        }
        guard trimmed != collection.name else {
            editingCollectionID = nil
            return
        }
        guard !hasDuplicateName(trimmed, excluding: collection.persistentModelID) else {
            errorMessage = "A collection with this name already exists"
            return
        }
        let oldName = collection.name
        collection.name = trimmed
        do {
            try modelContext.save()
            if appState.sidebarFilter == .collection(oldName) {
                appState.sidebarFilter = .collection(trimmed)
            }
            editingCollectionID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createCollection() {
        errorMessage = nil
        let trimmed = normalizedName(newCollectionName)
        guard !trimmed.isEmpty else {
            errorMessage = "Collection name can't be empty"
            return
        }
        guard !hasDuplicateName(trimmed) else {
            errorMessage = "A collection with this name already exists"
            return
        }

        let collection = SkillCollection(
            name: trimmed,
            icon: newCollectionIcon,
            sortOrder: collections.count
        )
        modelContext.insert(collection)

        do {
            try modelContext.save()
            newCollectionName = ""
            showingNewCollection = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleDrop(_ resolvedPaths: [String], onto collection: SkillCollection) -> Bool {
        var added = false
        for path in resolvedPaths {
            let descriptor = FetchDescriptor<Skill>(
                predicate: #Predicate { $0.resolvedPath == path }
            )
            guard let skill = try? modelContext.fetch(descriptor).first else { continue }
            guard !collection.skills.contains(where: { $0.resolvedPath == path }) else { continue }
            collection.skills.append(skill)
            added = true
        }
        if added { try? modelContext.save() }
        return added
    }

    private let availableIcons = [
        "folder", "star", "bookmark", "tag", "tray",
        "archivebox", "doc.text", "gearshape", "wrench",
        "hammer", "paintbrush", "wand.and.stars", "terminal",
        "network", "globe", "bolt", "flame", "leaf"
    ]

    var body: some View {
        ForEach(collections) { collection in
            if editingCollectionID == collection.persistentModelID {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isRenameFocused)
                    .onAppear {
                        isRenameFocused = true
                        DispatchQueue.main.async {
                            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                        }
                    }
                    .onSubmit {
                        commitRename(collection)
                    }
                    .onExitCommand {
                        editingCollectionID = nil
                    }
                    .tag(SidebarFilter.collection(collection.name))
            } else {
                Label(collection.name, systemImage: collection.icon)
                    .badge(collection.skills.count)
                    .tag(SidebarFilter.collection(collection.name))
                    .dropDestination(for: String.self) { resolvedPaths, _ in
                        handleDrop(resolvedPaths, onto: collection)
                    }
                    .contextMenu {
                        Button("Rename") {
                            errorMessage = nil
                            editingName = collection.name
                            editingCollectionID = collection.persistentModelID
                        }
                        Button("Delete", role: .destructive) {
                            modelContext.delete(collection)
                            try? modelContext.save()
                        }
                    }
            }
        }

        Button {
            errorMessage = nil
            showingNewCollection = true
        } label: {
            Label("New Collection", systemImage: "plus.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingNewCollection) {
            VStack(spacing: 12) {
                TextField("Collection name", text: $newCollectionName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(createCollection)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 6), spacing: 8) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button {
                            newCollectionIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.body)
                                .frame(width: 28, height: 28)
                                .background(
                                    newCollectionIcon == icon ?
                                    Color.accentColor.opacity(0.2) :
                                    Color.clear,
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                    }
                }

                HStack {
                    Button("Cancel") {
                        errorMessage = nil
                        showingNewCollection = false
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create", action: createCollection)
                    .disabled(normalizedName(newCollectionName).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 240)
        }
        .alert("Collection Error", isPresented: Binding(
            get: { errorMessage != nil && !showingNewCollection },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
