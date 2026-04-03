import SwiftUI

/// Collapsible "Thinking" section rendered outside the assistant bubble.
/// `isStreaming` is passed from the parent and should only flip false once (when the turn ends).
struct ThinkingView: View {
    let text: String
    let isStreaming: Bool

    @State private var isExpanded: Bool = false
    /// Latched true once streaming ends — shows brain icon instead of spinner.
    @State private var settled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !settled {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "brain")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("Thinking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if isExpanded {
                ScrollView(.vertical) {
                    Text(text)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .opacity(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(.bottom, 4)
        .onAppear {
            // Already settled when created for a completed message (isStreaming never flips).
            if !isStreaming {
                settled = true
                isExpanded = false
            }
        }
        .onChange(of: isStreaming) { _, streaming in
            if !streaming {
                settled = true
                withAnimation(.easeInOut(duration: 0.3)) { isExpanded = false }
            }
        }
    }
}
