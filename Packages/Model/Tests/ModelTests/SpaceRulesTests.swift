import Foundation
import Testing
@testable import Model

@Suite("Theme palette (spec §B)")
struct ThemePaletteTests {
    @Test("Hex colours survive the round trip through HSL")
    func roundTrip() {
        for hex in ["#FF0000", "#00FF00", "#0000FF", "#808080", "#1E90FF", "#FFFFFF", "#000000", "#C0FFEE"] {
            #expect(HSLColor(hex: hex)?.hex == hex)
        }
        #expect(HSLColor(hex: "c0ffee")?.hex == "#C0FFEE")
        #expect(HSLColor(hex: "#12345") == nil)
        #expect(HSLColor(hex: "blue") == nil)
    }

    @Test("Each algorithm derives its hues from the base colour", arguments: [
        (ThemeAlgorithm.complementary, ["#FF0000", "#00FFFF"]),
        (.split, ["#FF0000", "#00FF80", "#0080FF"]),
        (.analogous, ["#FF0000", "#FF0080", "#FF8000"]),
        (.triadic, ["#FF0000", "#00FF00", "#0000FF"]),
        (.floating, ["#FF0000"]),
    ])
    func derived(algorithm: ThemeAlgorithm, expected: [String]) {
        #expect(ThemePalette.colors(["#FF0000"], algorithm: algorithm) == expected)
    }

    @Test("A colour the user chose wins over the derived one; extra wells follow; three at most")
    func userWells() {
        #expect(ThemePalette.colors(["#FF0000", "#123456"], algorithm: .triadic) == ["#FF0000", "#123456", "#0000FF"])
        #expect(ThemePalette.colors(["#FF0000", "#123456", "#ABCDEF"], algorithm: .complementary) == ["#FF0000", "#123456", "#ABCDEF"])
        #expect(ThemePalette.colors(["#FF0000", "#123456", "#ABCDEF"], algorithm: .floating) == ["#FF0000", "#123456", "#ABCDEF"])
        #expect(ThemePalette.colors(["#FF0000", "#123456", "#ABCDEF", "#000000"], algorithm: .floating).count == 3)
    }

    @Test("No colours (or none parseable) is the neutral window")
    func empty() {
        #expect(ThemePalette.colors([], algorithm: .triadic).isEmpty)
        #expect(ThemePalette.colors(["nope"], algorithm: .split).isEmpty)
    }

    @Test("Dark variants are no lighter than the cap; hue and saturation stay")
    func dark() throws {
        let dark = ThemePalette.darkVariant(["#FFC0CB", "#202020"])
        let pink = try #require(HSLColor(hex: dark[0]))
        let original = try #require(HSLColor(hex: "#FFC0CB"))
        #expect(pink.lightness <= ThemePalette.darkMaxLightness + 0.005)
        #expect(abs(pink.hue - original.hue) < 0.01)
        #expect(dark[1] == "#202020")
    }

    @Test("Opacity maps linearly into the tint range")
    func alpha() {
        #expect(ThemePalette.tintAlpha(opacity: 0, range: 0.1...0.25) == 0.1)
        #expect(ThemePalette.tintAlpha(opacity: 1, range: 0.1...0.25) == 0.25)
        #expect(abs(ThemePalette.tintAlpha(opacity: 0.5, range: 0.1...0.25) - 0.175) < 1e-9)
        #expect(ThemePalette.tintAlpha(opacity: 7, range: 0.1...0.25) == 0.25)
    }
}

@Suite("Space switching and profiles (spec §B)")
struct SpaceRulesTests {
    private let profile = UUID()
    private func spaces(_ count: Int) -> [Space] {
        (0..<count).map { Space(name: "S\($0)", profileID: profile, position: $0) }
    }

    @Test("⌥⌘←/→ step through spaces and wrap around")
    func adjacent() {
        let list = spaces(3)
        #expect(SpaceRules.adjacent(to: list[2].id, offset: 1, in: list)?.id == list[0].id)
        #expect(SpaceRules.adjacent(to: list[0].id, offset: -1, in: list)?.id == list[2].id)
        #expect(SpaceRules.adjacent(to: list[1].id, offset: 1, in: list)?.id == list[2].id)
        #expect(SpaceRules.adjacent(to: list[0].id, offset: 1, in: spaces(1)) == nil)
    }

    @Test("⌃1…⌃9 pick the Nth space, ⌃0 the tenth")
    func digits() {
        let list = spaces(10)
        #expect(SpaceRules.space(forDigit: 1, in: list)?.id == list[0].id)
        #expect(SpaceRules.space(forDigit: 9, in: list)?.id == list[8].id)
        #expect(SpaceRules.space(forDigit: 0, in: list)?.id == list[9].id)
        #expect(SpaceRules.space(forDigit: 4, in: spaces(3)) == nil)
        #expect(SpaceRules.space(forDigit: 0, in: spaces(9)) == nil)
    }

    @Test("Names: the default and unique profile names ignore case")
    func names() {
        #expect(SpaceRules.defaultName(existing: []) == "Space")
        #expect(SpaceRules.defaultName(existing: ["space", "Space 2"]) == "Space 3")
        #expect(SpaceRules.uniqueName("Work", existing: ["Default"]) == "Work")
        #expect(SpaceRules.uniqueName("work", existing: ["Default", "Work"]) == "work 2")
    }

