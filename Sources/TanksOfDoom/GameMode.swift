import TanksCore

/// How this Mac takes part in a versus match.
enum VersusRole {
    /// Debug only: both players on this keyboard (TANKS_HOTSEAT=1).
    case hotSeat
    /// Runs the simulation and streams it to the guest.
    case host(MatchLink)
    /// Sends its keys and mirrors what the host streams.
    case guest(MatchLink)

    /// The player at this keyboard.
    var localSlot: PlayerSlot {
        if case .guest = self { return .guest }
        return .host
    }

    var isHost: Bool {
        if case .host = self { return true }
        return false
    }

    var isGuest: Bool {
        if case .guest = self { return true }
        return false
    }

    var link: MatchLink? {
        switch self {
        case .hotSeat: return nil
        case .host(let link), .guest(let link): return link
        }
    }
}

enum GameMode {
    case campaign
    case versus(VersusRole)
}
