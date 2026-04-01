import SwiftData
import Foundation

enum SymlinkError: LocalizedError {
    case destinationExists(String)
    case notASymlink(String)
    case sourceNotFound(String)
    case noTargetDirectory(ToolSource, ItemKind)

    var errorDescription: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func tilde(_ p: String) -> String { p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p }
        switch self {
        case .destinationExists(let p):
            return "\(tilde(p)) already exists and is not a symlink."
        case .notASymlink(let p):
            return "\(tilde(p)) is not a symlink — refusing to remove."
        case .sourceNotFound(let p):
            return "Source file not found at \(tilde(p))."
        case .noTargetDirectory(let tool, let kind):
            return "\(tool.displayName) has no global directory for \(kind.displayName.lowercased())."
        }
    }
}

@MainActor
final class SymlinkService {
    static let shared = SymlinkService()
    private let fm = FileManager.default

    private init() {}

    // MARK: - Link

    /// Creates a symlink in the vendor's global directory pointing at `skill.resolvedPath`.
    func link(_ skill: Skill, to tool: ToolSource, context: ModelContext) throws {
        let source = skill.resolvedPath
        guard fm.fileExists(atPath: source) else {
            throw SymlinkError.sourceNotFound(source)
        }

        let targetDir = try vendorDirectory(for: tool, kind: skill.itemKind)
        let relativePath = relativePathFromScanBase(source: source, kind: skill.itemKind, toolSources: skill.toolSources)
        var destination = URL(fileURLWithPath: targetDir)
            .appendingPathComponent(relativePath).path
        // Cursor requires .mdc for rules and agents to be picked up correctly.
        if tool == .cursor,
           skill.itemKind == .rule || skill.itemKind == .agent,
           destination.hasSuffix(".md") {
            destination = String(destination.dropLast(3)) + ".mdc"
        }
        let destinationParent = (destination as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: destinationParent, withIntermediateDirectories: true)

        if fm.fileExists(atPath: destination) {
            if let existingTarget = try? fm.destinationOfSymbolicLink(atPath: destination) {
                // Idempotent only if the existing symlink points to the same source.
                guard existingTarget == source else { throw SymlinkError.destinationExists(destination) }
            } else {
                throw SymlinkError.destinationExists(destination)
            }
        } else {
            try fm.createSymbolicLink(atPath: destination, withDestinationPath: source)
        }

        let targetID = "\(source)\n\(tool.rawValue)"
        let existingDescriptor = FetchDescriptor<SymlinkTarget>(predicate: #Predicate { $0.id == targetID })
        if let existingRecord = try context.fetch(existingDescriptor).first {
            if existingRecord.linkedPath == destination && existingRecord.kind == skill.itemKind.rawValue {
                // Symlink was recreated on disk after being marked broken — keep consistency.
                if existingRecord.isBroken {
                    existingRecord.isBroken = false
                    try context.save()
                    NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)
                }
                return
            }
            // Stale record (e.g. kind changed after a bug fix) — clean up the old symlink first.
            // Use attributesOfItem (lstat semantics) so broken symlinks are also removed.
            let staleAttrs = try? fm.attributesOfItem(atPath: existingRecord.linkedPath)
            if staleAttrs?[.type] as? FileAttributeType == .typeSymbolicLink {
                do {
                    try fm.removeItem(atPath: existingRecord.linkedPath)
                } catch {
                    AppLogger.fileIO.error("SymlinkService: failed to remove stale symlink at \(existingRecord.linkedPath): \(error.localizedDescription)")
                }
            }
            context.delete(existingRecord)
        }

        context.insert(SymlinkTarget(
            skillResolvedPath: source,
            toolSource: tool,
            linkedPath: destination,
            kind: skill.itemKind
        ))
        try context.save()
        NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)
    }

    // MARK: - Unlink

    /// Removes the symlink from the vendor directory and deletes the `SymlinkTarget` record.
    func unlink(_ skill: Skill, from tool: ToolSource, context: ModelContext) throws {
        let targetID = "\(skill.resolvedPath)\n\(tool.rawValue)"
        let descriptor = FetchDescriptor<SymlinkTarget>(
            predicate: #Predicate { $0.id == targetID }
        )
        guard let record = try context.fetch(descriptor).first else { return }

        let path = record.linkedPath
        let attrs = try? fm.attributesOfItem(atPath: path)
        if attrs == nil {
            context.delete(record)
            try context.save()
            return
        }
        guard attrs?[.type] as? FileAttributeType == .typeSymbolicLink else {
            throw SymlinkError.notASymlink(path)
        }
        try fm.removeItem(atPath: path)

        context.delete(record)
        try context.save()
        NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)
    }

    // MARK: - Reconcile

    /// Validates every `SymlinkTarget` and discovers untracked symlinks in vendor directories.
    /// Removes records whose kind no longer matches the parent skill, marks records broken when
    /// the symlink file is missing, and creates new records for on-disk symlinks with no record.
    func reconcile(context: ModelContext) {
        guard let records = try? context.fetch(FetchDescriptor<SymlinkTarget>()) else { return }
        let allSkills = (try? context.fetch(FetchDescriptor<Skill>())) ?? []
        let skillsByPath = Dictionary(uniqueKeysWithValues: allSkills.map { ($0.resolvedPath, $0) })

        var dirty = false
        var trackedIDs = Set(records.map(\.id))

        // Validate existing records
        for record in records {
            if let skill = skillsByPath[record.skillResolvedPath], skill.kind != record.kind {
                let staleAttrs = try? fm.attributesOfItem(atPath: record.linkedPath)
                if staleAttrs?[.type] as? FileAttributeType == .typeSymbolicLink {
                    do {
                        try fm.removeItem(atPath: record.linkedPath)
                    } catch {
                        AppLogger.fileIO.error("SymlinkService: failed to remove stale symlink at \(record.linkedPath): \(error.localizedDescription)")
                    }
                }
                trackedIDs.remove(record.id)
                context.delete(record)
                dirty = true
                continue
            }

            let broken = !fm.fileExists(atPath: record.linkedPath)
            if record.isBroken != broken {
                record.isBroken = broken
                dirty = true
            }
        }

        // Discover symlinks in vendor directories not yet tracked (recursive — link() preserves subdirs)
        for tool in ToolSource.allCases where tool != .custom {
            for kind in ItemKind.allCases {
                for dir in tool.globalDirs(for: kind) {
                    let enumerator = fm.enumerator(
                        at: URL(fileURLWithPath: dir),
                        includingPropertiesForKeys: [.isSymbolicLinkKey],
                        options: [.skipsPackageDescendants]
                    )
                    guard let enumerator else { continue }
                    // Resolve dir itself in case it is a symlink (needed for relative target computation)
                    let resolvedDir = URL(fileURLWithPath: dir).resolvingSymlinksInPath().path

                    for case let itemURL as URL in enumerator {
                        let resourceValues = try? itemURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                        // Prevent descent into symlinked directories — avoids infinite loops on cycles.
                        if resourceValues?.isSymbolicLink == true, resourceValues?.isDirectory == true {
                            enumerator.skipDescendants()
                        }
                        guard resourceValues?.isSymbolicLink == true else { continue }
                        let linkedPath = itemURL.path
                        guard let rawTarget = try? fm.destinationOfSymbolicLink(atPath: linkedPath) else { continue }

                        let absoluteTarget = rawTarget.hasPrefix("/") ? rawTarget
                            : URL(fileURLWithPath: resolvedDir).appendingPathComponent(rawTarget).path
                        let resolvedTarget = URL(fileURLWithPath: absoluteTarget).resolvingSymlinksInPath().path

                        guard let skill = skillsByPath[resolvedTarget],
                              skill.itemKind == kind else { continue }

                        let targetID = "\(resolvedTarget)\n\(tool.rawValue)"
                        guard !trackedIDs.contains(targetID) else { continue }

                        context.insert(SymlinkTarget(
                            skillResolvedPath: resolvedTarget,
                            toolSource: tool,
                            linkedPath: linkedPath,
                            kind: kind
                        ))
                        trackedIDs.insert(targetID)
                        dirty = true
                    }
                }
            }
        }

        if dirty {
            do {
                try context.save()
            } catch {
                AppLogger.fileIO.error("SymlinkService.reconcile save failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Query

    func targets(for skill: Skill, context: ModelContext) -> [SymlinkTarget] {
        let path = skill.resolvedPath
        let descriptor = FetchDescriptor<SymlinkTarget>(
            predicate: #Predicate { $0.skillResolvedPath == path && !$0.isBroken }
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            AppLogger.fileIO.error("SymlinkService.targets fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Private

    /// Returns `source` relative to its scan base, preserving subdirectory structure.
    private func relativePathFromScanBase(source: String, kind: ItemKind, toolSources: [ToolSource]) -> String {
        for toolSource in toolSources {
            for base in toolSource.globalDirs(for: kind) {
                let prefix = base.hasSuffix("/") ? base : base + "/"
                if source.hasPrefix(prefix) {
                    return String(source.dropFirst(prefix.count))
                }
            }
        }
        let fallback = URL(fileURLWithPath: source).lastPathComponent
        AppLogger.fileIO.warning("SymlinkService: no scan base found for \(source), falling back to filename '\(fallback)' — collision possible if other skills share this name")
        return fallback
    }

    private func vendorDirectory(for tool: ToolSource, kind: ItemKind) throws -> String {
        guard let dir = tool.globalDirs(for: kind).first else {
            throw SymlinkError.noTargetDirectory(tool, kind)
        }
        return dir
    }
}
