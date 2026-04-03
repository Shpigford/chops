import SwiftUI
import SwiftData
import Sparkle
import AppKit

@main
struct ChopsApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleLogger.self) private var lifecycleLogger
    @State private var appState = AppState()
    @AppStorage("ACPDebugLogging") private var debugLoggingEnabled = false
    private let updaterController: SPUStandardUpdaterController

    init() {
        AppLogger.lifecycle.notice("ChopsApp init bundleID=\(Bundle.main.bundleIdentifier ?? "unknown", privacy: .public)")
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)

        do {
            let config = try StoreBootstrap.makeConfiguration(schema: schema)
            return try ModelContainer(
                for: schema,
                migrationPlan: ChopsMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            TextEditingCommands()
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveCurrentSkill, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState.selectedSkill == nil)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .help) {
                Toggle("Enable Debug Logging", isOn: $debugLoggingEnabled)
                Divider()
                Button("Export Diagnostic Log…") {
                    let context = sharedModelContainer.mainContext
                    DiagnosticExporter.export(modelContext: context)
                }
            }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(appState)
                .modelContainer(sharedModelContainer)
        }
    }
}

@MainActor
final class AppLifecycleLogger: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        installWindowObservers()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppLogger.lifecycle.notice("applicationWillFinishLaunching")
        AppRuntimeDiagnostics.logSnapshot(reason: "applicationWillFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.lifecycle.notice("applicationDidFinishLaunching")
        AppRuntimeDiagnostics.logSnapshot(reason: "applicationDidFinishLaunching")
        scheduleLaunchSnapshots()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppLogger.lifecycle.notice("applicationDidBecomeActive")
        AppRuntimeDiagnostics.logSnapshot(reason: "applicationDidBecomeActive")
    }

    func applicationDidResignActive(_ notification: Notification) {
        AppLogger.lifecycle.notice("applicationDidResignActive")
        AppRuntimeDiagnostics.logSnapshot(reason: "applicationDidResignActive")
    }

    func applicationDidHide(_ notification: Notification) {
        AppLogger.lifecycle.notice("applicationDidHide")
        AppRuntimeDiagnostics.logSnapshot(reason: "applicationDidHide")
    }

    func applicationDidUnhide(_ notification: Notification) {
        AppLogger.lifecycle.notice("applicationDidUnhide")
        AppRuntimeDiagnostics.logSnapshot(reason: "applicationDidUnhide")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppLogger.lifecycle.notice("applicationShouldHandleReopen hasVisibleWindows=\(flag)")
        AppRuntimeDiagnostics.logSnapshot(reason: "applicationShouldHandleReopen")
        return true
    }

    private func installWindowObservers() {
        let center = NotificationCenter.default
        let windowNotifications: [(Notification.Name, String)] = [
            (NSWindow.didBecomeKeyNotification, "didBecomeKey"),
            (NSWindow.didResignKeyNotification, "didResignKey"),
            (NSWindow.didBecomeMainNotification, "didBecomeMain"),
            (NSWindow.didResignMainNotification, "didResignMain"),
            (NSWindow.didMiniaturizeNotification, "didMiniaturize"),
            (NSWindow.didDeminiaturizeNotification, "didDeminiaturize"),
            (NSWindow.didMoveNotification, "didMove"),
            (NSWindow.didResizeNotification, "didResize"),
            (NSWindow.willCloseNotification, "willClose"),
        ]

        observers = windowNotifications.map { name, label in
            center.addObserver(forName: name, object: nil, queue: .main) { notification in
                Task { @MainActor in
                    AppRuntimeDiagnostics.logWindowNotification(label: label, notification: notification)
                }
            }
        }
    }

    private func scheduleLaunchSnapshots() {
        Task { @MainActor in
            for (delay, reason) in [
                (UInt64(250_000_000), "post-launch +250ms"),
                (UInt64(1_000_000_000), "post-launch +1.25s"),
                (UInt64(3_000_000_000), "post-launch +4.25s"),
            ] {
                try? await Task.sleep(nanoseconds: delay)
                AppRuntimeDiagnostics.logSnapshot(reason: reason)
            }
        }
    }
}

@MainActor
enum AppRuntimeDiagnostics {
    static func logSnapshot(reason: String) {
        guard let app = NSApp else {
            AppLogger.windows.notice("\(reason, privacy: .public) no NSApp available")
            return
        }

        let activationPolicy: String
        switch app.activationPolicy() {
        case .regular:
            activationPolicy = "regular"
        case .accessory:
            activationPolicy = "accessory"
        case .prohibited:
            activationPolicy = "prohibited"
        @unknown default:
            activationPolicy = "unknown"
        }

        let windowDescriptions = app.windows.map(windowDescription).joined(separator: " || ")
        let message = "\(reason) policy=\(activationPolicy) isActive=\(app.isActive) hidden=\(app.isHidden) windows=\(app.windows.count) orderedWindows=\(app.orderedWindows.count) mainWindow=\(app.mainWindow?.title ?? "<nil>") keyWindow=\(app.keyWindow?.title ?? "<nil>") windows=[\(windowDescriptions)]"
        AppLogger.windows.notice("\(message, privacy: .public)")
    }

    static func logWindowNotification(label: String, notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            AppLogger.windows.notice("\(label, privacy: .public) notification without NSWindow")
            logSnapshot(reason: "window-notification \(label)")
            return
        }

        let message = "\(label) title=\(window.title) visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) miniaturized=\(window.isMiniaturized) occlusion=\(window.occlusionState.rawValue)"
        AppLogger.windows.notice("\(message, privacy: .public)")
        logSnapshot(reason: "window-notification \(label)")
    }

    private static func windowDescription(_ window: NSWindow) -> String {
        let title = window.title.isEmpty ? "<untitled>" : window.title
        let frame = NSStringFromRect(window.frame)
        let screen = window.screen?.localizedName ?? "<no-screen>"
        return "title=\(title) visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) miniaturized=\(window.isMiniaturized) frame=\(frame) screen=\(screen)"
    }
}

// MARK: - Sparkle Check for Updates menu item

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var observation: Any?

    init(updater: SPUUpdater) {
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, change in
            DispatchQueue.main.async {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }
}
