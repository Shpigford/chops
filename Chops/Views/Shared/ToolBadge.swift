import SwiftUI

/// Small text badge for the metadata bar
struct ToolBadge: View {
    let tool: ToolSource

    var body: some View {
        Text(tool.shortLabel)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
    }
}

/// Icon for the sidebar — uses custom logo asset or SF Symbol fallback
struct ToolIcon: View {
    let tool: ToolSource
    var size: CGFloat = 16

    var body: some View {
        if let assetName = tool.logoAssetName {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: tool.iconName)
                .font(.system(size: size * 0.7))
                .frame(width: size, height: size)
        }
    }
}

extension ToolSource {
    var shortLabel: String {
        switch self {
        case .claude: "CC"
        case .cursor: "CU"
        case .windsurf: "WS"
        case .codex: "CX"
        case .copilot: "CP"
        case .aider: "AI"
        case .amp: "AM"
        case .custom: "?"
        }
    }
}
