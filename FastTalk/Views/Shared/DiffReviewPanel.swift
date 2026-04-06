import SwiftUI

// MARK: - Diff Model

enum DiffLineKind {
    case unchanged, added, removed

    var prefix: String {
        switch self {
        case .unchanged: " "
        case .added:     "+"
        case .removed:   "-"
        }
    }

    var prefixColor: Color {
        switch self {
        case .unchanged: .secondary
        case .added:     Color(NSColor.systemGreen)
        case .removed:   Color(NSColor.systemRed)
        }
    }

    var background: Color {
        switch self {
        case .unchanged: .clear
        case .added:     Color(NSColor.systemGreen).opacity(0.12)
        case .removed:   Color(NSColor.systemRed).opacity(0.12)
        }
    }
}

struct DiffLine: Identifiable {
    let id = UUID()
    let text: String
    let kind: DiffLineKind
}

// MARK: - LCS Diff Engine

/// Computes a unified diff via LCS. O(n·m) — suitable for files up to ~3 000 lines.
/// Must not be called on the main actor for large inputs; use Task.detached at the call site.
func computeDiff(from original: String, to proposed: String) -> [DiffLine] {
    let a = original.components(separatedBy: .newlines)
    let b = proposed.components(separatedBy: .newlines)

    let m = a.count, n = b.count

    // Guard: ClosedRange 1...0 traps at runtime; handle empty inputs explicitly.
    guard m > 0, n > 0 else {
        let removals = a.map { DiffLine(text: $0, kind: .removed) }
        let additions = b.map { DiffLine(text: $0, kind: .added) }
        return removals + additions
    }

    // Guard: prevent OOM on very large files. Beyond 3 000 lines the LCS matrix
    // exceeds ~72 MB. Treat oversized input as a full replacement diff.
    let lineLimit = 3_000
    guard m <= lineLimit, n <= lineLimit else {
        let removals = a.map { DiffLine(text: $0, kind: .removed) }
        let additions = b.map { DiffLine(text: $0, kind: .added) }
        return removals + additions
    }

    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in 1...m {
        for j in 1...n {
            dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1] + 1 : max(dp[i-1][j], dp[i][j-1])
        }
    }

    // Backtrack to collect LCS pairs (originalIndex, proposedIndex)
    var pairs: [(Int, Int)] = []
    var i = m, j = n
    while i > 0 && j > 0 {
        if a[i-1] == b[j-1] { pairs.append((i-1, j-1)); i -= 1; j -= 1 }
        else if dp[i-1][j] >= dp[i][j-1] { i -= 1 } else { j -= 1 }
    }
    pairs.reverse()

    // Walk both arrays, emitting diff lines
    var result: [DiffLine] = []
    var ai = 0, bi = 0
    for (oi, pi) in pairs {
        while ai < oi { result.append(DiffLine(text: a[ai], kind: .removed)); ai += 1 }
        while bi < pi { result.append(DiffLine(text: b[bi], kind: .added));   bi += 1 }
        result.append(DiffLine(text: a[ai], kind: .unchanged))
        ai += 1; bi += 1
    }
    while ai < m { result.append(DiffLine(text: a[ai], kind: .removed)); ai += 1 }
    while bi < n { result.append(DiffLine(text: b[bi], kind: .added));   bi += 1 }
    return result
}

// MARK: - DiffReviewPanel

/// Shows a unified diff between `original` and `proposed` with Accept / Reject controls.
struct DiffReviewPanel: View {
    let original: String
    let proposed: String
    let onAccept: () -> Void
    let onReject: () -> Void
    var isApplying = false

    @State private var lines: [DiffLine] = []

    private var addedCount:   Int { lines.filter { $0.kind == .added   }.count }
    private var removedCount: Int { lines.filter { $0.kind == .removed }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            diffScroll
        }
        .task {
            // Compute off the main actor — LCS allocates O(n·m) memory; blocks UI for large files.
            let result = await Task.detached(priority: .userInitiated) {
                computeDiff(from: original, to: proposed)
            }.value
            lines = result
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "plusminus")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("+\(addedCount)")
                .font(.caption.monospaced())
                .foregroundStyle(Color(NSColor.systemGreen))
            Text("-\(removedCount)")
                .font(.caption.monospaced())
                .foregroundStyle(Color(NSColor.systemRed))

            Spacer()

            Text("Review Changes")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Reject", action: onReject)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .disabled(isApplying)

            Button(isApplying ? "Applying..." : "Accept", action: onAccept)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color(NSColor.systemGreen))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isApplying)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var diffScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: 4) {
                        Text(line.kind.prefix)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(line.kind.prefixColor)
                            .frame(width: 10, alignment: .center)
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(line.kind == .unchanged ? .primary : line.kind.prefixColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(line.kind.background)
                    .accessibilityLabel("\(line.kind.prefix) \(line.text)")
                }
            }
        }
        .background(.regularMaterial)
    }
}

// MARK: - Preview

#Preview {
    DiffReviewPanel(
        original: "# My Skill\n\nOld content here.\nLine two.\n",
        proposed: "# My Skill\n\nNew content here.\nLine two.\nLine three added.\n",
        onAccept: {},
        onReject: {},
        isApplying: false
    )
    .frame(width: 600, height: 300)
}
