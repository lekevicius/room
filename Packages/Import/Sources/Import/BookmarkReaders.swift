import Foundation

// Bookmark readers (Phase 4.3a): Chrome-family JSON, Safari's plist, the
// Netscape HTML file. Pure functions over the file's bytes.

/// Chrome's `Bookmarks` (Chrome, Brave, Edge, Vivaldi, Arc: the format of
/// `components/bookmarks/browser/bookmark_codec.cc`): `roots.bookmark_bar`,
/// `other` and `synced`, each a folder node; nodes have `type` (`url` or
/// `folder`), `name`, `url`, `children`, `date_added` (WebKit microseconds
/// as a decimal string) and `guid`. A node without its `url` or of another
/// type is skipped with a reason; unknown keys are ignored.
public enum ChromeBookmarksReader {
    public static func read(_ data: Data) throws(ImportError) -> ImportedBookmarks {
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data) } catch {
            throw ImportError(.malformed, .chromeBookmarks, "not JSON")
        }
        guard let object = json as? [String: Any], let roots = object["roots"] as? [String: Any] else {
            throw ImportError(.malformed, .chromeBookmarks, "no \"roots\" object")
        }
        guard roots["bookmark_bar"] != nil || roots["other"] != nil else {
            throw ImportError(.malformed, .chromeBookmarks, "no \"bookmark_bar\" or \"other\" root")
        }
        var skipped: [SkippedItem] = []
        func children(of root: String) -> [ImportedNode] {
            guard let node = roots[root] as? [String: Any] else { return [] }
            return nodes(node["children"], path: (node["name"] as? String) ?? root, skipped: &skipped)
        }
        let bar = children(of: "bookmark_bar")
        let other = children(of: "other")
        let mobile = children(of: "synced")
        return ImportedBookmarks(bar: bar, other: other, mobile: mobile, skipped: skipped)
    }

    private static func nodes(_ value: Any?, path: String, skipped: inout [SkippedItem]) -> [ImportedNode] {
        guard let list = value as? [[String: Any]] else { return [] }
        var result: [ImportedNode] = []
        for node in list {
            let name = (node["name"] as? String) ?? ""
            let label = path + " ▸ " + (name.isEmpty ? "(untitled)" : name)
            switch node["type"] as? String {
            case "url":
                guard let url = node["url"] as? String, !url.isEmpty else {
                    skipped.append(SkippedItem(label, reason: "no URL"))
                    continue
                }
                result.append(.link(ImportedLink(url: url, title: name, dateAdded: ImportTime.webKit(node["date_added"] as? String),
                                                 guid: node["guid"] as? String)))
            case "folder":
                result.append(.folder(ImportedFolder(title: name, children: nodes(node["children"], path: label, skipped: &skipped),
                                                     dateAdded: ImportTime.webKit(node["date_added"] as? String),
                                                     guid: node["guid"] as? String)))
            default:
                skipped.append(SkippedItem(label, reason: "unknown node type"))
            }
        }
        return result
    }
}

/// Safari's `Bookmarks.plist` (binary or XML): a root `WebBookmarkTypeList`
/// whose `Children` are lists (`BookmarksBar`, `BookmarksMenu`,
/// `com.apple.ReadingList`, the user's top-level folders), leaves
/// (`URLString`, `URIDictionary.title`) and proxies (History, not a
/// bookmark: ignored). The bar becomes `bar`; the menu's children, the
/// Reading List (as a folder "Reading List") and the other top-level items
/// become `other`.
public enum SafariBookmarksReader {
    public static let readingListTitle = "Reading List"

