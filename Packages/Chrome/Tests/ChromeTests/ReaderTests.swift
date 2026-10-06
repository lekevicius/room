import AppKit
import Design
import Engine
import Testing
@testable import Chrome

/// Reader mode's pure parts (4.7b): the distiller's answer, the article
/// threshold, the page template and its CSS variables from the tokens.
@Suite("Reader mode")
struct ReaderTests {
    /// The shape `DomDistiller.applyWithOptions` returns (field numbers of
    /// `DomDistillerResult`), as the engine hands it back in JSON.
    static let articleJSON = """
    {"1":"A Long Walk","2":{"1":"<h2>Morning</h2><p>First paragraph &amp; more.</p><img src=\\"http://127.0.0.1:8777/phase-4.7/swatch.png\\">"},\
    "6":{"1":0.4,"5":12.5},"8":{"1":321},"9":"ltr","10":[{"1":"http://127.0.0.1:8777/phase-4.7/swatch.png"},{"1":"http://127.0.0.1:8777/phase-4.7/b.png"}],\
    "11":"Morning First paragraph & more."}
    """

    @Test("The distiller's dictionary: title, markup, text, direction, words, images, timing")
    func parsesArticle() throws {
        let article = try ReaderRules.parse(Self.articleJSON)
        #expect(article.title == "A Long Walk")
        #expect(article.contentHTML.hasPrefix("<h2>Morning</h2>"))
        #expect(article.text == "Morning First paragraph & more.")
        #expect(article.textDirection == "ltr")
        #expect(article.wordCount == 321)
        #expect(article.imageURLs == ["http://127.0.0.1:8777/phase-4.7/swatch.png", "http://127.0.0.1:8777/phase-4.7/b.png"])
        #expect(article.distillerMilliseconds == 12.5)
    }

