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
    var hasUnsavedChanges = false
    var isLoadingRemote = false
    var isSavingRemote = false
    var showingSaveError = false
    var saveErrorMessage = ""

    private var fullFileContent: String = ""
    private var isLoading = false
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

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

            let parsed = FrontmatterParser.parse(editorContent)
            if !parsed.name.isEmpty {
                skill.name = parsed.name
            }
            skill.skillDescription = parsed.description
            skill.content = parsed.content
            skill.frontmatter = parsed.frontmatter

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

                    let parsed = FrontmatterParser.parse(editorContent)
                    if !parsed.name.isEmpty {
                        skill.name = parsed.name
                    }
                    skill.skillDescription = parsed.description
                    skill.content = parsed.content
                    skill.frontmatter = parsed.frontmatter
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

    deinit {
        loadTask?.cancel()
    }
}

struct SkillEditorView: View {
    @Bindable var document: SkillEditorDocument

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if document.isLoadingRemote {
                VStack {
                    ProgressView("Loading from server...")
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HighlightedTextEditor(text: $document.editorContent)
            }

            HStack(spacing: 6) {
                if document.isSavingRemote {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if document.hasUnsavedChanges {
                    Text("Modified")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Save Action via FocusedValues for Cmd+S menu support

struct SaveAction {
    let action: () -> Void
}

struct SaveActionKey: FocusedValueKey {
    typealias Value = SaveAction
}

extension FocusedValues {
    var saveAction: SaveAction? {
        get { self[SaveActionKey.self] }
        set { self[SaveActionKey.self] = newValue }
    }
}

// MARK: - Syntax-highlighted NSTextView wrapper

struct HighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.backgroundColor = .clear

        // Prevent NSTextView's intrinsic content size from propagating up through
        // the NavigationSplitView constraint chain. Without this, large documents
        // trigger recursive _informContainerThatSubviewsNeedUpdateConstraints calls
        // that crash AppKit's constraint solver.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        textView.string = text
        MarkdownHighlighter.highlight(textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            // Defer the text update to the next run loop tick so it doesn't
            // overlap with SwiftUI's constraint update pass. This prevents the
            // recursive _informContainerThatSubviewsNeedUpdateConstraints crash.
            let newText = text
            DispatchQueue.main.async {
                guard textView.string != newText else { return }
                let selectedRanges = textView.selectedRanges
                textView.string = newText
                MarkdownHighlighter.highlight(textView)
                textView.selectedRanges = selectedRanges
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedTextEditor
        weak var textView: NSTextView?
        private var isUpdating = false

        init(_ parent: HighlightedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView else { return }
            isUpdating = true
            parent.text = textView.string
            MarkdownHighlighter.highlight(textView)
            isUpdating = false
        }
    }
}

// MARK: - Markdown + YAML Frontmatter Highlighter

enum MarkdownHighlighter {
    private static let muted = NSColor.secondaryLabelColor
    private static let faintBg = NSColor.quaternaryLabelColor

    static func highlight(_ textView: NSTextView) {
        let text = textView.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard let storage = textView.textStorage else { return }

        storage.beginEditing()

        let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)

        let lines = text.components(separatedBy: "\n")
        var offset = 0
        var inFrontmatter = false
        var inCodeBlock = false

        for (index, line) in lines.enumerated() {
            let lineRange = NSRange(location: offset, length: (line as NSString).length)

            // Frontmatter — just dim the whole block
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                if index == 0 {
                    inFrontmatter = true
                    storage.addAttribute(.foregroundColor, value: muted, range: lineRange)
                    offset += line.count + 1
                    continue
                } else if inFrontmatter {
                    inFrontmatter = false
                    storage.addAttribute(.foregroundColor, value: muted, range: lineRange)
                    offset += line.count + 1
                    continue
                }
            }

            if inFrontmatter {
                storage.addAttribute(.foregroundColor, value: muted, range: lineRange)
                offset += line.count + 1
                continue
            }

            // Code blocks — subtle background, no color change
            if line.hasPrefix("```") {
                inCodeBlock.toggle()
                storage.addAttribute(.foregroundColor, value: muted, range: lineRange)
                offset += line.count + 1
                continue
            }

            if inCodeBlock {
                storage.addAttribute(.backgroundColor, value: faintBg, range: lineRange)
                offset += line.count + 1
                continue
            }

            // Headings — just bold + sized, same color
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6 && (line.count == level || line[line.index(line.startIndex, offsetBy: level)] == " ") {
                    let size: CGFloat = [18, 16, 14, 13, 13, 13][min(level - 1, 5)]
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .bold), range: lineRange)
                    offset += line.count + 1
                    continue
                }
            }

            // Inline: bold gets bold, inline code gets faint bg, that's it
            let nsLine = line as NSString
            applyRegex(#"\*\*(.+?)\*\*"#, to: nsLine, lineOffset: lineRange.location, storage: storage, attrs: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
            ])
            applyRegex(#"__(.+?)__"#, to: nsLine, lineOffset: lineRange.location, storage: storage, attrs: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
            ])
            applyRegex(#"`([^`]+)`"#, to: nsLine, lineOffset: lineRange.location, storage: storage, attrs: [
                .backgroundColor: faintBg
            ])

            offset += line.count + 1
        }

        storage.endEditing()
    }

    private static func applyRegex(_ pattern: String, to nsLine: NSString, lineOffset: Int, storage: NSTextStorage, attrs: [NSAttributedString.Key: Any]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let lineRange = NSRange(location: 0, length: nsLine.length)
        for match in regex.matches(in: nsLine as String, range: lineRange) {
            let matchRange = NSRange(location: lineOffset + match.range.location, length: match.range.length)
            storage.addAttributes(attrs, range: matchRange)
        }
    }
}
