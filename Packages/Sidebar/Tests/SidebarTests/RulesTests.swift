import Foundation
import Model
import Testing
@testable import Sidebar

@Suite("Click semantics (spec §A.2)")
struct ClickRulesTests {
    typealias Outcome = ClickRules.Outcome

    @Test("Click: select; on the selected entry, reset only when changed", arguments: [EntryKind.essential, .pinned])
    func primaryPermanent(kind: EntryKind) {
        #expect(ClickRules.outcome(.primary, kind: kind, isSelected: false, isChanged: false, isLoaded: false) == .select)
        #expect(ClickRules.outcome(.primary, kind: kind, isSelected: false, isChanged: true, isLoaded: true) == .select)
        #expect(ClickRules.outcome(.primary, kind: kind, isSelected: true, isChanged: true, isLoaded: true) == .reset)
        #expect(ClickRules.outcome(.primary, kind: kind, isSelected: true, isChanged: false, isLoaded: true) == .none)
    }

    @Test("Click on a selected Today tab does nothing")
    func primaryToday() {
        #expect(ClickRules.outcome(.primary, kind: .today, isSelected: false, isChanged: false, isLoaded: true) == .select)
        #expect(ClickRules.outcome(.primary, kind: .today, isSelected: true, isChanged: false, isLoaded: true) == .none)
    }

    @Test("⌘-click on the selected changed entry separates")
    func commandClick() {
        #expect(ClickRules.outcome(.command, kind: .pinned, isSelected: true, isChanged: true, isLoaded: true) == .separate)
        #expect(ClickRules.outcome(.command, kind: .essential, isSelected: true, isChanged: true, isLoaded: true) == .separate)
    }

    @Test("Otherwise ⌘-click toggles the multi-selection and ⇧-click extends it (§A.9)")
    func multiSelectClicks() {
        #expect(ClickRules.outcome(.command, kind: .today, isSelected: true, isChanged: false, isLoaded: true) == .toggleSelection)
        #expect(ClickRules.outcome(.command, kind: .pinned, isSelected: false, isChanged: true, isLoaded: true) == .toggleSelection)
        #expect(ClickRules.outcome(.command, kind: .essential, isSelected: true, isChanged: false, isLoaded: true) == .toggleSelection)
        #expect(ClickRules.outcome(.shift, kind: .today, isSelected: false, isChanged: false, isLoaded: false) == .extendSelection)
        #expect(ClickRules.outcome(.shift, kind: .pinned, isSelected: true, isChanged: true, isLoaded: true) == .extendSelection)
    }

    @Test("Middle-click: unload if loaded; an unloaded pinned entry is removed, an essential never; Today closes")
    func middleClick() {
        #expect(ClickRules.outcome(.middle, kind: .essential, isSelected: false, isChanged: false, isLoaded: true) == .unload)
        #expect(ClickRules.outcome(.middle, kind: .essential, isSelected: false, isChanged: false, isLoaded: false) == .none)
        #expect(ClickRules.outcome(.middle, kind: .pinned, isSelected: true, isChanged: false, isLoaded: true) == .unload)
        #expect(ClickRules.outcome(.middle, kind: .pinned, isSelected: false, isChanged: false, isLoaded: false) == .remove)
        #expect(ClickRules.outcome(.middle, kind: .today, isSelected: false, isChanged: false, isLoaded: false) == .close)
    }
}

@Suite("Row labels (spec §I.3)")
struct EntryLabelTests {
    let profile = UUID(), space = UUID()

    @Test("A changed pinned entry keeps its stored title; a Today tab shows the live title")
    func stableTitle() {
        var pinned = Entry(kind: .pinned, spaceID: space, profileID: profile, storedURL: "https://mail.example.com",
                           storedTitle: "Mail", liveURL: "https://mail.example.com/thread/1", liveTitle: "Re: lunch")
        #expect(EntryLabel.title(pinned) == "Mail")
        #expect(EntryLabel.currentTitle(pinned) == "Re: lunch")
        pinned.customLabel = "Work mail"
        #expect(EntryLabel.title(pinned) == "Work mail")
        let today = Entry(kind: .today, spaceID: space, profileID: profile, liveURL: "https://news.example.com", liveTitle: "News")
        #expect(EntryLabel.title(today) == "News")
    }

    @Test("Without a title the label is the domain (no www.)")
    func domainFallback() {
        let entry = Entry(kind: .today, spaceID: space, profileID: profile, liveURL: "https://www.example.org/a?b")
        #expect(EntryLabel.title(entry) == "example.org")
    }

    @Test("Unread counters never show", arguments: [("(3) Inbox", "Inbox"), ("(12)Chat", "Chat"), ("(a) b", "(a) b"), ("Inbox (3)", "Inbox (3)")])
    func counters(raw: String, shown: String) {
        #expect(EntryLabel.withoutCounter(raw) == shown)
    }

    @Test("Markdown link escapes brackets in the title")
    func markdown() {
        #expect(EntryLabel.markdown(title: "a [b] c", url: "https://x.example") == "[a \\[b\\] c](https://x.example)")
    }
}

@Suite("Essentials grid layout (spec §I.2)")
struct EssentialsLayoutTests {
    @Test("Tiles fill the width; columns as fit, capped by count and the maximum")
    func columns() {
        #expect(EssentialsLayout.columns(count: 0, width: 228) == 0)
        #expect(EssentialsLayout.columns(count: 2, width: 228) == 2)
        #expect(EssentialsLayout.columns(count: 12, width: 228) == 4)
        #expect(EssentialsLayout.columns(count: 12, width: 488) == 6)
        let frames = EssentialsLayout.frames(count: 5, width: 228)
        #expect(frames.count == 5)
        #expect(frames[3].minY > frames[2].minY, "fourth tile starts the second row")
        #expect(abs(frames[2].maxX - 228) <= 1 && abs(frames[4].maxX - 228) <= 1, "both rows fill the width")
    }

    @Test("Rows are balanced: never shorter than another by more than one (2.2a review)", arguments: [
        (5, 228.0, [3, 2]), (7, 228.0, [4, 3]), (9, 228.0, [3, 3, 3]), (6, 228.0, [3, 3]), (4, 228.0, [4]),
        (12, 228.0, [4, 4, 4]), (7, 488.0, [4, 3]), (12, 488.0, [6, 6]), (1, 228.0, [1]), (0, 228.0, []),
    ])
    func balancedRows(count: Int, width: Double, rows: [Int]) {
        #expect(EssentialsLayout.rowCounts(count: count, width: width) == rows)
    }
}
