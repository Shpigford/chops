import SwiftUI
import AppKit
import os

@Observable
final class SkillEditorDocument {
    var editorContent: String = "" {
        didSet {
            guard !isLoading else { return }
            hasUnsavedChanges = editorContent != fullFileContent
        }
    }
    var preferredCursorLocation: Int?
    var editorFocusRequestID: Int?
    var hasUnsavedChanges = false
    var isLoadingRemote = false
    var isSavingRemote = false
    var showingSaveError = false
    var saveErrorMessage = ""

    private var fullFileContent: String = ""
    private var isLoading = false
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var nextEditorFocusRequestID = 0

    func load(from skill: Skill) {
        if skill.isRemote {
            loadRemote(skill)
        } else {
            loadLocal(skill)
        }
    }

    func save(to skill: Skill) {
        if skill.isRemote {
            saveRemote(skill)
        } else {
            saveLocal(skill)
        }
    }

    // MARK: - Local

    private func loadLocal(_ skill: Skill) {
        isLoading = true
        loadTask?.cancel()
        loadGeneration += 1

        let path = skill.filePath
        let fallback = skill.content
        let generation = loadGeneration
        let isNote = skill.itemKind == .note

        loadTask = Task.detached { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            let data: String
            if let fileData = try? String(contentsOfFile: path, encoding: .utf8) {
                data = fileData
            } else {
                AppLogger.fileIO.warning("Failed to read file, using cached content: \(path)")
                data = fallback
            }
            guard !Task.isCancelled else { return }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            AppLogger.fileIO.notice("Loaded \(path) in \(String(format: "%.3f", elapsed))s (\(data.count) chars)")

            await MainActor.run { [data] in
                guard let self, self.loadGeneration == generation else { return }
                self.editorContent = data
                self.fullFileContent = data
                self.preferredCursorLocation = self.initialCursorLocation(isNote: isNote, content: data)
                self.editorFocusRequestID = self.initialFocusRequestID(isNote: isNote, content: data)
                self.isLoading = false
                self.hasUnsavedChanges = false
                self.showingSaveError = false
                self.saveErrorMessage = ""
            }
        }
    }

    private func saveLocal(_ skill: Skill) {
        do {
            try editorContent.write(toFile: skill.filePath, atomically: true, encoding: .utf8)
            fullFileContent = editorContent
            hasUnsavedChanges = false

            updateIndexedContent(for: skill)

            let attrs = try? FileManager.default.attributesOfItem(atPath: skill.filePath)
            skill.fileModifiedDate = (attrs?[.modificationDate] as? Date) ?? skill.fileModifiedDate
            skill.fileSize = (attrs?[.size] as? Int) ?? skill.fileSize
            AppLogger.fileIO.info("Saved: \(skill.filePath)")
        } catch {
            AppLogger.fileIO.error("Save failed: \(error.localizedDescription)")
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }

    // MARK: - Remote

    private func loadRemote(_ skill: Skill) {
        guard let server = skill.remoteServer, let remotePath = skill.remotePath else {
            editorContent = skill.content
            fullFileContent = skill.content
            return
        }

        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let fallbackContent = skill.content
        let isNote = skill.itemKind == .note

        isLoading = true
        isLoadingRemote = true

        loadTask = Task {
            do {
                let content = try await SSHService.readFile(server, path: remotePath)
                guard !Task.isCancelled, loadGeneration == generation else { return }
                await MainActor.run {
                    guard self.loadGeneration == generation else { return }
                    editorContent = content
                    fullFileContent = content
                    preferredCursorLocation = initialCursorLocation(isNote: isNote, content: content)
                    editorFocusRequestID = initialFocusRequestID(isNote: isNote, content: content)
                    isLoading = false
                    isLoadingRemote = false
                    hasUnsavedChanges = false
                    showingSaveError = false
                    saveErrorMessage = ""
                }
            } catch {
                guard !Task.isCancelled, loadGeneration == generation else { return }
                await MainActor.run {
                    guard self.loadGeneration == generation else { return }
                    editorContent = fallbackContent
                    fullFileContent = fallbackContent
                    preferredCursorLocation = initialCursorLocation(isNote: isNote, content: fallbackContent)
                    editorFocusRequestID = initialFocusRequestID(isNote: isNote, content: fallbackContent)
                    isLoading = false
                    isLoadingRemote = false
                    hasUnsavedChanges = false
                    saveErrorMessage = "Failed to load from server: \(error.localizedDescription)"
                    showingSaveError = true
                }
            }
        }
    }

    private func saveRemote(_ skill: Skill) {
        guard let server = skill.remoteServer, let remotePath = skill.remotePath else {
            saveErrorMessage = "Missing remote server or path"
            showingSaveError = true
            return
        }

        isSavingRemote = true

        Task {
            do {
                try await SSHService.writeFile(server, path: remotePath, content: editorContent)
                await MainActor.run {
                    fullFileContent = editorContent
                    hasUnsavedChanges = false
                    isSavingRemote = false

                    updateIndexedContent(for: skill)
                    skill.fileModifiedDate = .now
                    skill.fileSize = editorContent.utf8.count
                }
            } catch {
                await MainActor.run {
                    saveErrorMessage = error.localizedDescription
                    showingSaveError = true
                    isSavingRemote = false
                }
            }
        }
    }

    private func updateIndexedContent(for skill: Skill) {
        if skill.itemKind == .note {
            let metadata = NotesService.metadata(for: editorContent)
            skill.name = metadata.title
            skill.skillDescription = metadata.excerpt
            skill.content = editorContent
            skill.frontmatter = [:]
            return
        }

        let parsed = FrontmatterParser.parse(editorContent)
        if !parsed.name.isEmpty {
            skill.name = parsed.name
        }
        skill.skillDescription = parsed.description
        skill.content = parsed.content
        skill.frontmatter = parsed.frontmatter
    }

    private func initialCursorLocation(isNote: Bool, content: String) -> Int? {
        guard isNote, content == NotesService.initialContent else {
            return nil
        }

        return NotesService.initialContent.utf16.count
    }

    private func initialFocusRequestID(isNote: Bool, content: String) -> Int? {
        guard isNote, content == NotesService.initialContent else {
            return nil
        }

        nextEditorFocusRequestID += 1
        return nextEditorFocusRequestID
    }

    deinit {
        loadTask?.cancel()
    }
}

struct SkillEditorView: View {
    @Bindable var document: SkillEditorDocument
    var isEditable: Bool = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if document.isLoadingRemote {
                VStack {
                    ProgressView("Loading from server...")
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HighlightedTextEditor(
                    text: $document.editorContent,
                    preferredCursorLocation: $document.preferredCursorLocation,
                    editorFocusRequestID: $document.editorFocusRequestID,
                    isEditable: isEditable
                )
                .accessibilityLabel("Skill editor")
            }

            HStack(spacing: 6) {
                if document.isSavingRemote {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            }
            .padding(12)
        }
    }
}

// MARK: - File menu notifications

extension Notification.Name {
    static let saveCurrentSkill = Notification.Name("saveCurrentSkill")
    static let newNoteRequested = Notification.Name("newNoteRequested")
}

// MARK: - Syntax-highlighted NSTextView wrapper

struct HighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var preferredCursorLocation: Int?
    @Binding var editorFocusRequestID: Int?
    var isEditable: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = FastTalkTextView()
        textView.isEditable = isEditable
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Font & colors
        textView.font = EditorTheme.editorFont
        textView.textColor = EditorTheme.textColor
        textView.backgroundColor = .clear

