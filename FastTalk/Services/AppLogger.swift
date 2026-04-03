import Foundation
import os

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.fasttalk"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let scanning = Logger(subsystem: subsystem, category: "scanning")
    static let fileIO = Logger(subsystem: subsystem, category: "fileIO")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let windows = Logger(subsystem: subsystem, category: "windows")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
