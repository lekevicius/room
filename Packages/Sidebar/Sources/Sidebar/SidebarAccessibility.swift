import AppKit
import Model

/// What VoiceOver says for a sidebar row or an Essential (5.3a, ROADMAP 5.3
/// task 1: kind, state, changed, audible): the title is the label; the value
/// lists the kind and every state the row shows with pixels (the selection
/// pill, the dimmed unloaded icon, the changed dot, the audio glyph, the
/// capture and reader glyphs), in the order the eye meets them.
enum EntryAccessibility {
    static func value(kind: EntryKind, isCollapsed: Bool = false, children: Int? = nil, page: EntryPageState,
                      isSelected: Bool, isChanged: Bool, hasUnread: Bool = false) -> String {
        var parts: [String]
        switch kind {
        case .essential: parts = ["Essential"]
        case .pinned: parts = ["Pinned tab"]
        case .today: parts = ["Today tab"]
        case .folder:
            parts = ["Folder", isCollapsed ? "collapsed" : "expanded"]
            if let children { parts.append(children == 1 ? "1 item" : "\(children) items") }
            return parts.joined(separator: ", ")
        }
        if isSelected { parts.append("current") }
        if page.isLoading {
            parts.append("loading")
        } else if !page.isLoaded {
            parts.append("not loaded")
        }
        if isChanged { parts.append("changed from its pinned URL") }
        if hasUnread { parts.append("unread") }
        if page.isMuted {
            parts.append("muted")
        } else if page.isAudible {
            parts.append("playing audio")
        }
        switch page.capture {
        case .screen?: parts.append("sharing your screen")
        case .camera?: parts.append("using your camera")
        case .microphone?: parts.append("using your microphone")
        case nil: break
        }
        if page.isReader { parts.append("reader mode") }
        return parts.joined(separator: ", ")
    }

    /// The row's buttons as VoiceOver actions (the rotor's Actions), so a row's
    /// hover-only buttons are reachable without the pointer.
    static func actionNames(kind: EntryKind, page: EntryPageState, isChanged: Bool) -> [String] {
        var names: [String] = []
        if kind == .today { names.append("Close Tab") }
        if isChanged { names.append("Back to Pinned URL") }
        if page.isMuted {
            names.append("Unmute Tab")
        } else if page.isAudible {
            names.append("Mute Tab")
        }
        return names
    }
}
