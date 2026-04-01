import Foundation

// MARK: - Schema Migration Notes
// v1.1 (SchemaV2) additions:
// - SymlinkTarget: tracks active (resolvedPath, toolSource) symlink pairs
// @Model definition lives in SchemaVersions.swift (SchemaV2.SymlinkTarget).

extension SymlinkTarget {
    var toolSourceEnum: ToolSource? { ToolSource(rawValue: toolSource) }
    var itemKind: ItemKind { ItemKind(rawValue: kind) ?? .skill }
}
