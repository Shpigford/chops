import Foundation

/// User-configurable source-of-truth root directory.
/// Sub-directories for skills, agents, and rules are derived from the root.
struct ChopsSettings {
    private init() {}

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static var sotDir: String {
        get { UserDefaults.standard.string(forKey: "sotDir") ?? "\(home)/.chops" }
        set { UserDefaults.standard.set(newValue, forKey: "sotDir") }
    }

    static var sotSkillsDir: String { "\(sotDir)/skills" }
    static var sotAgentsDir: String { "\(sotDir)/agents" }
    static var sotRulesDir: String { "\(sotDir)/rules" }

    /// When false (default), skills installed by CLI and Desktop plugins are excluded from the library.
    static var includePluginSkills: Bool {
        get { UserDefaults.standard.bool(forKey: "includePluginSkills") }
        set { UserDefaults.standard.set(newValue, forKey: "includePluginSkills") }
    }
}
