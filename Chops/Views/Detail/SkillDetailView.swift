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
        case confirmDelete
        case confirmMakeGlobal
        case deleteError(String)
        case makeGlobalError(String)

        var id: String {
            switch self {
            case .confirmDelete:
                return "confirm-delete"
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
    @Environment(AppState.self) private var appState
    @AppStorage("preferPreview") private var preferPreview = false
    @State private var document = SkillEditorDocument()
    @State private var activeAlert: ActiveAlert?
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var showingComposePanel = false

    var body: some View {
        @Bindable var document = document

        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                if preferPreview {
                    SkillPreviewView(content: document.editorContent)
                } else {
                    SkillEditorView(document: document, isEditable: !skill.isReadOnly)
                }

                if !showingComposePanel && !skill.isReadOnly {
                    composeFloatingButton
                }
            }

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
            if !skill.isReadOnly {
                ToolbarItem {
                    Button {
                        activeAlert = .confirmDelete
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete \(skill.displayTypeName)")
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
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .confirmMakeGlobal:
                return Alert(
                    title: Text("Make \"\(skill.name)\" Global?"),
                    message: Text("This will move the skill to ~/.agents/skills/ and symlink it to all installed agents."),
                    primaryButton: .default(Text("Make Global")) {
                        makeSkillGlobal()
                    },
                    secondaryButton: .cancel()
                )
            case .confirmDelete:
                return Alert(
                    title: Text("Delete \(skill.displayTypeName)?"),
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
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.accentColor))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .overlay(ClickableCursorOverlay(action: { [self] in showingComposePanel.toggle() }))
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
        guard !skill.isReadOnly else { return }
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
