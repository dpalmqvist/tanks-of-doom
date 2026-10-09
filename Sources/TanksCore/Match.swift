import Foundation

/// The two sides of a versus match. The host runs the simulation; the guest joined with a room code.
public enum PlayerSlot: Int, CaseIterable, Sendable {
    case host = 0
    case guest = 1

    public var opponent: PlayerSlot { self == .host ? .guest : .host }
    /// Index into `Level.bases`.
    public var baseIndex: Int { rawValue }
}

/// How much AI joins a versus match, borrowed from a campaign level's tuning.
public enum AIIntensity: Int, CaseIterable, Sendable {
    case light = 0
    case normal = 1
    case heavy = 2

    public var difficultyLevel: Int {
        switch self {
        case .light: return 1
        case .normal: return 3
        case .heavy: return 6
        }
    }

    public var name: String {
        switch self {
        case .light: return "LIGHT"
        case .normal: return "NORMAL"
        case .heavy: return "HEAVY"
        }
    }
}

/// What the host picks in the lobby, plus the seed both Macs build the city from.
public struct MatchSettings: Equatable, Sendable {
    public static let livesRange = 1...9

    public private(set) var lives: Int
    public var aiIntensity: AIIntensity
    public var seed: UInt64

    public init(lives: Int = 3, aiIntensity: AIIntensity = .normal, seed: UInt64 = 0) {
        self.lives = Self.clamp(lives)
        self.aiIntensity = aiIntensity
        self.seed = seed
    }

    public mutating func changeLives(by delta: Int) {
        lives = Self.clamp(lives + delta)
    }

    /// Steps through the intensities, wrapping around.
    public mutating func changeIntensity(by delta: Int) {
        let count = AIIntensity.allCases.count
        aiIntensity = AIIntensity(rawValue: ((aiIntensity.rawValue + delta) % count + count) % count)!
    }

    private static func clamp(_ lives: Int) -> Int {
        min(max(lives, livesRange.lowerBound), livesRange.upperBound)
    }
}

/// Who fired a shot: a human player or one of the AI hazards.
public enum Combatant: Equatable, Sendable {
    case player(PlayerSlot)
    case enemyTank
    case infantry(InfantryKind)
}

/// Kill-feed lines, worded for the player reading them.
public enum KillFeed {
    public static func name(of combatant: Combatant, viewer: PlayerSlot) -> String {
        switch combatant {
        case .player(let slot): return slot == viewer ? "You" : "Opponent"
        case .enemyTank: return "Rust Brigade tank"
        case .infantry(.rifleman): return "Rifleman"
        case .infantry(.machineGunner): return "Machine gunner"
        case .infantry(.bazooka): return "Bazooka"
        case .infantry(.mortar): return "Mortar"
        }
    }

    /// `killer` is nil when the victim abandoned their tank.
    public static func line(killer: Combatant?, victim: PlayerSlot, viewer: PlayerSlot) -> String {
        guard let killer else {
            return victim == viewer ? "You abandoned your tank" : "Opponent abandoned their tank"
        }
        return "\(name(of: killer, viewer: viewer)) destroyed \(name(of: .player(victim), viewer: viewer))"
    }
}

/// Lives, kills, respawn countdowns, spawn protection and the winner of a versus match.
public struct MatchState: Sendable {
    public static let respawnDelay = 3.0
    public static let invulnerableTime = 3.0

    public let settings: MatchSettings
    public private(set) var lives: [PlayerSlot: Int]
    public private(set) var kills: [PlayerSlot: Int] = [.host: 0, .guest: 0]
    public private(set) var winner: PlayerSlot?
    private var respawnTimers: [PlayerSlot: Double] = [:]
    private var invulnerableTimers: [PlayerSlot: Double] = [:]

    public init(settings: MatchSettings) {
        self.settings = settings
        lives = [.host: settings.lives, .guest: settings.lives]
    }

    public var isOver: Bool { winner != nil }
    public func isRespawning(_ slot: PlayerSlot) -> Bool { respawnTimers[slot] != nil }
    public func respawnRemaining(_ slot: PlayerSlot) -> Double? { respawnTimers[slot] }
    public func isInvulnerable(_ slot: PlayerSlot) -> Bool { invulnerableTimers[slot] != nil }

    /// A tank was destroyed. Any death costs a life; only the opponent's kills are credited.
    public mutating func playerDied(_ slot: PlayerSlot, killer: Combatant?) {
        guard !isOver, !isRespawning(slot) else { return }
        lives[slot, default: 0] -= 1
        invulnerableTimers[slot] = nil
        if killer == .player(slot.opponent) { kills[slot.opponent, default: 0] += 1 }
        if lives[slot, default: 0] <= 0 {
            winner = slot.opponent
        } else {
            respawnTimers[slot] = Self.respawnDelay
        }
    }

    /// Advances the countdowns. Returns the slots whose respawn delay ran out (they are now invulnerable).
    public mutating func tick(dt: Double) -> [PlayerSlot] {
        guard !isOver else { return [] }
        for slot in PlayerSlot.allCases {
            guard let remaining = invulnerableTimers[slot] else { continue }
            invulnerableTimers[slot] = remaining - dt > 0 ? remaining - dt : nil
        }
        var respawned: [PlayerSlot] = []
        for slot in PlayerSlot.allCases {
            guard let remaining = respawnTimers[slot] else { continue }
            if remaining - dt > 0 {
                respawnTimers[slot] = remaining - dt
            } else {
                respawnTimers[slot] = nil
                invulnerableTimers[slot] = Self.invulnerableTime
                respawned.append(slot)
            }
        }
        return respawned
    }

    /// Shooting gives up spawn protection.
    public mutating func playerFired(_ slot: PlayerSlot) {
        invulnerableTimers[slot] = nil
    }

    /// The player quit or their connection timed out: the opponent wins.
    public mutating func playerLeft(_ slot: PlayerSlot) {
        guard !isOver else { return }
        winner = slot.opponent
    }
}
