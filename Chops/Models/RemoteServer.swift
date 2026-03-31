import Foundation

extension RemoteServer {
    var sshDestination: String {
        "\(username)@\(host)"
    }

    var isOpenClaw: Bool {
        skillsBasePath.contains("openclaw")
    }
}