    @Test("Without text_content the markup's text counts; an unknown direction is auto")
    func fallsBackToMarkupText() throws {
        let article = try ReaderRules.parse(#"{"1":"T","2":{"1":"<p>One&nbsp;two</p>\n<p>  three &lt;4&gt;</p>"},"9":"sideways"}"#)
        #expect(article.text == "One two three <4>")
        #expect(article.textDirection == "auto")
        #expect(article.imageURLs.isEmpty && article.wordCount == nil)
    }

    @Test("null is no result; anything but a dictionary is malformed")
    func rejectsOtherAnswers() {
        #expect(throws: ReaderError.noResult) { try ReaderRules.parse("null") }
        #expect(throws: ReaderError.malformed("not a dictionary")) { try ReaderRules.parse("[1,2]") }
        #expect(throws: ReaderError.malformed("not JSON")) { try ReaderRules.parse("<html>") }
    }

    @Test("An article has at least the threshold's characters of text, whitespace runs counted once")
    func articleThreshold() {
        let minimum = ReaderMetrics.minimumArticleCharacters
        let enough = ReaderArticle(title: "", contentHTML: "", text: String(repeating: "a", count: minimum))
        let short = ReaderArticle(title: "", contentHTML: "", text: String(repeating: "a", count: minimum - 1) + "   \n\n   ")
        let spaced = ReaderArticle(title: "", contentHTML: "", text: String(repeating: "ab   ", count: minimum / 3))
        #expect(ReaderRules.isArticle(enough))
        #expect(!ReaderRules.isArticle(short))
        #expect(spaced.textLength == minimum / 3 * 3 - 1)
        #expect(!ReaderRules.isArticle(ReaderArticle(title: "Dashboard", contentHTML: "<p>12°</p>", text: "")))
    }

    @Test("The script wraps Chrome's distiller with the options as field numbers")
    func distillerScript() {
        let script = ReaderRules.distillerScript("/* gwt */", url: URL(string: "https://example.com/a?b=1"))
        #expect(script.contains("/* gwt */"))
        #expect(script.contains(#"applyWithOptions({"1":false,"2":0,"3":"https:\/\/example.com\/a?b=1"})"#))
        #expect(script.contains("window.setTimeout = function() {};"))
        #expect(!script.contains("Object.create(window)"), "the window's getters need the window itself")
    }

    @Test("The template's slots fill in one pass; text is escaped, the article's markup is not")
    func fillsTemplate() throws {
        let template = "<html dir=\"{{DIRECTION}}\" data-size=\"{{SIZE}}\" data-appearance=\"{{APPEARANCE}}\"><style>{{STYLE}}</style>"
            + "<title>{{TITLE}}</title><a href=\"{{URL}}\">{{HOST}}</a><main>{{CONTENT}}</main>{{UNKNOWN}}"
        let article = ReaderArticle(title: "Tom & \"Jerry\" <3", contentHTML: "<p>Says {{TITLE}}</p>", text: "")
        let page = ReaderRules.page(template: template, article: article, source: try #require(URL(string: "https://news.example/a?x=1&y=2")),
                                    style: ":root{}", textSize: "large", appearance: "dark")
        #expect(page.contains("<title>Tom &amp; &quot;Jerry&quot; &lt;3</title>"))
        #expect(page.contains("href=\"https://news.example/a?x=1&amp;y=2\">news.example</a>"))
        #expect(page.contains("<main><p>Says {{TITLE}}</p></main>"), "the article is not scanned again")
        #expect(page.contains("data-size=\"large\" data-appearance=\"dark\""))
        #expect(page.contains("<style>:root{}</style>"))
        #expect(page.hasSuffix("{{UNKNOWN}}"))
        let untitled = ReaderRules.page(template: "{{TITLE}}|{{SIZE}}", article: ReaderArticle(title: "", contentHTML: "", text: ""),
                                        source: try #require(URL(string: "https://host.example/")), style: "", textSize: "huge", appearance: "light")
        #expect(untitled == "host.example|medium", "no title: the host; an unknown size: medium")
    }

    @Test("The CSS variables come from the tokens: the card background and label colours per appearance, the type scale")
    func cssVariables() throws {
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        let lightColors = Dictionary(uniqueKeysWithValues: ReaderStyle.colorVariables(for: light).map { ($0.name, $0.value) })
        let darkColors = Dictionary(uniqueKeysWithValues: ReaderStyle.colorVariables(for: dark).map { ($0.name, $0.value) })
        #expect(lightColors["--room-background"] == ReaderStyle.rgba(Palette.cardBackground, light))
        #expect(lightColors["--room-background"] == "rgba(255, 255, 255, 1)")
        #expect(darkColors["--room-background"] == ReaderStyle.rgba(Palette.cardBackground, dark))
        #expect(darkColors["--room-background"] != lightColors["--room-background"])
        #expect(lightColors["--room-text"] == ReaderStyle.rgba(.labelColor, light))
        #expect(Set(lightColors.keys) == ["--room-background", "--room-text", "--room-secondary", "--room-link", "--room-separator"])
        let css = ReaderStyle.css()
        #expect(css.contains("--room-text-size: \(Int(ReaderMetrics.textSizes[1]))px;"))
        for (name, size) in zip(ReaderRules.textSizeNames, ReaderMetrics.textSizes) {
            #expect(css.contains(":root[data-size=\"\(name)\"] { --room-text-size: \(Int(size))px; }"))
        }
        #expect(css.contains("--room-measure: \(Int(ReaderMetrics.measure))em;"))
        #expect(css.contains("--room-line-height: 1.55;"))
        #expect(css.contains(":root[data-appearance=\"dark\"] {\n  --room-background: \(darkColors["--room-background"]!);"))
        #expect(css.contains("@media (prefers-color-scheme: dark)"))
    }
}

@Suite("Reader mode in the context menu")
struct ReaderContextMenuTests {
    @Test("Chrome's Open in Reading Mode becomes Room's reader mode in place; Listen to This Page is dropped")
    func readingModeItems() throws {
        // `performActionForItem` sends through the application object.
        _ = NSApplication.shared
        let items = [
            MenuItem(id: 100, title: "Back"),
            MenuItem(id: ContextMenu.openInReadingModeID, title: "Open in Reading Mode"),
            MenuItem(id: ContextMenu.listenToThisPageID, title: "Listen to This Page"),
            MenuItem(id: 101, title: "Inspect"),
        ]
        var performed: [RoomMenuAction] = []
        var heard: [MenuItem.ID?] = []
        let contextMenu = ContextMenu(model: MenuModel(items: items) { heard.append($0) }, element: ContextMenuElement(location: .zero)) { performed.append($0) }
        #expect(contextMenu.menu.items.map(\.title) == ["Back", "Open in Reader Mode", "Inspect"])
        let reader = try #require(contextMenu.menu.items.firstIndex { $0.title == "Open in Reader Mode" })
        contextMenu.menu.performActionForItem(at: reader)
        #expect(performed == [.readerMode])
        #expect(heard == [nil], "the engine hears cancel")
    }
}
