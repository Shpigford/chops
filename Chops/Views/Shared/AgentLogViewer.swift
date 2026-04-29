import SwiftUI

/// Viewer for the agent debug log file written by `AgentLogger`.
struct AgentLogViewer: View {
    @State private var logContent = ""
    @State private var debugEnabled = agentLog.debugEnabled
    @State private var autoRefresh = true
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent Logs")
                    .font(.headline)

                Spacer()

                Toggle("Debug Mode", isOn: $debugEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: debugEnabled) { _, newValue in
                        agentLog.debugEnabled = newValue
                    }

                Toggle("Auto-refresh", isOn: $autoRefresh)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Button {
                    refreshLogs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")

                Button {
                    agentLog.clearLogs()
                    refreshLogs()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear Logs")

                Button {
                    NSWorkspace.shared.selectFile(agentLog.logURL.path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(logContent)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                        .id("bottom")
                }
                .onChange(of: logContent) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .background(Color(.textBackgroundColor))
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
            logContent = await agentLog.recentLogs(lines: 500)
        }
    }

    private func startAutoRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard autoRefresh else { continue }
                logContent = await agentLog.recentLogs(lines: 500)
            }
        }
    }
}

#Preview {
    AgentLogViewer()
        .frame(width: 600, height: 400)
}
