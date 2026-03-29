import SwiftData
import Foundation

/// Tracks an active (skill → vendor) symlink pair on disk.
/// Written only by `SymlinkService`; read by the UI to show link toggle state.
/// Never mutated by the scanner.
@Model
final class SymlinkTarget {
    /// Unique key: "<resolvedPath>|<toolSource.rawValue>"
    @Attribute(.unique) var id: String
    var skillResolvedPath: String
    /// Raw value of `ToolSource`. Stored as String for SwiftData `#Predicate` compatibility.
    var toolSource: String
    var linkedPath: String
    /// Raw value of `ItemKind`. Stored as String for SwiftData `#Predicate` compatibility.
    var kind: String
    var createdAt: Date
    /// Set by `reconcile()` when the symlink target no longer resolves.
    var isBroken: Bool

    var toolSourceEnum: ToolSource? { ToolSource(rawValue: toolSource) }
    var itemKind: ItemKind? { ItemKind(rawValue: kind) }

    init(
        skillResolvedPath: String,
        toolSource: ToolSource,
        linkedPath: String,
        kind: ItemKind
    ) {
        self.id = "\(skillResolvedPath)|\(toolSource.rawValue)"
        self.skillResolvedPath = skillResolvedPath
        self.toolSource = toolSource.rawValue
        self.linkedPath = linkedPath
        self.kind = kind.rawValue
        self.createdAt = .now
        self.isBroken = false
    }
}
