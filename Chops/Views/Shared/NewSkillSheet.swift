import SwiftUI
import SwiftData

struct NewSkillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var skillName = ""
    @State private var selectedTool: ToolSource = .claude
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("New Skill")
                .font(.title2)
                .fontWeight(.bold)

            Form {
                TextField("Skill name", text: $skillName)
                    .textFieldStyle(.roundedBorder)

                Picker("Tool", selection: $selectedTool) {
                    ForEach(ToolSource.allCases.filter { $0 != .custom }) { tool in
                        Label(tool.displayName, systemImage: tool.iconName)
                            .tag(tool)
                    }
                }
            }
            .formStyle(.grouped)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    createSkill()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(skillName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func createSkill() {
        let fm = FileManager.default
        let configHome: String = {
            if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
                return xdg
            }
            return "\(fm.homeDirectoryForCurrentUser.path)/.config"
        }()
        let sanitizedName = skillName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        guard !sanitizedName.isEmpty else {
            errorMessage = "Invalid skill name"
            return
        }

        let basePath: String
        let fileName: String
        let isDirectory: Bool

        switch selectedTool {
        case .claude:
            basePath = "\(fm.homeDirectoryForCurrentUser.path)/.claude/skills/\(sanitizedName)"
            fileName = "SKILL.md"
            isDirectory = true
        case .cursor:
            basePath = "\(fm.homeDirectoryForCurrentUser.path)/.cursor/skills/\(sanitizedName)"
            fileName = "SKILL.md"
            isDirectory = true
        case .codex:
            basePath = "\(fm.homeDirectoryForCurrentUser.path)/.codex/skills/\(sanitizedName)"
            fileName = "SKILL.md"
            isDirectory = true
        case .amp:
            basePath = "\(configHome)/amp/skills/\(sanitizedName)"
            fileName = "SKILL.md"
            isDirectory = true
        case .pi:
            basePath = "\(fm.homeDirectoryForCurrentUser.path)/.pi/agent/skills/\(sanitizedName)"
            fileName = "SKILL.md"
            isDirectory = true
        default:
            let firstPath = selectedTool.globalPaths.first ?? "\(fm.homeDirectoryForCurrentUser.path)/.claude/skills/\(sanitizedName)"
            basePath = firstPath
            fileName = "SKILL.md"
            isDirectory = true
        }

        do {
            if isDirectory {
                try fm.createDirectory(atPath: basePath, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(atPath: basePath, withIntermediateDirectories: true)
            }

            let filePath = isDirectory ? "\(basePath)/\(fileName)" : "\(basePath)/\(fileName)"

            // Don't overwrite existing files
            guard !fm.fileExists(atPath: filePath) else {
                errorMessage = "A skill with this name already exists"
                return
            }

            let boilerplate = generateBoilerplate(name: skillName, tool: selectedTool)
            try boilerplate.write(toFile: filePath, atomically: true, encoding: .utf8)

            // Insert into SwiftData
            let parsed = FrontmatterParser.parse(boilerplate)
            let skill = Skill(
                filePath: filePath,
                toolSource: selectedTool,
                isDirectory: isDirectory,
                name: skillName,
                skillDescription: parsed.description,
                content: parsed.content,
                frontmatter: parsed.frontmatter,
                fileModifiedDate: .now,
                fileSize: boilerplate.count,
                isGlobal: true,
                resolvedPath: filePath
            )
            modelContext.insert(skill)
            try modelContext.save()

            appState.selectedSkill = skill
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generateBoilerplate(name: String, tool: ToolSource) -> String {
        switch tool {
        case .claude, .cursor:
            return """
            ---
            name: \(name.lowercased().replacingOccurrences(of: " ", with: "-"))
            description: \(name)
            ---

            # \(name)

            ## When to Use

            - Describe when this skill should be activated

            ## Instructions

            Add your skill instructions here.
            """
        case .codex, .amp, .pi:
            return """
            ---
            name: \(name.lowercased().replacingOccurrences(of: " ", with: "-"))
            description: \(name)
            ---

            # \(name)

            ## Instructions

            Add your skill instructions here.
            """
        default:
            return """
            ---
            name: \(name.lowercased().replacingOccurrences(of: " ", with: "-"))
            description: \(name)
            ---

            # \(name)

            Add your skill instructions here.
            """
        }
    }
}