    @Test("A page stays with its entry only inside one profile")
    func newPage() {
        let other = UUID()
        let entry = Entry(kind: .today, spaceID: UUID(), profileID: profile)
        #expect(!ProfileRules.needsNewPage(pageProfile: profile, entry: entry))
        #expect(ProfileRules.needsNewPage(pageProfile: other, entry: entry))
    }

    @Test("Moving into another profile's space crosses with every tab, folders through their children; essentials never")
    func crossing() {
        let other = UUID()
        let home = Space(name: "Home", profileID: profile, position: 0)
        let work = Space(name: "Work", profileID: other, position: 1)
        let folder = Entry(kind: .folder, spaceID: home.id, profileID: profile)
        let child = Entry(kind: .pinned, spaceID: home.id, profileID: profile, folderID: folder.id, storedURL: "https://a.example")
        let tab = Entry(kind: .today, spaceID: home.id, profileID: profile, liveURL: "https://b.example")
        let essential = Entry(kind: .essential, spaceID: nil, profileID: profile, storedURL: "https://c.example")
        let all = Dictionary(uniqueKeysWithValues: [folder, child, tab, essential].map { ($0.id, $0) })
        #expect(Set(ProfileRules.crossingEntries([folder, tab, essential], into: work, entries: all).map(\.id)) == [child.id, tab.id])
        #expect(ProfileRules.crossingEntries([folder, tab], into: home, entries: all).isEmpty)
    }
}

@Suite("Space swipe (spec §B)")
struct SwipeRulesTests {
    @Test("A release past a quarter of the width switches; less stays")
    func threshold() {
        #expect(SwipeRules.outcome(progress: 0.3, velocity: 0, index: 0, count: 3) == .switchTo(offset: 1))
        #expect(SwipeRules.outcome(progress: -0.3, velocity: 0, index: 1, count: 3) == .switchTo(offset: -1))
        #expect(SwipeRules.outcome(progress: 0.2, velocity: 0, index: 0, count: 3) == .stay)
    }

    @Test("A fling switches below the threshold; a fling against the drag cancels it")
    func velocity() {
        #expect(SwipeRules.outcome(progress: 0.1, velocity: 0.4, index: 0, count: 3) == .switchTo(offset: 1))
        #expect(SwipeRules.outcome(progress: 0.3, velocity: -0.4, index: 0, count: 3) == .stay)
    }

    @Test("Past the last space is the new-space form; before the first stays")
    func ends() {
        #expect(SwipeRules.outcome(progress: 0.5, velocity: 0, index: 2, count: 3) == .newSpace)
        #expect(SwipeRules.outcome(progress: -0.5, velocity: 0, index: 0, count: 3) == .stay)
        #expect(SwipeRules.outcome(progress: 0.5, velocity: 0, index: 0, count: 1) == .newSpace)
    }

    @Test("Before the first space the lists rubber-band, bounded; elsewhere they follow the fingers")
    func rubberBand() {
        #expect(SwipeRules.displayedProgress(0.4, index: 0, count: 3) == 0.4)
        #expect(SwipeRules.displayedProgress(-0.4, index: 1, count: 3) == -0.4)
        let small = SwipeRules.displayedProgress(-0.05, index: 0, count: 3)
        let large = SwipeRules.displayedProgress(-1, index: 0, count: 3)
        #expect(small < 0 && small > -0.05)
        #expect(large > -SwipeRules.rubberBandLimit && large < small)
    }
}

@Suite("Extension pages open in a space of the extension's profile (B-67, 4.5)")
struct ExtensionPageSpaceTests {
    let personal = UUID()
    let work = UUID()
    let spare = UUID()
    let spaces: [Space]

    init() {
        spaces = [Space(name: "Home", profileID: personal, position: 0),
                  Space(name: "Office", profileID: work, position: 2),
                  Space(name: "Clients", profileID: work, position: 1)]
    }

    @Test("The shown space when it is the extension's profile's")
    func shownSpace() {
        let shown = spaces[1].id
        #expect(ExtensionPageSpace.choose(profile: work, shownSpace: shown, spaces: spaces) == .existing(shown))
    }

    @Test("Another profile's space shown: the extension's profile's first space in the footer's order")
    func firstSpaceOfTheProfile() {
        let clients = spaces[2].id
        #expect(ExtensionPageSpace.choose(profile: work, shownSpace: spaces[0].id, spaces: spaces) == .existing(clients))
        #expect(ExtensionPageSpace.choose(profile: work, shownSpace: nil, spaces: spaces) == .existing(clients))
    }

    @Test("A profile without spaces gets a new \"Extensions\" space (a unique name)")
    func newSpace() {
        #expect(ExtensionPageSpace.choose(profile: spare, shownSpace: spaces[0].id, spaces: spaces) == .create(name: "Extensions"))
        let taken = spaces + [Space(name: "Extensions", profileID: personal, position: 3)]
        #expect(ExtensionPageSpace.choose(profile: spare, shownSpace: nil, spaces: taken) == .create(name: "Extensions 2"))
    }
}
