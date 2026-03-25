import SwiftUI
import MarkdownUI

struct SkillPreviewView: View {
    let content: String

    var body: some View {
        let parsed = RawFrontmatterParser.parse(content)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let frontmatter = parsed?.frontmatter {
                    FrontmatterBlockView(frontmatter: frontmatter)
                        .padding(.bottom, 24)
                }

                Markdown(parsed?.content ?? content)
                    .markdownTheme(.clearly)
                    .markdownCodeSyntaxHighlighter(HighlightrSyntaxHighlighter())
                    .textSelection(.enabled)
            }
            .padding(24)
            .frame(maxWidth: 672, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.clearlyBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Frontmatter Block

private struct FrontmatterBlockView: View {
    let frontmatter: String

    var body: some View {
        Text(frontmatter)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color.clearlyFmValue)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clearlyFmBg)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.clearlyFmBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private enum RawFrontmatterParser {
    struct Result {
        let frontmatter: String?
        let content: String
    }

    static func parse(_ text: String) -> Result? {
        let lines = text.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        for index in 1..<lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                let frontmatterLines = Array(lines[1..<index])
                let frontmatter = frontmatterLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let contentStart = min(index + 1, lines.count)
                let content = Array(lines[contentStart...]).joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return Result(
                    frontmatter: frontmatter.isEmpty ? nil : frontmatter,
                    content: content
                )
            }
        }

        return nil
    }
}

// MARK: - Clearly Theme

extension Theme {
    static let clearly = Theme()
        .text {
            ForegroundColor(.clearlyText)
            BackgroundColor(.clearlyBackground)
            FontSize(16)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
            ForegroundColor(.clearlyCode)
            BackgroundColor(.clearlyInlineCodeBg)
        }
        .strong {
            FontWeight(.bold)
        }
        .link {
            ForegroundColor(.clearlyLink)
        }
        .heading1 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: .em(1.5), bottom: .em(0.5))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(2))
                }
        }
        .heading2 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: .em(1.5), bottom: .em(0.5))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.5))
                }
        }
        .heading3 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: .em(1.5), bottom: .em(0.5))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.25))
                }
        }
        .heading4 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: .em(1.5), bottom: .em(0.5))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.1))
                }
        }
        .heading5 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: .em(1.5), bottom: .em(0.5))
                .markdownTextStyle {
                    FontWeight(.bold)
                }
        }
        .heading6 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: .em(1.5), bottom: .em(0.5))
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(0.85))
                    ForegroundColor(.clearlyBlockquoteText)
                }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.3))
                .markdownMargin(top: 0, bottom: 16)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.clearlyBlockquoteBorder)
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.clearlyBlockquoteText)
                        FontStyle(.italic)
                    }
                    .relativePadding(.horizontal, length: .em(1))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.225))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
                    .padding(16)
            }
            .background(Color.clearlyCodeBlockBg)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.clearlyCodeBlockBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .markdownMargin(top: 0, bottom: 16)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.25))
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: .clearlyTableBorder))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clearlyBackground, Color.clearlyTableAltRow)
                )
                .markdownMargin(top: 0, bottom: 16)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    BackgroundColor(nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 13)
                .relativeLineSpacing(.em(0.25))
        }
        .thematicBreak {
            Divider()
                .overlay(Color.clearlyHr)
                .markdownMargin(top: .em(2), bottom: .em(2))
        }
}

// MARK: - Color Palette

private extension Color {
    static let clearlyText = Color(
        light: Color(rgba: 0x2222_22ff), dark: Color(rgba: 0xE0E0_E0ff)
    )
    static let clearlyBackground = Color(
        light: Color(rgba: 0xFAFA_FAff), dark: Color(rgba: 0x1A1A_1Aff)
    )
    static let clearlyCode = Color(
        light: Color(rgba: 0xCC33_33ff), dark: Color(rgba: 0xE070_70ff)
    )
    static let clearlyCodeBlockBg = Color(
        light: Color(rgba: 0xF5F5_F5ff), dark: Color(rgba: 0x2A2A_2Aff)
    )
    static let clearlyCodeBlockBorder = Color(
        light: Color(rgba: 0xE0E0_E0ff), dark: Color(rgba: 0x3333_33ff)
    )
    static let clearlyInlineCodeBg = Color(
        light: Color(rgba: 0xF0F0_F0ff), dark: Color(rgba: 0x2A2A_2Aff)
    )
    static let clearlyLink = Color(
        light: Color(rgba: 0x3366_AAff), dark: Color(rgba: 0x6699_CCff)
    )
    static let clearlyBlockquoteText = Color(
        light: Color(rgba: 0x6666_66ff), dark: Color(rgba: 0x9999_99ff)
    )
    static let clearlyBlockquoteBorder = Color(
        light: Color(rgba: 0xCCCC_CCff), dark: Color(rgba: 0x4444_44ff)
    )
    static let clearlyHr = Color(
        light: Color(rgba: 0xDDDD_DDff), dark: Color(rgba: 0x3333_33ff)
    )
    static let clearlyTableBorder = Color(
        light: Color(rgba: 0xE0E0_E0ff), dark: Color(rgba: 0x3333_33ff)
    )
    static let clearlyTableAltRow = Color(
        light: Color(rgba: 0xF5F5_F5ff), dark: Color(rgba: 0x2222_22ff)
    )
    static let clearlyFmBg = Color(
        light: Color(rgba: 0xF0F0_F0ff), dark: Color(rgba: 0x2222_22ff)
    )
    static let clearlyFmBorder = Color(
        light: .clear, dark: Color(rgba: 0x3333_33ff)
    )
    static let clearlyFmValue = Color(
        light: Color(rgba: 0x3333_33ff), dark: Color(rgba: 0x9999_99ff)
    )
}
