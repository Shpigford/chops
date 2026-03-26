import Foundation

// MARK: - Errors

enum SymlinkError: LocalizedError {
    case partialFailure([String])

    var errorDescription: String? {
        switch self {
        case .partialFailure(let errors):
            return "Some symlinks could not be created:\n" + errors.joined(separator: "\n")
        }
    }
}

// MARK: - SymlinkService

/// Service for creating and managing symlinks between skill sources and tool directories.
/// All mutations must happen on MainActor since they modify SwiftData `Skill` objects.
@MainActor
struct SymlinkService {
    private static let logger = AppLogger.symlink

    /// Creates symlinks for the given skills to the specified tool directories.
    /// - Parameters:
    ///   - skills: The skills to symlink
    ///   - tools: The target tools to link to
    /// - Throws: `SymlinkError.partialFailure` if any symlinks could not be created
    static func symlink(_ skills: [Skill], to tools: [ToolSource]) throws {
        let fm = FileManager.default
        var errors: [String] = []

        for skill in skills {
            let sourcePath: String
            let itemName: String

            if skill.isDirectory {
                sourcePath = (skill.filePath as NSString).deletingLastPathComponent
                itemName = (sourcePath as NSString).lastPathComponent
            } else {
                sourcePath = skill.filePath
                itemName = (sourcePath as NSString).lastPathComponent
            }

            for tool in tools {
                guard let globalPath = findMatchingPath(for: skill.category, in: tool.globalPaths) else {
                    let message = "\(tool.displayName): no matching \(skill.category.displayName) directory"
                    logger.warning("\(message)")
                    errors.append(message)
                    continue
                }
                let linkPath = "\(globalPath)/\(itemName)"

                var s = stat()
                let inodeExists = Darwin.lstat(linkPath, &s) == 0

                if inodeExists {
                    let isSymlink = (s.st_mode & S_IFMT) == S_IFLNK
                    if isSymlink {
                        // Symlink exists and resolves — just update metadata
                        if fm.fileExists(atPath: linkPath) {
                            skill.addInstallation(path: skill.filePath, tool: tool)
                            skill.addSymlinkTarget(tool)
                            logger.debug("Symlink already exists: \(linkPath)")
                            continue
                        }
                        // Broken symlink — remove and recreate
                        do {
                            try fm.removeItem(atPath: linkPath)
                            logger.info("Removed broken symlink: \(linkPath)")
                        } catch {
                            let message = "\(tool.displayName): could not remove broken symlink — \(error.localizedDescription)"
                            logger.error("\(message)")
                            errors.append(message)
                            continue
                        }
                    } else {
                        // Regular file/directory exists — skip to avoid overwriting
                        logger.debug("Skipping \(linkPath): non-symlink file exists")
                        continue
                    }
                } else {
                    // Nothing at path — check if already installed natively
                    if skill.toolSources.contains(tool) && !skill.linkedTools.contains(tool) {
                        logger.debug("Skipping \(tool.displayName): already installed natively")
                        continue
                    }
                }

                do {
                    try fm.createDirectory(atPath: globalPath, withIntermediateDirectories: true, attributes: nil)
                    try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: sourcePath)
                    skill.addInstallation(path: skill.filePath, tool: tool)
                    skill.addSymlinkTarget(tool)
                    logger.info("Created symlink: \(linkPath) -> \(sourcePath)")
                } catch {
                    let message = "\(tool.displayName): \(error.localizedDescription)"
                    logger.error("Failed to create symlink: \(message)")
                    errors.append(message)
                }
            }
        }

        if !errors.isEmpty {
            throw SymlinkError.partialFailure(errors)
        }
    }

    /// Removes symlinks for the given skills from the specified tool directories.
    /// - Parameters:
    ///   - skills: The skills to unlink
    ///   - tools: The target tools to unlink from
    /// - Throws: `SymlinkError.partialFailure` if any symlinks could not be removed
    static func unlink(_ skills: [Skill], from tools: [ToolSource]) throws {
        let fm = FileManager.default
        var errors: [String] = []

        for skill in skills {
            let sourcePath: String
            let itemName: String

            if skill.isDirectory {
                sourcePath = (skill.filePath as NSString).deletingLastPathComponent
                itemName = (sourcePath as NSString).lastPathComponent
            } else {
                sourcePath = skill.filePath
                itemName = (sourcePath as NSString).lastPathComponent
            }

            for tool in tools {
                guard skill.linkedTools.contains(tool) else {
                    continue
                }

                guard let globalPath = findMatchingPath(for: skill.category, in: tool.globalPaths) else {
                    continue
                }

                let linkPath = "\(globalPath)/\(itemName)"

                var s = stat()
                let inodeExists = Darwin.lstat(linkPath, &s) == 0

                if inodeExists {
                    let isSymlink = (s.st_mode & S_IFMT) == S_IFLNK
                    if isSymlink {
                        do {
                            try fm.removeItem(atPath: linkPath)
                            skill.removeSymlinkTarget(tool)
                            logger.info("Removed symlink: \(linkPath)")
                        } catch {
                            let message = "\(tool.displayName): \(error.localizedDescription)"
                            logger.error("Failed to remove symlink: \(message)")
                            errors.append(message)
                        }
                    } else {
                        // Not a symlink - just remove from metadata
                        skill.removeSymlinkTarget(tool)
                        logger.debug("Removed link metadata for non-symlink: \(linkPath)")
                    }
                } else {
                    // Path doesn't exist - just remove from metadata
                    skill.removeSymlinkTarget(tool)
                    logger.debug("Removed stale link metadata: \(linkPath)")
                }
            }
        }

        if !errors.isEmpty {
            throw SymlinkError.partialFailure(errors)
        }
    }

    /// Finds the appropriate path for a given category within a tool's global paths.
    /// - Parameters:
    ///   - category: The skill category (agents, skills, rules)
    ///   - paths: The tool's available global paths
    /// - Returns: The matching path, or nil if none found
    /// - Note: This is `nonisolated` as it's a pure function with no side effects.
    nonisolated static func findMatchingPath(for category: SkillCategory, in paths: [String]) -> String? {
        let suffix: String
        switch category {
        case .agents: suffix = "/agents"
        case .skill: suffix = "/skills"
        case .rules: suffix = "/rules"
        }
        return paths.first { $0.hasSuffix(suffix) }
    }
}
