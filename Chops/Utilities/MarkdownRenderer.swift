import Foundation
import Highlightr
import JavaScriptCore
import cmark

enum MarkdownRenderer {
    static func renderHTML(_ markdown: String, isDarkMode: Bool) -> String {
        guard !markdown.isEmpty else { return "" }

        let len = markdown.utf8.count
        let options = Int32(CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE)

        guard let buf = cmark_gfm_markdown_to_html(markdown, len, options) else { return "" }
        let html = String(cString: buf)
        free(buf)

        return PreviewCodeHighlighter.shared.highlightCodeBlocks(in: html, isDarkMode: isDarkMode)
    }

    static func themeCSS(isDarkMode: Bool) -> String {
        PreviewCodeHighlighter.shared.themeCSS(isDarkMode: isDarkMode)
    }
}

private final class PreviewCodeHighlighter {
    static let shared = PreviewCodeHighlighter()

    private static let codeBlockRegex = try! NSRegularExpression(
        pattern: #"<pre([^>]*)><code(?: class="([^"]*)")?>([\s\S]*?)</code></pre>"#,
        options: []
    )

    private let bundle: Bundle?
    private let hljs: JSValue?
    private var cssCache: [String: String] = [:]

    private init() {
        self.bundle = Self.resourceBundle()

        guard let jsContext = JSContext(),
              let bundle,
              let highlightPath = bundle.path(forResource: "highlight.min", ofType: "js"),
              let highlightJS = try? String(contentsOfFile: highlightPath, encoding: .utf8) else {
            self.hljs = nil
            return
        }

        jsContext.evaluateScript(highlightJS)
        self.hljs = jsContext.objectForKeyedSubscript("hljs")
    }

    func highlightCodeBlocks(in html: String, isDarkMode: Bool) -> String {
        let nsHTML = html as NSString
        let matches = Self.codeBlockRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        guard !matches.isEmpty else { return html }

        var rendered = ""
        var currentLocation = 0

        for match in matches {
            let blockRange = match.range(at: 0)
            rendered += nsHTML.substring(with: NSRange(location: currentLocation, length: blockRange.location - currentLocation))

            let preAttributes = substring(in: nsHTML, range: match.range(at: 1))
            let classNames = substring(in: nsHTML, range: match.range(at: 2))
            let encodedCode = substring(in: nsHTML, range: match.range(at: 3)) ?? ""

            let language = languageName(classNames: classNames, preAttributes: preAttributes)
            let code = decodeHTML(encodedCode)

            if let highlighted = highlightedHTML(for: code, language: language, isDarkMode: isDarkMode) {
                rendered += highlighted
            } else {
                rendered += nsHTML.substring(with: blockRange)
            }

            currentLocation = blockRange.location + blockRange.length
        }

        rendered += nsHTML.substring(from: currentLocation)
        return rendered
    }

    func themeCSS(isDarkMode: Bool) -> String {
        let themeName = isDarkMode ? "atom-one-dark" : "atom-one-light"

        if let cached = cssCache[themeName] {
            return cached
        }

        guard let bundle,
              let themePath = bundle.path(forResource: themeName + ".min", ofType: "css"),
              let css = try? String(contentsOfFile: themePath, encoding: .utf8) else {
            return ""
        }

        cssCache[themeName] = css
        return css
    }

    private func highlightedHTML(for code: String, language: String?, isDarkMode: Bool) -> String? {
        guard let hljs else { return nil }

        let result: JSValue?
        if let language, !language.isEmpty {
            let highlighted = hljs.invokeMethod("highlight", withArguments: [language, code, false])
            if highlighted?.isUndefined == false {
                result = highlighted
            } else {
                result = hljs.invokeMethod("highlightAuto", withArguments: [code])
            }
        } else {
            result = hljs.invokeMethod("highlightAuto", withArguments: [code])
        }

        guard let html = result?.objectForKeyedSubscript("value")?.toString() else {
            return nil
        }

        let languageClass = language.map { " language-\($0)" } ?? ""
        let themeClass = isDarkMode ? "dark" : "light"

        return """
        <pre class="highlighted-code \(themeClass)"><code class="hljs\(languageClass)">\(html)</code></pre>
        """
    }

    private func languageName(classNames: String?, preAttributes: String?) -> String? {
        if let classNames {
            for className in classNames.split(separator: " ") {
                if className.hasPrefix("language-") {
                    return String(className.dropFirst("language-".count))
                }
                if className.hasPrefix("lang-") {
                    return String(className.dropFirst("lang-".count))
                }
            }
        }

        guard let preAttributes else { return nil }

        let pattern = #"lang="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: preAttributes, range: NSRange(location: 0, length: (preAttributes as NSString).length)) else {
            return nil
        }

        return substring(in: preAttributes as NSString, range: match.range(at: 1))
    }

    private func substring(in string: NSString, range: NSRange) -> String? {
        guard range.location != NSNotFound else { return nil }
        return string.substring(with: range)
    }

    private func decodeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func resourceBundle() -> Bundle? {
        let bundleName = "Highlightr_Highlightr"
        let overrides: [URL]

        if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"]
            ?? ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            overrides = [URL(fileURLWithPath: override)]
        } else {
            overrides = []
        }

        let candidates = overrides + [
            Bundle.main.resourceURL,
            Bundle(for: ResourceBundleFinder.self).resourceURL,
            Bundle.main.bundleURL
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }

        return nil
    }
}

private final class ResourceBundleFinder {}
