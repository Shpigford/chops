import SwiftData
import Foundation

@Model
final class MCPServer {
    /// Composite key: "toolSource:configFilePath:name"
    @Attribute(.unique) var id: String
    var name: String
    var toolSourceRaw: String
    var configFilePath: String
    var transportType: String

    var command: String?
    var argsData: Data?
    var envData: Data?

    var url: String?
    var headersData: Data?

    var isEnabled: Bool

    // MARK: - Computed

    var toolSource: ToolSource {
        ToolSource(rawValue: toolSourceRaw) ?? .custom
    }

    var args: [String] {
        get {
            guard let data = argsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            argsData = try? JSONEncoder().encode(newValue)
        }
    }

    var env: [String: String] {
        get {
            guard let data = envData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            envData = try? JSONEncoder().encode(newValue)
        }
    }

    var headers: [String: String] {
        get {
            guard let data = headersData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            headersData = try? JSONEncoder().encode(newValue)
        }
    }

    var displayTransport: String {
        switch transportType {
        case "stdio": "stdio"
        case "http": "HTTP"
        case "sse": "SSE"
        default: transportType
        }
    }

    // MARK: - Init

    init(
        name: String,
        toolSource: ToolSource,
        configFilePath: String,
        transportType: String,
        command: String? = nil,
        args: [String] = [],
        env: [String: String] = [:],
        url: String? = nil,
        headers: [String: String] = [:],
        isEnabled: Bool = true
    ) {
        self.id = "\(toolSource.rawValue):\(configFilePath):\(name)"
        self.name = name
        self.toolSourceRaw = toolSource.rawValue
        self.configFilePath = configFilePath
        self.transportType = transportType
        self.command = command
        self.argsData = try? JSONEncoder().encode(args)
        self.envData = try? JSONEncoder().encode(env)
        self.url = url
        self.headersData = try? JSONEncoder().encode(headers)
        self.isEnabled = isEnabled
    }

    static func makeID(toolSource: ToolSource, configFilePath: String, name: String) -> String {
        "\(toolSource.rawValue):\(configFilePath):\(name)"
    }
}
