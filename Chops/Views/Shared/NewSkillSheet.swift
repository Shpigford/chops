import SwiftUI
import SwiftData

struct NewSkillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var skillName = ""
    @State private var selectedTool: ToolSource = .claude
    @State private var errorMessage: String?

    private let skillCreatableTools: [ToolSource] = [.claude, .agents, .cursor, .codex, .amp, .opencode, .pi, .antigravity]
    private let agentCreatableTools: [ToolSource] = [.claude, .cursor, .codex]

    private var itemKind: ItemKind { appState.newItemKind }
    private var isAgent: Bool { itemKind == .agent }

    private var creatableTools: [ToolSource] {
        isAgent ? agentCreatableTools : skillCreatableTools
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(isAgent ? "newSkill.titleAgent".localized : "newSkill.titleSkill".localized)
                .font(.title2)
                .fontWeight(.bold)

            Form {
                TextField(isAgent ? "newSkill.agentName".localized : "newSkill.skillName".localized, text: $skillName)
                    .textFieldStyle(.roundedBorder)

                Picker("newSkill.tool".localized, selection: $selectedTool) {
                    ForEach(creatableTools) { tool in
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
                Button("newSkill.cancel".localized) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("newSkill.create".localized) {
                    createItem()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(skillName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            // Ensure selectedTool is valid for the current item kind
            if !creatableTools.contains(selectedTool) {
                selectedTool = creatableTools.first ?? .claude
            }
        }
    }

    private func createItem() {
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
            errorMessage = "newSkill.invalidName".localized
            return
        }

        let basePath: String
        let fileName: String

        if isAgent {
            // Agents go into the tool's agents/ directory
            guard let agentDir = selectedTool.globalAgentPaths.first else {
                errorMessage = "newSkill.noAgentSupport".localized
                return
            }
            basePath = "\(agentDir)/\(sanitizedName)"
            fileName = "\(sanitizedName).md"
        } else {
            // Skills use existing path logic
            switch selectedTool {
            case .claude:
                basePath = "\(fm.homeDirectoryForCurrentUser.path)/.claude/skills/\(sanitizedName)"
                fileName = "SKILL.md"
            case .agents:
                basePath = "\(fm.homeDirectoryForCurrentUser.path)/.agents/skills/\(sanitizedName)"
                fileName = "SKILL.md"
            case .cursor:
                basePath = "\(fm.homeDirectoryForCurrentUser.path)/.cursor/skills/\(sanitizedName)"
                fileName = "SKILL.md"
            case .codex:
                basePath = "\(fm.homeDirectoryForCurrentUser.path)/.codex/skills/\(sanitizedName)"
                fileName = "SKILL.md"
            case .amp:
                basePath = "\(configHome)/amp/skills/\(sanitizedName)"
                fileName = "SKILL.md"
            case .opencode:
                basePath = "\(configHome)/opencode/skills/\(sanitizedName)"
                fileName = "SKILL.md"
            case .pi:
                basePath = "\(fm.homeDirectoryForCurrentUser.path)/.pi/agent/skills/\(sanitizedName)"
                fileName = "SKILL.md"
            case .antigravity:
                basePath = "\(fm.homeDirectoryForCurrentUser.path)/.gemini/antigravity/skills/\(sanitizedName)"
                fileName = "SKILL.md"
            default:
                let firstPath = selectedTool.globalPaths.first ?? "\(fm.homeDirectoryForCurrentUser.path)/.claude/skills/\(sanitizedName)"
                basePath = firstPath
                fileName = "SKILL.md"
            }
        }

        do {
            try fm.createDirectory(atPath: basePath, withIntermediateDirectories: true)

            let filePath = "\(basePath)/\(fileName)"

            guard !fm.fileExists(atPath: filePath) else {
                errorMessage = isAgent ? "newSkill.duplicateAgent".localized : "newSkill.duplicateSkill".localized
                return
            }

            let boilerplate = generateBoilerplate(name: skillName, skillID: sanitizedName, tool: selectedTool)
            try boilerplate.write(toFile: filePath, atomically: true, encoding: .utf8)

            let parsed = FrontmatterParser.parse(boilerplate)
            let skill = Skill(
                filePath: filePath,
                toolSource: selectedTool,
                isDirectory: true,
                name: skillName,
                skillDescription: parsed.description,
                content: parsed.content,
                frontmatter: parsed.frontmatter,
                fileModifiedDate: .now,
                fileSize: boilerplate.count,
                isGlobal: true,
                resolvedPath: filePath,
                kind: itemKind
            )
            modelContext.insert(skill)
            try modelContext.save()

            appState.selectedSkill = skill
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generateBoilerplate(name: String, skillID: String, tool: ToolSource) -> String {
        if isAgent {
            return """
            ---
            name: \(skillID)
            description: \(name)
            ---

            # \(name)

            ## Instructions

            Add your agent instructions here.
            """
        }

        switch tool {
        case .claude, .cursor:
            return """
            ---
            name: \(skillID)
            description: \(name)
            ---

            # \(name)

            ## When to Use

            - Describe when this skill should be activated

            ## Instructions

            Add your skill instructions here.
            """
        case .codex, .amp, .opencode, .pi, .agents, .antigravity:
            return """
            ---
            name: \(skillID)
            description: \(name)
            ---

            # \(name)

            ## Instructions

            Add your skill instructions here.
            """
        default:
            return """
            ---
            name: \(skillID)
            description: \(name)
            ---

            # \(name)

            Add your skill instructions here.
            """
        }
    }
}
