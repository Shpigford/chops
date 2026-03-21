import Foundation

@Observable
final class SkillRegistry {
    var isSearching = false
    var searchError: String?

    // Cache repo trees and default branches to avoid repeated API calls
    private var treeCache: [String: [String]] = [:] // source -> [SKILL.md paths]
    private var branchCache: [String: String] = [:] // source -> default branch

    // MARK: - Search

    struct SearchResponse: Codable {
        let skills: [RegistrySkill]
        let count: Int
    }

    struct RegistrySkill: Identifiable, Codable {
        let id: String
        let skillId: String
        let name: String
        let installs: Int
        let source: String

        var formattedInstalls: String {
            if installs >= 1_000_000 {
                return "\(String(format: "%.1f", Double(installs) / 1_000_000).replacingOccurrences(of: ".0", with: ""))M"
            } else if installs >= 1_000 {
                return "\(String(format: "%.1f", Double(installs) / 1_000).replacingOccurrences(of: ".0", with: ""))K"
            }
            return "\(installs)"
        }
    }

    func search(query: String) async throws -> [RegistrySkill] {
        guard query.count >= 2 else { return [] }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://skills.sh/api/search?q=\(encoded)&limit=30")!

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RegistryError.searchFailed
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.skills
    }

    // MARK: - Content Resolution

    func fetchContent(skill: RegistrySkill) async throws -> String {
        let branch = try await getDefaultBranch(source: skill.source)
        let paths = try await getSkillPaths(source: skill.source, branch: branch)

        // Try each SKILL.md path until we find one whose frontmatter name matches
        for path in paths {
            let rawURL = URL(string: "https://raw.githubusercontent.com/\(skill.source)/\(branch)/\(path)")!
            guard let (data, response) = try? await URLSession.shared.data(from: rawURL),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            // Check if this SKILL.md's frontmatter name matches the skillId
            let frontmatterName = parseFrontmatterName(from: content)
            if frontmatterName == skill.skillId || frontmatterName == skill.name {
                return content
            }
        }

        throw RegistryError.skillNotFound
    }

    private func getDefaultBranch(source: String) async throws -> String {
        if let cached = branchCache[source] {
            return cached
        }

        let url = URL(string: "https://api.github.com/repos/\(source)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Fall back to "main" if we can't determine default branch
            return "main"
        }

        struct RepoResponse: Codable {
            let default_branch: String
        }

        let repo = try JSONDecoder().decode(RepoResponse.self, from: data)
        branchCache[source] = repo.default_branch
        return repo.default_branch
    }

    private func getSkillPaths(source: String, branch: String) async throws -> [String] {
        if let cached = treeCache[source] {
            return cached
        }

        let url = URL(string: "https://api.github.com/repos/\(source)/git/trees/\(branch)?recursive=1")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw RegistryError.treeFetchFailed
        }
        if http.statusCode == 403 {
            throw RegistryError.rateLimited
        }
        guard http.statusCode == 200 else {
            throw RegistryError.treeFetchFailed
        }

        struct TreeResponse: Codable {
            struct TreeEntry: Codable {
                let path: String
                let type: String
            }
            let tree: [TreeEntry]
        }

        let tree = try JSONDecoder().decode(TreeResponse.self, from: data)
        let skillPaths = tree.tree
            .filter { $0.type == "blob" && $0.path.hasSuffix("/SKILL.md") }
            .map(\.path)

        treeCache[source] = skillPaths
        return skillPaths
    }

    private func parseFrontmatterName(from content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.hasPrefix("name:") {
                return trimmed
                    .dropFirst(5)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    // MARK: - Install

    func install(content: String, skillName: String, agents: [AgentTarget]) throws {
        let sanitized = skillName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == "_" }
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))

        guard !sanitized.isEmpty else {
            throw RegistryError.invalidSkillName
        }

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Canonical location — matches the official skills CLI behavior
        let canonicalDir = "\(home)/.agents/skills/\(sanitized)"
        let canonicalFile = "\(canonicalDir)/SKILL.md"
        let canonicalAlreadyExisted = fm.fileExists(atPath: canonicalFile)

        // Write real file to canonical location if not already there
        if !canonicalAlreadyExisted {
            try fm.createDirectory(atPath: canonicalDir, withIntermediateDirectories: true)
            try content.write(toFile: canonicalFile, atomically: true, encoding: .utf8)
        }

        // Symlink from each agent's skills dir to the canonical location
        var newLinks = 0
        for agent in agents {
            let agentDir = "\(agent.expandedSkillsDir)/\(sanitized)"

            // Skip if already installed (real file or symlink)
            if fm.fileExists(atPath: agentDir) { continue }

            // Create parent dir if needed
            try fm.createDirectory(atPath: agent.expandedSkillsDir, withIntermediateDirectories: true)

            // Create symlink to canonical dir
            try fm.createSymbolicLink(atPath: agentDir, withDestinationPath: canonicalDir)
            newLinks += 1
        }

        if newLinks == 0 && canonicalAlreadyExisted {
            throw RegistryError.skillAlreadyExists
        }
    }

    // MARK: - Errors

    enum RegistryError: LocalizedError {
        case searchFailed
        case treeFetchFailed
        case rateLimited
        case skillNotFound
        case invalidSkillName
        case skillAlreadyExists

        var errorDescription: String? {
            switch self {
            case .searchFailed: "Search request failed"
            case .treeFetchFailed: "Could not fetch repository contents"
            case .rateLimited: "GitHub API rate limit reached — try again in a few minutes"
            case .skillNotFound: "Skill file not found in repository"
            case .invalidSkillName: "Invalid skill name"
            case .skillAlreadyExists: "Skill is already installed for all selected agents"
            }
        }
    }
}
