import SwiftUI
import SwiftData

struct NewSkillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var skillName = ""
    @State private var selectedTool: ToolSource = .claude
    @State private var errorMessage: String?

    private var itemKind: ItemKind { appState.newItemKind }

    private var creatableTools: [ToolSource] {
        switch itemKind {
        case .skill:
            return [.claude, .agents, .cursor, .codex, .amp, .opencode, .pi, .antigravity]
        case .agent:
            return ToolSource.allCases.filter { !$0.globalAgentPaths.isEmpty }
        case .rule:
            return ToolSource.allCases.filter { !$0.globalRulePaths.isEmpty }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("New \(itemKind.singularName)")
                .font(.title2)
                .fontWeight(.bold)

            Form {
                TextField("\(itemKind.singularName) name", text: $skillName)
                    .textFieldStyle(.roundedBorder)

                Picker("Tool", selection: $selectedTool) {
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
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
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
            errorMessage = "Invalid name"
            return
        }

        let basePath: String
        let fileName: String

        switch itemKind {
        case .agent:
            guard let dir = selectedTool.globalAgentPaths.first else {
                errorMessage = "This tool doesn't support agents"
                return
            }
            basePath = "\(dir)/\(sanitizedName)"
            fileName = "\(sanitizedName).md"
        case .rule:
            guard let dir = selectedTool.globalRulePaths.first else {
                errorMessage = "This tool doesn't support rules"
                return
            }
            basePath = dir
            fileName = "\(sanitizedName).md"
        case .skill:
            guard let dir = selectedTool.globalPaths.first else {
                errorMessage = "This tool doesn't support skills"
                return
            }
            basePath = "\(dir)/\(sanitizedName)"
            fileName = "SKILL.md"
        }

        do {
            try fm.createDirectory(atPath: basePath, withIntermediateDirectories: true)

            let filePath = "\(basePath)/\(fileName)"

            guard !fm.fileExists(atPath: filePath) else {
                errorMessage = "A \(itemKind.singularName.lowercased()) with this name already exists"
                return
            }

            let boilerplate = generateBoilerplate(name: skillName, skillID: sanitizedName, tool: selectedTool)
            try boilerplate.write(toFile: filePath, atomically: true, encoding: .utf8)

            let parsed = FrontmatterParser.parse(boilerplate)
            let skill = Skill(
                filePath: filePath,
                toolSource: selectedTool,
                isDirectory: itemKind != .rule,
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

            switch itemKind {
            case .skill: appState.sidebarFilter = .allSkills
            case .agent: appState.sidebarFilter = .allAgents
            case .rule: appState.sidebarFilter = .allRules
            }
            appState.selectedSkill = skill
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generateBoilerplate(name: String, skillID: String, tool: ToolSource) -> String {
        switch itemKind {
        case .agent:
            return """
            ---
            name: \(skillID)
            description: \(name)
            ---

            # \(name)

            ## Instructions

            Add your agent instructions here.
            """
        case .rule:
            return """
            # \(name)

            Add your rule content here.
            """
        case .skill:
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
            default:
                return """
                ---
                name: \(skillID)
                description: \(name)
                ---

                # \(name)

                ## Instructions

                Add your skill instructions here.
                """
            }
        }
    }
}
