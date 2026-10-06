import Foundation

/// The installed extensions in a Chrome-family `Preferences` (or `Secure
/// Preferences`, where recent Chrome keeps them): `extensions.settings.<id>`
/// with `manifest.name`, `manifest.version`, `from_webstore`, `state` (1
/// enabled) and `location` (`extensions/browser/extension_prefs.cc`,
/// `mojom::ManifestLocation`). Only Web Store installs can be installed
/// again in Room (4.3b), but every user-installed one is listed; unpacked,
/// component and policy-installed ones are skipped with a reason, as is an
/// entry without a manifest name.
public enum ChromeExtensionsReader {
    public static func read(_ data: Data) throws(ImportError) -> ImportedExtensions {
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data) } catch {
            throw ImportError(.malformed, .chromePreferences, "not JSON")
        }
        guard let object = json as? [String: Any] else {
            throw ImportError(.malformed, .chromePreferences, "not a JSON object")
        }
        guard let settings = (object["extensions"] as? [String: Any])?["settings"] as? [String: Any] else {
            return ImportedExtensions()
        }
        var result = ImportedExtensions()
        for id in settings.keys.sorted() {
            guard let entry = settings[id] as? [String: Any] else { continue }
            let manifest = entry["manifest"] as? [String: Any]
            let name = (manifest?["name"] as? String) ?? ""
            let label = name.isEmpty ? id : name
            switch (entry["location"] as? Int) ?? 1 {
            case 4, 8:
                result.skipped.append(SkippedItem(label, reason: "unpacked (loaded from a folder)"))
                continue
            case 5, 10:
                result.skipped.append(SkippedItem(label, reason: "part of the browser"))
                continue
            case 6, 7, 9:
                result.skipped.append(SkippedItem(label, reason: "installed by policy or another app"))
                continue
            default:
                break
            }
            guard !name.isEmpty else {
                result.skipped.append(SkippedItem(id, reason: "no manifest"))
                continue
            }
            result.extensions.append(ImportedExtension(id: id, name: name, version: (manifest?["version"] as? String) ?? "",
                                                       fromWebStore: (entry["from_webstore"] as? Bool) ?? false,
                                                       enabled: (entry["state"] as? Int).map { $0 == 1 } ?? ((entry["disable_reasons"] as? [Any])?.isEmpty ?? true)))
        }
        return result
    }
}

/// `Local State`'s profiles: `profile.info_cache.<directory>.name`, in
/// `profile.profiles_order` when present, else by directory.
public enum ChromeLocalStateReader {
    public static func profiles(_ data: Data) throws(ImportError) -> [(directory: String, name: String)] {
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data) } catch {
            throw ImportError(.malformed, .chromeLocalState, "not JSON")
        }
        guard let cache = ((json as? [String: Any])?["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else {
            return []
        }
        let order = (((json as? [String: Any])?["profile"] as? [String: Any])?["profiles_order"] as? [String]) ?? []
        let directories = order.filter { cache[$0] != nil } + cache.keys.filter { !order.contains($0) }.sorted()
        return directories.map { directory in
            (directory, ((cache[directory] as? [String: Any])?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? directory)
        }
    }
}
