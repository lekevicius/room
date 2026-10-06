import AppKit
import Design
import Foundation

/// What Chrome's DOM Distiller found on a page (4.7b): its
/// `DomDistillerResult` (`third_party/dom_distiller_js/dom_distiller.proto`)
/// as the script returns it, a dictionary keyed by field numbers.
nonisolated public struct ReaderArticle: Equatable, Sendable {
    public var title: String
    /// `distilled_content.html`: the article's markup, images with absolute URLs.
    public var contentHTML: String
    /// `text_content`, or the markup's text when the distiller gave none.
    public var text: String
    /// `text_direction`: "ltr", "rtl" or "auto".
    public var textDirection: String
    public var wordCount: Int?
    /// `content_images[].url`.
    public var imageURLs: [String]
    /// `timing_info.total_time`, the distiller's own milliseconds.
    public var distillerMilliseconds: Double?

    public init(title: String, contentHTML: String, text: String, textDirection: String = "auto", wordCount: Int? = nil,
                imageURLs: [String] = [], distillerMilliseconds: Double? = nil) {
        self.title = title
        self.contentHTML = contentHTML
        self.text = text
        self.textDirection = textDirection
        self.wordCount = wordCount
        self.imageURLs = imageURLs
        self.distillerMilliseconds = distillerMilliseconds
    }

    /// The text's length in characters, whitespace runs counted once.
    public var textLength: Int { ReaderRules.collapsedWhitespace(text).count }
}

nonisolated public enum ReaderError: Error, Equatable, Sendable {
    /// The script returned nothing (`null`: it threw inside, or the page has no document).
    case noResult
    /// The answer was not the distiller's dictionary.
    case malformed(String)
}

/// Reader mode's pure parts (4.7b): the distiller's script around Chrome's
/// `domdistiller.js`, its answer, the article threshold, and the reader
/// page from `App/Resources/Reader/reader.html`.
public enum ReaderRules {
    /// The text sizes the page knows, in `ReaderMetrics.textSizes`' order
    /// (`Settings.readerTextSize`'s raw values).
    public static let textSizeNames = ["small", "medium", "large"]

