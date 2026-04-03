import Foundation

extension RemoteServer {
    var sshDestination: String {
        "\(username)@\(host)"
    }

    /// Tool used when tagging skills synced from this server (path-based heuristic).
    var inferredRemoteToolSource: ToolSource {
        let p = skillsBasePath.lowercased()
        if p.contains("hermes") { return .hermes }
        if p.contains("openclaw") { return .openclaw }
        return .openclaw
    }
}
