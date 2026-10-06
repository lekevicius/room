import Model

/// The one-time move of 4.4b (B-22): until then the engine kept a profile
/// at `<root>/Room Profile <name>`, so a rename would have lost its cookies;
/// from 4.4b the directory is keyed by the profile's id. At launch, before
/// the engine opens any profile, every profile whose legacy directory exists
/// and whose id directory does not gets its directory moved. Pure: the app
/// lists the root and performs the moves.
public enum EngineProfileDirectories {
    public struct Move: Equatable, Sendable {
        public let from: String
        public let to: String
    }

    /// The moves for `profiles` given the directory names in the engine's
    /// root. A legacy directory is claimed once (the first profile in order
    /// wins if two names map to one directory); nothing moves onto an
    /// existing directory.
    public static func moves(profiles: [Model.Profile], existing: Set<String>, prefix: String) -> [Move] {
        var claimed = Set<String>()
        var moves: [Move] = []
        for profile in profiles {
            let from = prefix + TabController.legacyEngineProfileName(for: profile)
            let to = prefix + TabController.engineProfileName(for: profile)
            guard from != to, existing.contains(from), !existing.contains(to), claimed.insert(from).inserted else { continue }
            moves.append(Move(from: from, to: to))
        }
        return moves
    }
}
