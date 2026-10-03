import AppKit
import Engine
import UniformTypeIdentifiers

/// `<input type=file>` and the save picker (ROADMAP 2.6 task 2): the system
/// open or save panel as a sheet on the window, filtered by the input's
/// `accept` attribute.
public enum FileChooser {
    /// The panel's file types for an `accept` list (MIME types, `type/*`
    /// wildcards, `.ext`). Empty means any file: also when nothing in the
    /// list is known, so an odd `accept` never makes every file unpickable.
    public static func contentTypes(accept: [String]) -> [UTType] {
        var types: [UTType] = []
        for raw in accept {
            let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !value.isEmpty else { continue }
            let type: UTType?
            if value.hasPrefix(".") {
                type = UTType(filenameExtension: String(value.dropFirst()))
            } else if value.hasSuffix("/*") {
                type = switch value {
                case "image/*": .image
                case "video/*": .movie
                case "audio/*": .audio
                case "text/*": .text
                default: nil
                }
            } else {
                type = UTType(mimeType: value)
            }
            // A MIME type the system does not know becomes a dynamic type no file conforms to.
            if let type, !type.isDynamic, !types.contains(type) { types.append(type) }
        }
        return types
    }

    /// Runs the panel for `request` as a sheet on `window`; `completion(nil)` when cancelled.
    public static func run(_ request: FileChooserRequest, in window: NSWindow, completion: @escaping ([URL]?) -> Void) {
        let types = contentTypes(accept: request.acceptTypes)
        if request.mode == .save {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = request.defaultPath?.lastPathComponent ?? ""
            if let directory = request.defaultPath?.deletingLastPathComponent(), request.defaultPath?.pathComponents.count ?? 0 > 1 {
                panel.directoryURL = directory
            }
            if !types.isEmpty { panel.allowedContentTypes = types }
            if let title = request.title, !title.isEmpty { panel.message = title }
            panel.beginSheetModal(for: window) { completion($0 == .OK ? panel.url.map { [$0] } : nil) }
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = request.mode == .openMultiple
        panel.canChooseDirectories = request.mode == .openFolder
        panel.canChooseFiles = request.mode != .openFolder
        panel.resolvesAliases = true
        if !types.isEmpty, request.mode != .openFolder { panel.allowedContentTypes = types }
        if let title = request.title, !title.isEmpty { panel.message = title }
        if let path = request.defaultPath { panel.directoryURL = path.hasDirectoryPath ? path : path.deletingLastPathComponent() }
        panel.beginSheetModal(for: window) { completion($0 == .OK ? panel.urls : nil) }
    }
}