    /// Chrome's own wrapping (`components/dom_distiller/core/javascript/
    /// domdistiller.js`): timers stubbed while the GWT module initialises on
    /// `window` (the isolated world's own global, so the page's window is not
    /// changed), then `DomDistiller.applyWithOptions` with
    /// `DomDistillerOptions` as field numbers (1 extract_text_only,
    /// 2 debug_level, 3 original_url). The result object is the script's
    /// value (the engine returns it as JSON). (Chrome's older
    /// `domdistiller_wrapped.js` initialises it on `Object.create(window)`,
    /// which throws "Illegal invocation" at `window.document`'s getter.)
    public static func distillerScript(_ distiller: String, url: URL?) -> String {
        var options: [String: Any] = ["1": false, "2": 0]
        if let url { options["3"] = url.absoluteString }
        let json = (try? JSONSerialization.data(withJSONObject: options, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return """
        (() => {
          const setTimeoutWas = window.setTimeout;
          const clearTimeoutWas = window.clearTimeout;
          window.setTimeout = function() {};
          window.clearTimeout = function() {};
          try {
        \(distiller)
            const result = window.org.chromium.distiller.DomDistiller.applyWithOptions(\(json));
            return result === undefined ? null : result;
          } finally {
            window.setTimeout = setTimeoutWas;
            window.clearTimeout = clearTimeoutWas;
          }
        })()
        """
    }

    /// The distiller's answer (the engine's JSON text of the result object).
    public static func parse(_ json: String) throws -> ReaderArticle {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
        } catch {
            throw ReaderError.malformed("not JSON")
        }
        if value is NSNull { throw ReaderError.noResult }
        guard let result = value as? [String: Any] else { throw ReaderError.malformed("not a dictionary") }
        let html = ((result["2"] as? [String: Any])?["1"] as? String) ?? ""
        let text = (result["11"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? plainText(fromHTML: html)
        let images = (result["10"] as? [[String: Any]] ?? []).compactMap { $0["1"] as? String }
        let words = ((result["8"] as? [String: Any])?["1"] as? NSNumber)?.intValue
        let total = ((result["6"] as? [String: Any])?["5"] as? NSNumber)?.doubleValue
        let direction = (result["9"] as? String).flatMap { ["ltr", "rtl", "auto"].contains($0) ? $0 : nil } ?? "auto"
        return ReaderArticle(title: (result["1"] as? String) ?? "", contentHTML: html, text: text, textDirection: direction,
                             wordCount: words, imageURLs: images, distillerMilliseconds: total)
    }

    /// Whether the page reads as an article: the distiller kept at least
    /// `minimum` characters of text (a dashboard of short widgets does not).
    public static func isArticle(_ article: ReaderArticle, minimum: Int = ReaderMetrics.minimumArticleCharacters) -> Bool {
        article.textLength >= minimum
    }

    /// The markup's text: tags dropped, the five entities decoded, whitespace collapsed.
    public static func plainText(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return collapsedWhitespace(text)
    }

    nonisolated static func collapsedWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Text for HTML: `& < > " '` escaped (titles, hosts, URLs in attributes).
    public static func escape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    /// The reader page: `template` with its `{{NAME}}` slots filled in one
    /// pass (a slot's value is never scanned again, so an article that
    /// mentions `{{TITLE}}` stays as it is). The article's markup goes in as
    /// the distiller left it; everything else is escaped.
    public static func page(template: String, article: ReaderArticle, source: URL, style: String, textSize: String,
                            appearance: String) -> String {
        let host = source.host() ?? source.absoluteString
        let title = article.title.isEmpty ? host : article.title
        let values: [String: String] = [
            "STYLE": style,
            "TITLE": escape(title),
            "HOST": escape(host),
            "URL": escape(source.absoluteString),
            "DIRECTION": escape(article.textDirection),
            "SIZE": escape(textSizeNames.contains(textSize) ? textSize : "medium"),
            "APPEARANCE": escape(appearance),
            "CONTENT": article.contentHTML,
        ]
        return fill(template, values)
    }

    /// One left-to-right pass over `template`: `{{NAME}}` becomes `values[NAME]`; unknown slots stay.
    static func fill(_ template: String, _ values: [String: String]) -> String {
        var result = ""
        var rest = template[...]
        while let open = rest.range(of: "{{") {
            result += rest[..<open.lowerBound]
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else {
                rest = rest[open.lowerBound...]
                break
            }
            let name = String(after[..<close.lowerBound])
            if let value = values[name] {
                result += value
            } else {
                result += rest[open.lowerBound..<close.upperBound]
            }
            rest = after[close.upperBound...]
        }
        result += rest
        return result
    }
}

/// The reader page's CSS variables, generated from the design tokens: the
/// colours (`Palette.cardBackground` and the system label, link and
/// separator colours resolved in Aqua and Dark Aqua) and the type
/// (`ReaderMetrics`). Light is the default and `[data-appearance="light"]`;
/// dark is `[data-appearance="dark"]`, and `prefers-color-scheme: dark`
/// when the page is told neither.
public enum ReaderStyle {
    /// The colour variables for one appearance, in a fixed order.
    public static func colorVariables(for appearance: NSAppearance) -> [(name: String, value: String)] {
        [
            ("--room-background", rgba(Palette.cardBackground, appearance)),
            ("--room-text", rgba(.labelColor, appearance)),
            ("--room-secondary", rgba(.secondaryLabelColor, appearance)),
            ("--room-link", rgba(.linkColor, appearance)),
            ("--room-separator", rgba(.separatorColor, appearance)),
        ]
    }

    /// The type and spacing variables (the same in both appearances); the
    /// text size by `data-size`.
    public static var typeVariables: [(name: String, value: String)] {
        [
            ("--room-text-size", px(ReaderMetrics.textSizes[1])),
            ("--room-title-scale", number(ReaderMetrics.titleScale)),
            ("--room-heading-scale", number(ReaderMetrics.headingScale)),
            ("--room-secondary-scale", number(ReaderMetrics.secondaryScale)),
            ("--room-line-height", number(ReaderMetrics.lineHeight)),
            ("--room-measure", number(ReaderMetrics.measure) + "em"),
            ("--room-page-padding", px(ReaderMetrics.pagePadding)),
            ("--room-block-gap", px(ReaderMetrics.blockGap)),
            ("--room-image-radius", px(ReaderMetrics.imageRadius)),
        ]
    }

    /// The whole variables block for the template's `{{STYLE}}` slot.
    public static func css() -> String {
        guard let light = NSAppearance(named: .aqua), let dark = NSAppearance(named: .darkAqua) else { return "" }
        func block(_ variables: [(name: String, value: String)]) -> String {
            variables.map { "  \($0.name): \($0.value);" }.joined(separator: "\n")
        }
        let sizes = zip(ReaderRules.textSizeNames, ReaderMetrics.textSizes).map { name, size in
            ":root[data-size=\"\(name)\"] { --room-text-size: \(px(size)); }"
        }
        return """
        :root, :root[data-appearance="light"] {
        \(block(typeVariables + colorVariables(for: light)))
          color-scheme: light;
        }
        :root[data-appearance="dark"] {
        \(block(colorVariables(for: dark)))
          color-scheme: dark;
        }
        @media (prefers-color-scheme: dark) {
          :root:not([data-appearance="light"]) {
        \(block(colorVariables(for: dark)))
            color-scheme: dark;
          }
        }
        \(sizes.joined(separator: "\n"))
        """
    }

    /// `rgba(r, g, b, a)` of `color` in sRGB as `appearance` draws it.
    public static func rgba(_ color: NSColor, _ appearance: NSAppearance) -> String {
        let resolved = color.resolved(for: appearance).usingColorSpace(.sRGB) ?? color
        let channel = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return "rgba(\(channel(resolved.redComponent)), \(channel(resolved.greenComponent)), \(channel(resolved.blueComponent)), "
            + "\(number(resolved.alphaComponent)))"
    }

    static func px(_ value: CGFloat) -> String { number(value) + "px" }

    static func number(_ value: CGFloat) -> String {
        let rounded = (value * 1000).rounded() / 1000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", Double(rounded))
    }
}
