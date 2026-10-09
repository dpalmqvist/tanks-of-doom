import TanksCore

/// How this Mac takes part in a versus match.
enum VersusRole {
    /// Debug only: both players on this keyboard (TANKS_HOTSEAT=1).
    case hotSeat

    /// The player at this keyboard.
    var localSlot: PlayerSlot {
        switch self {
        case .hotSeat: return .host
        }
    }

    /// This Mac runs the simulation and streams it to another Mac.
    var isHost: Bool {
        switch self {
        case .hotSeat: return false
        }
    }

    /// This Mac only mirrors what the host sends.
    var isGuest: Bool {
        switch self {
        case .hotSeat: return false
        }
    }
}

enum GameMode {
    case campaign
    case versus(VersusRole)
}