    public static func read(_ data: Data) throws(ImportError) -> ImportedBookmarks {
        let plist: Any
        do { plist = try PropertyListSerialization.propertyList(from: data, format: nil) } catch {
            throw ImportError(.malformed, .safariBookmarks, "not a property list")
        }
        guard let root = plist as? [String: Any], root["WebBookmarkType"] as? String == "WebBookmarkTypeList",
              let children = root["Children"] as? [[String: Any]] else {
            throw ImportError(.malformed, .safariBookmarks, "the root is not a WebBookmarkTypeList with Children")
        }
        var skipped: [SkippedItem] = []
        var result = ImportedBookmarks()
        for child in children {
            let title = (child["Title"] as? String) ?? ""
            switch (child["WebBookmarkType"] as? String, title) {
            case ("WebBookmarkTypeList", "BookmarksBar"):
                result.bar += nodes(child["Children"], path: "Favourites", skipped: &skipped)
            case ("WebBookmarkTypeList", "BookmarksMenu"):
                result.other += nodes(child["Children"], path: "Bookmarks Menu", skipped: &skipped)
            case ("WebBookmarkTypeList", "com.apple.ReadingList"):
                result.other.append(.folder(ImportedFolder(title: readingListTitle,
                                                           children: nodes(child["Children"], path: readingListTitle, skipped: &skipped),
                                                           guid: child["WebBookmarkUUID"] as? String)))
            case ("WebBookmarkTypeProxy", _):
                continue
            default:
                result.other += nodes([child], path: "Bookmarks", skipped: &skipped)
            }
        }
        result.skipped = skipped
        return result
    }

    private static func nodes(_ value: Any?, path: String, skipped: inout [SkippedItem]) -> [ImportedNode] {
        guard let list = value as? [[String: Any]] else { return [] }
        var result: [ImportedNode] = []
        for node in list {
            switch node["WebBookmarkType"] as? String {
            case "WebBookmarkTypeLeaf":
                let title = ((node["URIDictionary"] as? [String: Any])?["title"] as? String) ?? ""
                guard let url = node["URLString"] as? String, !url.isEmpty else {
                    skipped.append(SkippedItem(path + " ▸ " + (title.isEmpty ? "(untitled)" : title), reason: "no URL"))
                    continue
                }
                let added = (node["ReadingList"] as? [String: Any])?["DateAdded"] as? Date
                result.append(.link(ImportedLink(url: url, title: title, dateAdded: added, guid: node["WebBookmarkUUID"] as? String)))
            case "WebBookmarkTypeList":
                let title = (node["Title"] as? String) ?? ""
                result.append(.folder(ImportedFolder(title: title, children: nodes(node["Children"], path: path + " ▸ " + title, skipped: &skipped),
                                                     guid: node["WebBookmarkUUID"] as? String)))
            case "WebBookmarkTypeProxy":
                continue
            default:
                skipped.append(SkippedItem(path + " ▸ " + ((node["Title"] as? String) ?? "(untitled)"), reason: "unknown bookmark type"))
            }
        }
        return result
    }
}

