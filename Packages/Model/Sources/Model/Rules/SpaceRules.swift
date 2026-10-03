import Foundation

/// Spaces and profiles (spec §B), as pure functions.
public enum SpaceRules {
    /// The space `offset` steps from `current` in `spaces` (⌥⌘← / ⌥⌘→),
    /// wrapping around the ends; `nil` with fewer than two spaces.
    public static func adjacent(to current: UUID, offset: Int, in spaces: [Space]) -> Space? {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == current }) else { return nil }
        let count = spaces.count
        return spaces[((index + offset) % count + count) % count]
    }

    /// ⌃1…⌃9 pick the Nth space, ⌃0 the tenth (spec §B); `nil` past the end.
    public static func space(forDigit digit: Int, in spaces: [Space]) -> Space? {
        guard (0...9).contains(digit) else { return nil }
        let index = digit == 0 ? 9 : digit - 1
        return spaces.indices.contains(index) ? spaces[index] : nil
    }

    /// The name a new space gets when the form is left empty: "Space",
    /// then "Space 2", "Space 3"… (Zen names the first space "Space").
    public static func defaultName(existing: [String]) -> String {
        uniqueName("Space", existing: existing)
    }

    /// `name`, or `name 2`, `name 3`… if a name in `existing` already
    /// equals it ignoring case (profiles: one engine directory per name).
    public static func uniqueName(_ name: String, existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var number = 2
        while taken.contains("\(name) \(number)".lowercased()) { number += 1 }
        return "\(name) \(number)"
    }
}

/// Cookies belong to a profile (spec §B "Containers").
public enum ProfileRules {
    /// A page made in `pageProfile`'s engine profile cannot keep showing
    /// `entry` once the entry belongs to another profile: it loads again
    /// in the new one ("Logins and cookies won't carry over").
    public static func needsNewPage(pageProfile: UUID, entry: Entry) -> Bool {
        pageProfile != entry.profileID
    }

    /// The entries a move into `space` takes to another profile (the move
    /// warns once; essentials never move between spaces, they belong to the
    /// profile). Folders count through their descendants in `entries`.
    public static func crossingEntries(_ moving: [Entry], into space: Space, entries: [UUID: Entry]) -> [Entry] {
        var result: [Entry] = []
        func visit(_ entry: Entry) {
            if entry.kind == .folder {
                for child in entries.values where child.folderID == entry.id { visit(child) }
            } else if entry.kind != .essential, entry.profileID != space.profileID {
                result.append(entry)
            }
        }
        moving.forEach(visit)
        return result
    }
}

/// The two-finger swipe over the sidebar (spec §B; Zen's swipe actions):
/// the lists follow the fingers, a release past a quarter of the width (or
/// a fling) switches, the ends rubber-band, and swiping past the last space
/// reveals the new-space form.
public enum SwipeRules {
    /// Fraction of the sidebar width a release must pass (Zen 25%).
    public static let threshold = 0.25
    /// How much a fling's velocity adds: progress + velocity × this (Zen 0.5),
    /// velocity in sidebar widths per second.
    public static let velocityWeight = 0.5
    /// The farthest the lists stretch past an end, in sidebar widths.
    public static let rubberBandLimit = 0.15

    public enum Outcome: Equatable, Sendable {
        /// Back to the current space.
        case stay
        /// To the space `offset` steps away (+1 = the next, to the right).
        case switchTo(offset: Int)
        /// Past the last space: the new-space form.
        case newSpace
    }

    /// Where a released swipe goes. `progress`: how far the lists moved, in
    /// sidebar widths (+ = towards the next space); `velocity`: widths per
    /// second at release, same sign; `index` / `count`: the current space.
    public static func outcome(progress: Double, velocity: Double, index: Int, count: Int) -> Outcome {
        let projected = progress + velocity * velocityWeight
        guard abs(projected) >= threshold else { return .stay }
        if projected > 0 {
            return index + 1 < count ? .switchTo(offset: 1) : .newSpace
        }
        return index > 0 ? .switchTo(offset: -1) : .stay
    }

    /// The displayed offset (sidebar widths) for a finger offset `progress`:
    /// one-to-one towards a neighbour, damped past the first space (rubber
    /// band, approaching `rubberBandLimit`); past the last space it follows
    /// the fingers, the form sliding in.
    public static func displayedProgress(_ progress: Double, index: Int, count: Int) -> Double {
        let clamped = min(max(progress, -1), 1)
        guard clamped < 0, index == 0 else { return clamped }
        // An end: x → limit × (1 − 1 / (1 + x / limit)), smooth and bounded.
        let stretch = -clamped
        return -rubberBandLimit * (1 - 1 / (1 + stretch / rubberBandLimit))
    }
}
