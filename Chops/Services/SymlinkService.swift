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

    /// Creates a symlink inside the vendor's global directory pointing at `skill.resolvedPath`.
    /// Inserts a `SymlinkTarget` record into `context`.
    func link(_ skill: Skill, to tool: ToolSource, context: ModelContext) throws {
        let source = skill.resolvedPath
        guard fm.fileExists(atPath: source) else {
            throw SymlinkError.sourceNotFound(source)
        }

        let targetDir = try vendorDirectory(for: tool, kind: skill.itemKind)
        try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

        let sourceURL = URL(fileURLWithPath: source)
        let destination = URL(fileURLWithPath: targetDir)
            .appendingPathComponent(sourceURL.lastPathComponent).path

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

        let targetID = "\(source)|\(tool.rawValue)"
        let existing = FetchDescriptor<SymlinkTarget>(predicate: #Predicate { $0.id == targetID })
        if (try? context.fetch(existing))?.isEmpty == false {
            try context.save()
            NotificationCenter.default.post(name: .customScanPathsChanged, object: nil)
            return
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
        let targetID = "\(skill.resolvedPath)|\(tool.rawValue)"
        let descriptor = FetchDescriptor<SymlinkTarget>(
            predicate: #Predicate { $0.id == targetID }
        )
        guard let record = try context.fetch(descriptor).first else { return }

        let path = record.linkedPath
        let attrs = try? fm.attributesOfItem(atPath: path)
        if attrs == nil {
            // File already gone — clean up the record without error.
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

    /// Checks every `SymlinkTarget` and marks broken ones whose symlink target no longer resolves.
    /// Called on app launch and after each full scan. Never triggers a rescan.
    func reconcile(context: ModelContext) {
        let descriptor = FetchDescriptor<SymlinkTarget>()
        guard let records = try? context.fetch(descriptor) else { return }
        var dirty = false
        for record in records {
            let broken = !fm.fileExists(atPath: record.linkedPath)
            if record.isBroken != broken {
                record.isBroken = broken
                dirty = true
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

    /// Returns all non-broken `SymlinkTarget` records for a given skill.
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

    /// Returns true if a non-broken symlink exists for (skill, tool).
    func isLinked(_ skill: Skill, to tool: ToolSource, context: ModelContext) -> Bool {
        let targetID = "\(skill.resolvedPath)|\(tool.rawValue)"
        let descriptor = FetchDescriptor<SymlinkTarget>(
            predicate: #Predicate { $0.id == targetID && !$0.isBroken }
        )
        do {
            return try !context.fetch(descriptor).isEmpty
        } catch {
            AppLogger.fileIO.error("SymlinkService.isLinked fetch failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private

    private func vendorDirectory(for tool: ToolSource, kind: ItemKind) throws -> String {
        guard let dir = tool.globalDirs(for: kind).first else {
            throw SymlinkError.noTargetDirectory(tool, kind)
        }
        return dir
    }
}