        // Line height with baseline centering
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = EditorTheme.editorLineHeight
        paragraph.maximumLineHeight = EditorTheme.editorLineHeight
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: EditorTheme.editorFont,
            .foregroundColor: EditorTheme.textColor,
            .paragraphStyle: paragraph,
            .baselineOffset: EditorTheme.editorBaselineOffset
        ]

        // Insets
        textView.textContainerInset = NSSize(width: EditorTheme.editorInsetX, height: EditorTheme.editorInsetTop)
        textView.textContainer?.lineFragmentPadding = 0

        // Layout
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.allowsNonContiguousLayout = true

        textView.insertionPointColor = EditorTheme.textColor

        // Set up highlighter and coordinator
        let highlighter = MarkdownSyntaxHighlighter()
        context.coordinator.highlighter = highlighter
        context.coordinator.textView = textView

        // Set text BEFORE attaching delegate to avoid triggering textDidChange during setup
        textView.string = text
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        // Initial highlight
        highlighter.highlightAll(textView.textStorage!)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? FastTalkTextView else { return }

        context.coordinator.parent = self
        textView.isEditable = isEditable

        // Re-highlight on appearance change
        let currentScheme = colorScheme
        if context.coordinator.lastColorScheme != currentScheme {
            context.coordinator.lastColorScheme = currentScheme
            textView.insertionPointColor = EditorTheme.textColor

            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = EditorTheme.editorLineHeight
            paragraph.maximumLineHeight = EditorTheme.editorLineHeight
            textView.typingAttributes = [
                .font: EditorTheme.editorFont,
                .foregroundColor: EditorTheme.textColor,
                .paragraphStyle: paragraph,
                .baselineOffset: EditorTheme.editorBaselineOffset
            ]

            context.coordinator.isHighlightingInProgress = true
            context.coordinator.highlighter?.highlightAll(textView.textStorage!)
            context.coordinator.isHighlightingInProgress = false
        }

        // Only update text if it changed externally (not from user typing)
        if !context.coordinator.isUpdating && textView.string != text {
            context.coordinator.isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.isHighlightingInProgress = true
            context.coordinator.highlighter?.highlightAll(textView.textStorage!)
            context.coordinator.isHighlightingInProgress = false
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdating = false
        }

        if let preferredCursorLocation {
            let clampedLocation = min(preferredCursorLocation, textView.string.utf16.count)
            let selectedRange = NSRange(location: clampedLocation, length: 0)
            textView.setSelectedRange(selectedRange)
            textView.scrollRangeToVisible(selectedRange)

            DispatchQueue.main.async {
                self.preferredCursorLocation = nil
            }
        }

        if let editorFocusRequestID {
            DispatchQueue.main.async {
                guard self.editorFocusRequestID == editorFocusRequestID else { return }
                guard let window = textView.window else { return }

                let selectedRange = textView.selectedRange()
                window.makeFirstResponder(textView)
                textView.setSelectedRange(selectedRange)
                textView.scrollRangeToVisible(selectedRange)
                self.editorFocusRequestID = nil
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedTextEditor
        var isUpdating = false
        var isHighlightingInProgress = false
        var highlighter: MarkdownSyntaxHighlighter?
        weak var textView: FastTalkTextView?
        var lastColorScheme: ColorScheme?

        init(_ parent: HighlightedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if isUpdating { return }

            // Highlight synchronously so colors appear on the same frame
            isHighlightingInProgress = true
            highlighter?.highlightAll(textView.textStorage!)
            isHighlightingInProgress = false

            // Update binding asynchronously to prevent re-entrant updateNSView
            let newText = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isUpdating = true
                self.parent.text = newText
                self.isUpdating = false
            }
        }
    }
}
