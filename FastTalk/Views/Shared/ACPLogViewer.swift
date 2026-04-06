import SwiftUI

/// Viewer for ACP debug logs
struct ACPLogViewer: View {
    @State private var logContent = ""
    @State private var debugEnabled = acpLog.debugEnabled
    @State private var autoRefresh = true
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("ACP Logs")
                    .font(.headline)

                Spacer()

                Toggle("Debug Mode", isOn: $debugEnabled)
                    .controlSize(.small)
                    .onChange(of: debugEnabled) { _, newValue in
                        acpLog.debugEnabled = newValue
                    }

                Toggle("Auto-refresh", isOn: $autoRefresh)
                    .controlSize(.small)

                Button {
                    refreshLogs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .accessibilityLabel("Refresh")

                Button {
                    acpLog.clearLogs()
                    refreshLogs()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear Logs")
                .accessibilityLabel("Clear Logs")

                Button {
                    NSWorkspace.shared.selectFile(acpLog.logURL.path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logContent)
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .id("bottom")
                }
                .onChange(of: logContent) { _, _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .background(.regularMaterial)
        }
        .onAppear {
            refreshLogs()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }

    private func refreshLogs() {
        Task {
            let content = await acpLog.recentLogs(lines: 500)
            logContent = content
        }
    }

    private func startAutoRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard autoRefresh else { continue }
                let content = await acpLog.recentLogs(lines: 500)
                logContent = content
            }
        }
    }
}

#Preview {
    ACPLogViewer()
        .frame(width: 600, height: 400)
}
