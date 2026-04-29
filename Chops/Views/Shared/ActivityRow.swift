import SwiftUI

/// One row in the agent activity feed. Tap to expand and see what the step actually did
/// — a diff for Write/Edit/MultiEdit, or the raw input/output for everything else.
struct ActivityRow: View {
    let activity: AgentActivity
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if hasExpandableDetail { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    statusIcon
                        .frame(width: 14, alignment: .center)
                    Text(activity.title)
                        .font(.callout)
                        .foregroundStyle(textColor)
                    if let detail = activity.detail {
                        Text(detail)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if hasExpandableDetail {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                .truncationMode(.middle)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasExpandableDetail)

            if expanded {
                expandedDetail
                    .padding(.leading, 22)
                    .padding(.top, 4)
            }
        }
    }

    private var hasExpandableDetail: Bool {
        let p = activity.payload
        return p.proposedText != nil || p.rawInput != nil || p.resultText != nil
    }

    private var textColor: Color {
        switch activity.status {
        case .failed:  return .red
        case .applied: return .primary
        default:       return .primary
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch activity.status {
        case .running:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .applied:
            // Distinct icon so the user can see at a glance "this changed disk".
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var expandedDetail: some View {
        let p = activity.payload
        if let proposed = p.proposedText {
            // Diff view for Write / Edit / MultiEdit.
            DiffReviewPanel(
                original: p.originalText ?? "",
                proposed: proposed,
                onAccept: nil,
                onReject: nil,
                isApplying: false
            )
            .frame(minHeight: 200, idealHeight: 280, maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
        } else if let result = p.resultText {
            // Read / Bash / Grep / etc. — surface the tool result.
            ScrollView {
                Text(result)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 240)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
        } else if let raw = p.rawInput {
            // Fallback: show the raw input JSON.
            ScrollView {
                Text(raw)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 200)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
        }
    }
}
