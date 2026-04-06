import SwiftUI
import SwiftData

/// Transparent NSView overlay that intercepts AppKit hit-testing so it owns
/// cursor management (pointing hand) and click handling, beating NSTextView's
/// aggressive I-beam cursor.
private struct ClickableCursorOverlay: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> OverlayNSView {
        let view = OverlayNSView()
        view.onTap = action
        return view
    }

    func updateNSView(_ nsView: OverlayNSView, context: Context) {
        nsView.onTap = action
    }

    final class OverlayNSView: NSView {
        var onTap: (() -> Void)?
        private var area: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow],
                owner: self
            )
            addTrackingArea(area!)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            return bounds.contains(local) ? self : nil
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.pointingHand.set()
        }

        override func mouseEntered(with event: NSEvent) {
            NSCursor.pointingHand.set()
        }

        override func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
        }

        override func mouseDown(with event: NSEvent) {
            onTap?()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

struct SkillDetailView: View {
    private enum ActiveAlert: Identifiable {
        case confirmMakeGlobal
        case deleteError(String)
        case makeGlobalError(String)

        var id: String {
            switch self {
            case .confirmMakeGlobal:
                return "confirm-make-global"
            case .deleteError(let message):
                return "delete-error-\(message)"
            case .makeGlobalError(let message):
                return "make-global-error-\(message)"
            }
        }
    }

    @Bindable var skill: Skill
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("preferPreview") private var preferPreview = false
    @State private var document = SkillEditorDocument()
    @State private var activeAlert: ActiveAlert?
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var showingComposePanel = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        @Bindable var document = document

        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                if preferPreview {
                    SkillPreviewView(content: document.editorContent)
                        .transition(.opacity)
                } else {
                    SkillEditorView(document: document, isEditable: !skill.isReadOnly)
                        .transition(.opacity)
                }

                if !showingComposePanel && !skill.isReadOnly {
                    composeFloatingButton
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: preferPreview)

            // Inline compose panel
            if showingComposePanel {
                ComposePanel(
                    content: $document.editorContent,
                    isVisible: $showingComposePanel,
                    skillName: skill.name,
                    skillDescription: skill.skillDescription,
                    frontmatter: skill.frontmatter,
                    filePath: skill.filePath,
                    workingDirectory: URL(fileURLWithPath: skill.filePath).deletingLastPathComponent(),
                    templateType: WizardTemplateType(rawValue: skill.itemKind.rawValue) ?? .skill,
                    onAccept: { document.save(to: skill) }
                )
                .id(skill.filePath)
                .transition(.opacity)
            }

            Divider()

            SkillMetadataBar(skill: skill)
        }
        .navigationTitle(skill.name)
        .onAppear {
            document.load(from: skill)
        }
        .onChange(of: skill.filePath) {
            autoSaveTask?.cancel()
            document.load(from: skill)
        }
        .onChange(of: document.editorContent) {
            guard !skill.isReadOnly else { return }

            if skill.itemKind == .note {
                let metadata = NotesService.metadata(for: document.editorContent)
                skill.name = metadata.title
                skill.skillDescription = metadata.excerpt
            }

            autoSaveTask?.cancel()
            autoSaveTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, document.hasUnsavedChanges else { return }
                document.save(to: skill)
            }
        }
        .onDisappear {
            autoSaveTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveCurrentSkill)) { _ in
            guard !skill.isReadOnly else { return }
            document.save(to: skill)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleComposePanelRequested)) { _ in
            guard !skill.isReadOnly else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                showingComposePanel.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditPreviewRequested)) { _ in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                preferPreview.toggle()
            }
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
                .help("Toggle Edit / Preview")
            }
            ToolbarItem {
                Button {
                    skill.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: skill.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(skill.isFavorite ? Color(NSColor.systemYellow) : .secondary)
                }
                .help(skill.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                .accessibilityLabel(skill.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            if !skill.isRemote {
                ToolbarItem {
                    Button {
                        NSWorkspace.shared.selectFile(skill.filePath, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Show in Finder")
                    .accessibilityLabel("Show in Finder")
                }
            }
            if !skill.isReadOnly {
                ToolbarItem {
                    Button {
                        showingDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .help("Delete \(skill.displayTypeName)")
                    .accessibilityLabel("Delete \(skill.displayTypeName)")
                }
            }
            if skill.canMakeGlobal {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeAlert = .confirmMakeGlobal
                    } label: {
                        Image(systemName: "globe")
                    }
                    .help("Make Global")
                    .accessibilityLabel("Make Global")
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(skill.name)\"?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSkill()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves the \(skill.displayTypeName.lowercased()) to Trash.")
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmMakeGlobal:
                return Alert(
                    title: Text("Make \"\(skill.name)\" Global?"),
                    message: Text("This will move the skill to ~/.agents/skills/ and symlink it to all installed agents."),
                    primaryButton: .cancel(),
                    secondaryButton: .default(Text("Make Global")) {
                        makeSkillGlobal()
                    }
                )
            case .deleteError(let message):
                return Alert(
                    title: Text("Move to Trash Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .makeGlobalError(let message):
                return Alert(
                    title: Text("Make Global Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var composeFloatingButton: some View {
        Image(systemName: "sparkles")
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color(NSColor.alternateSelectedControlTextColor))
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.accentColor))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .overlay(ClickableCursorOverlay(action: { [self] in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    showingComposePanel.toggle()
                }
            }))
            .help("Compose with AI")
            .padding(16)
    }

    private func makeSkillGlobal() {
        do {
            try skill.makeGlobal()
            try? modelContext.save()
        } catch {
            activeAlert = .makeGlobalError(error.localizedDescription)
        }
    }

    private func deleteSkill() {
        guard !skill.isReadOnly, !skill.isRemote else { return }
        do {
            let operation = try SkillTrashOperation.trash([skill])
            modelContext.delete(skill)
            do {
                try modelContext.save()
            } catch {
                _ = try? operation.restore(in: modelContext)
                try? modelContext.save()
                throw error
            }

            appState.selectOnly(nil)

            undoManager?.registerUndo(withTarget: modelContext) { context in
                do {
                    let restoredSkills = try operation.restore(in: context)
                    try context.save()

                    if let restoredSkill = restoredSkills.first {
                        appState.selectOnly(restoredSkill)
                    }
                } catch {
                    activeAlert = .deleteError(error.localizedDescription)
                }
            }
            undoManager?.setActionName("Move to Trash")
        } catch {
            activeAlert = .deleteError(error.localizedDescription)
        }
    }
}
