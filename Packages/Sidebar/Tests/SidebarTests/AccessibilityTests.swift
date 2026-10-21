import Foundation
import Model
import Testing
@testable import Sidebar

/// ROADMAP 5.3 task 1: a row tells VoiceOver its kind and every state it
/// shows (selection, unloaded, changed, audible), not only its title.
@Suite("Row accessibility (5.3a)")
struct EntryAccessibilityTests {
    @Test("Kind first, then the states the row draws, in order")
    func states() {
        let loaded = EntryPageState(isLoaded: true)
        #expect(EntryAccessibility.value(kind: .today, page: loaded, isSelected: false, isChanged: false) == "Today tab")
        #expect(EntryAccessibility.value(kind: .pinned, page: EntryPageState(), isSelected: false, isChanged: false) == "Pinned tab, not loaded")
        #expect(EntryAccessibility.value(kind: .essential, page: EntryPageState(isLoaded: true, isAudible: true), isSelected: true, isChanged: true)
            == "Essential, current, changed from its pinned URL, playing audio")
        #expect(EntryAccessibility.value(kind: .today, page: EntryPageState(isLoaded: true, isLoading: true, isAudible: true, isMuted: true,
                                                                            capture: .camera, isReader: true),
                                         isSelected: false, isChanged: false)
            == "Today tab, loading, muted, using your camera, reader mode")
        #expect(EntryAccessibility.value(kind: .folder, isCollapsed: true, children: 3, page: loaded, isSelected: false, isChanged: false)
            == "Folder, collapsed, 3 items")
    }

    @Test("The hover-only buttons are VoiceOver actions where the row shows them")
    func actions() {
        #expect(EntryAccessibility.actionNames(kind: .today, page: EntryPageState(isLoaded: true), isChanged: false) == ["Close Tab"])
        #expect(EntryAccessibility.actionNames(kind: .pinned, page: EntryPageState(isLoaded: true, isAudible: true), isChanged: true)
            == ["Back to Pinned URL", "Mute Tab"])
        #expect(EntryAccessibility.actionNames(kind: .essential, page: EntryPageState(isLoaded: true, isMuted: true), isChanged: false)
            == ["Unmute Tab"])
    }
}
