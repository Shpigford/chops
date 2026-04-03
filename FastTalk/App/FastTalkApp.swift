import SwiftUI
import SwiftData
import AppKit

@main
struct FastTalkApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleLogger.self) private var lifecycleLogger
    @State private var appState = AppState()
    @AppStorage("ACPDebugLogging") private var debugLoggingEnabled = false

    init() {
        AppLogger.lifecycle.notice("FastTalkApp init bundleID=\(Bundle.main.bundleIdentifier ?? "unknown", privacy: .public)")
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)

        do {
            let config = try StoreBootstrap.makeConfiguration(schema: schema)
            return try ModelContainer(
                for: schema,
                migrationPlan: FastTalkMigrationPlan.self,
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
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .newNoteRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.sidebarFilter != .allNotes)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveCurrentSkill, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState.selectedSkill == nil)
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
            SettingsView()
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
        NSApp?.setActivationPolicy(.regular)
        AppRuntimeDiagnostics.logSnapshot(reason: "applicationDidFinishLaunching")
        scheduleLaunchSnapshots()
        scheduleWindowRecovery()
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
        if !flag {
            AppRuntimeDiagnostics.ensureVisibleWindow(reason: "applicationShouldHandleReopen")
        }
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

    private func scheduleWindowRecovery() {
        Task { @MainActor in
            for (delay, reason) in [
                (UInt64(250_000_000), "post-launch recovery +250ms"),
                (UInt64(500_000_000), "post-launch recovery +750ms"),
                (UInt64(750_000_000), "post-launch recovery +1.5s"),
            ] {
                try? await Task.sleep(nanoseconds: delay)
                AppRuntimeDiagnostics.ensureVisibleWindow(reason: reason)
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
        let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "<nil>"
        let message = "\(reason) policy=\(activationPolicy) isActive=\(app.isActive) hidden=\(app.isHidden) frontmostApp=\(frontmostApp) windows=\(app.windows.count) orderedWindows=\(app.orderedWindows.count) mainWindow=\(app.mainWindow?.title ?? "<nil>") keyWindow=\(app.keyWindow?.title ?? "<nil>") windows=[\(windowDescriptions)]"
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

    static func ensureVisibleWindow(reason: String) {
        guard let app = NSApp else {
            AppLogger.windows.notice("\(reason, privacy: .public) cannot recover window without NSApp")
            return
        }

        let candidateWindows = app.windows.filter { !$0.isMiniaturized }
        guard let window = candidateWindows.first else {
            AppLogger.windows.notice("\(reason, privacy: .public) no candidate windows to surface")
            return
        }

        let hasVisibleWindow = candidateWindows.contains(where: \.isVisible)
        let needsActivation = !app.isActive || app.mainWindow == nil || app.keyWindow == nil

        guard !hasVisibleWindow || needsActivation else {
            AppLogger.windows.notice("\(reason, privacy: .public) skipped recovery because the app is already visible and active")
            return
        }

        AppLogger.windows.notice("\(reason, privacy: .public) forcing primary window foreground visible")

        if app.activationPolicy() != .regular {
            app.setActivationPolicy(.regular)
        }

        if window.screen == nil {
            window.center()
        }

        var collectionBehavior = window.collectionBehavior
        collectionBehavior.insert(.moveToActiveSpace)
        window.collectionBehavior = collectionBehavior

        app.unhide(nil)
        app.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        app.arrangeInFront(nil)
        app.activate(ignoringOtherApps: true)

        logSnapshot(reason: "\(reason) after ensureVisibleWindow")

        if !app.isActive, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow" {
            AppLogger.windows.error("\(reason, privacy: .public) app is running in a loginwindow-fronted session; launch from the Aqua desktop session to surface the UI")
        }
    }

    private static func windowDescription(_ window: NSWindow) -> String {
        let title = window.title.isEmpty ? "<untitled>" : window.title
        let frame = NSStringFromRect(window.frame)
        let screen = window.screen?.localizedName ?? "<no-screen>"
        return "title=\(title) visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) miniaturized=\(window.isMiniaturized) frame=\(frame) screen=\(screen)"
    }
}