/// The Netscape bookmark file every browser exports (Firefox's
/// "Export Bookmarks to HTML", Chrome's, Safari's): `<DL>` lists of
/// `<DT><H3>` folders and `<DT><A HREF ADD_DATE>` links. The folder with
/// `PERSONAL_TOOLBAR_FOLDER` becomes `bar`, everything else `other`. Read
/// tag by tag, like Chromium's line-based parser but tolerant of tags on one
/// line; `<DD>` descriptions, `<HR>` and unknown tags are ignored.
public enum NetscapeBookmarksReader {
    public static func read(_ data: Data) throws(ImportError) -> ImportedBookmarks {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError(.malformed, .netscapeBookmarks, "not text")
        }
        let upper = text.uppercased()
        guard upper.contains("NETSCAPE-BOOKMARK-FILE") || upper.contains("<DL") else {
            throw ImportError(.malformed, .netscapeBookmarks, "no bookmark list (<DL>)")
        }
        // A stack of open folders; the bottom one is the file itself.
        struct Open { var title: String; var isBar: Bool; var children: [ImportedNode]; var added: Date? }
        var stack = [Open(title: "", isBar: false, children: [], added: nil)]
        var pendingFolder: Open?
        var bar: [ImportedNode] = []
        var skipped: [SkippedItem] = []
        var index = text.startIndex
        while let open = text.range(of: "<", range: index..<text.endIndex) {
            guard let close = text.range(of: ">", range: open.upperBound..<text.endIndex) else { break }
            let tag = String(text[open.upperBound..<close.lowerBound])
            let name = tag.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map { $0.uppercased() } ?? ""
            index = close.upperBound
            // A folder named without a list of its own is an empty folder.
            if name == "H3" || name == "A", let folder = pendingFolder {
                stack[stack.count - 1].children.append(.folder(ImportedFolder(title: folder.title, children: [], dateAdded: folder.added)))
                pendingFolder = nil
            }
            switch name {
            case "H3":
                let end = text.range(of: "</H3>", options: .caseInsensitive, range: index..<text.endIndex)
                let title = decode(String(text[index..<(end?.lowerBound ?? index)]))
                let attributes = attributesOf(tag)
                pendingFolder = Open(title: title, isBar: attributes["PERSONAL_TOOLBAR_FOLDER"]?.lowercased() == "true",
                                     children: [], added: ImportTime.netscape(attributes["ADD_DATE"]))
                index = end?.upperBound ?? index
            case "DL":
                // The list of the folder just named, or the file's top list.
                if let folder = pendingFolder {
                    stack.append(folder)
                    pendingFolder = nil
                }
            case "/DL":
                guard stack.count > 1, let folder = stack.popLast() else { continue }
                if folder.isBar, bar.isEmpty, stack.count == 1 {
                    bar = folder.children
                } else {
                    stack[stack.count - 1].children.append(.folder(ImportedFolder(title: folder.title, children: folder.children,
                                                                                  dateAdded: folder.added)))
                }
            case "A":
                let end = text.range(of: "</A>", options: .caseInsensitive, range: index..<text.endIndex)
                let title = decode(String(text[index..<(end?.lowerBound ?? index)])).trimmingCharacters(in: .whitespacesAndNewlines)
                index = end?.upperBound ?? index
                let attributes = attributesOf(tag)
                guard let href = attributes["HREF"].map(decode), !href.isEmpty else {
                    skipped.append(SkippedItem(title.isEmpty ? "(untitled)" : title, reason: "no URL"))
                    continue
                }
                stack[stack.count - 1].children.append(.link(ImportedLink(url: href, title: title,
                                                                          dateAdded: ImportTime.netscape(attributes["ADD_DATE"]))))
            default:
                continue
            }
        }
        // An unclosed list keeps what it had.
        while stack.count > 1, let folder = stack.popLast() {
            stack[stack.count - 1].children.append(.folder(ImportedFolder(title: folder.title, children: folder.children, dateAdded: folder.added)))
        }
        return ImportedBookmarks(bar: bar, other: stack[0].children, skipped: skipped)
    }

    /// `KEY="value"` pairs of a tag, keys upper-cased.
    static func attributesOf(_ tag: String) -> [String: String] {
        var result: [String: String] = [:]
        let scanner = Scanner(string: tag)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        _ = scanner.scanUpToCharacters(from: .whitespacesAndNewlines)
        while !scanner.isAtEnd {
            guard let key = scanner.scanUpToString("=") else { break }
            _ = scanner.scanString("=")
            let value: String
            if scanner.scanString("\"") != nil {
                value = scanner.scanUpToString("\"") ?? ""
                _ = scanner.scanString("\"")
            } else {
                value = scanner.scanUpToCharacters(from: .whitespacesAndNewlines) ?? ""
            }
            result[key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()] = value
        }
        return result
    }

    /// HTML entities: the five named ones and numeric references.
    static func decode(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        var index = string.startIndex
        while let amp = string.range(of: "&", range: index..<string.endIndex) {
            result += string[index..<amp.lowerBound]
            guard let semi = string.range(of: ";", range: amp.upperBound..<string.endIndex),
                  string.distance(from: amp.upperBound, to: semi.lowerBound) <= 10 else {
                result += "&"
                index = amp.upperBound
                continue
            }
            let entity = string[amp.upperBound..<semi.lowerBound]
            let replacement: String? = switch entity {
            case "amp": "&"
            case "lt": "<"
            case "gt": ">"
            case "quot": "\""
            case "apos", "#39": "'"
            default:
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if entity.hasPrefix("#") {
                    UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    nil
                }
            }
            if let replacement {
                result += replacement
                index = semi.upperBound
            } else {
                result += "&"
                index = amp.upperBound
            }
        }
        result += string[index...]
        return result
    }
}
