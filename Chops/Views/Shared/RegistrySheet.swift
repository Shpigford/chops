import SwiftUI

struct RegistrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var registry = SkillRegistry()
    @State private var searchText = ""
    @State private var results: [SkillRegistry.RegistrySkill] = []
    @State private var selectedSkill: SkillRegistry.RegistrySkill?
    @State private var skillContent: String?
    @State private var selectedAgents: Set<String> = []
    @State private var isSearching = false
    @State private var isFetchingContent = false
    @State private var isInstalling = false
    @State private var error: String?
    @State private var installSuccess = false
    @State private var searchTask: Task<Void, Never>?
    @State private var contentTask: Task<Void, Never>?

    private var installedAgents: [AgentTarget] {
        AgentTarget.installed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if selectedSkill != nil {
                    Button {
                        withAnimation {
                            contentTask?.cancel()
                            selectedSkill = nil
                            skillContent = nil
                            error = nil
                            installSuccess = false
                            isFetchingContent = false
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(selectedSkill != nil ? "Install Skill" : "Browse Skills")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            if let skill = selectedSkill {
                installView(skill: skill)
            } else {
                searchView
            }
        }
        .frame(width: 560, height: 500)
        .onAppear {
            // Pre-select all installed agents
            selectedAgents = Set(installedAgents.map(\.id))
        }
        .onDisappear {
            searchTask?.cancel()
            contentTask?.cancel()
        }
    }

    // MARK: - Search Phase

    private var searchView: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search skills (e.g. react, testing, deploy)...", text: $searchText)
                    .textFieldStyle(.plain)
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .onChange(of: searchText) { _, newValue in
                debounceSearch(query: newValue)
            }

            Divider()

            // Results
            if results.isEmpty && !isSearching && searchText.isEmpty {
                ContentUnavailableView {
                    Label("Search the Skills Registry", systemImage: "globe")
                } description: {
                    Text("Find and install skills from the open agent skills ecosystem.")
                }
                .frame(maxHeight: .infinity)
            } else if results.isEmpty && !isSearching && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else {
                List(results) { skill in
                    Button {
                        selectSkill(skill)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(skill.name)
                                    .fontWeight(.medium)
                                Text(skill.source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(skill.formattedInstalls) installs")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Install Phase

    private func installView(skill: SkillRegistry.RegistrySkill) -> some View {
        VStack(spacing: 0) {
            if isFetchingContent {
                Spacer()
                ProgressView("Loading skill content...")
                Spacer()
            } else if let content = skillContent {
                // Content preview
                ScrollView {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .frame(maxHeight: 200)
                .background(.quaternary.opacity(0.3))

                Divider()

                // Agent selection
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Install to:")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        if !installedAgents.isEmpty {
                            let allSelected = selectedAgents.count == installedAgents.count
                            Button(allSelected ? "Deselect All" : "Select All") {
                                if allSelected {
                                    selectedAgents.removeAll()
                                } else {
                                    selectedAgents = Set(installedAgents.map(\.id))
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                    }

                    if installedAgents.isEmpty {
                        Text("No supported agents detected on this machine.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(installedAgents) { agent in
                                    HStack(spacing: 8) {
                                        Image(systemName: selectedAgents.contains(agent.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedAgents.contains(agent.id) ? .accentColor : .secondary)
                                            .font(.system(size: 14))

                                        Text(agent.displayName)
                                            .font(.system(size: 12))

                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedAgents.contains(agent.id) {
                                            selectedAgents.remove(agent.id)
                                        } else {
                                            selectedAgents.insert(agent.id)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 4)
                                }
                            }
                        }
                        .frame(maxHeight: 140)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                Divider()

                // Install button
                HStack {
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }

                    if installSuccess {
                        Label("Installed!", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Button {
                        performInstall(content: content, skillName: skill.skillId)
                    } label: {
                        if isInstalling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Install")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedAgents.isEmpty || isInstalling || installSuccess)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            } else if let error {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func debounceSearch(query: String) {
        searchTask?.cancel()
        error = nil

        guard query.count >= 2 else {
            results = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            await MainActor.run { isSearching = true }

            do {
                let skills = try await registry.search(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    results = skills
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.error = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func selectSkill(_ skill: SkillRegistry.RegistrySkill) {
        contentTask?.cancel()
        selectedSkill = skill
        skillContent = nil
        error = nil
        installSuccess = false
        isFetchingContent = true

        contentTask = Task {
            do {
                let content = try await registry.fetchContent(skill: skill)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard selectedSkill?.id == skill.id else { return }
                    self.skillContent = content
                    self.isFetchingContent = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard selectedSkill?.id == skill.id else { return }
                    self.error = error.localizedDescription
                    self.isFetchingContent = false
                }
            }
        }
    }

    private func performInstall(content: String, skillName: String) {
        let agents = installedAgents.filter { selectedAgents.contains($0.id) }
        guard !agents.isEmpty else { return }

        isInstalling = true
        error = nil

        do {
            try registry.install(content: content, skillName: skillName, agents: agents)
            installSuccess = true
            isInstalling = false

            // Trigger re-scan so the new skill appears immediately
            NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)

            // Auto-dismiss after brief delay
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                await MainActor.run { dismiss() }
            }
        } catch {
            self.error = error.localizedDescription
            isInstalling = false
        }
    }
}
