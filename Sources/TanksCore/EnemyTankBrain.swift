import Foundation

public enum EnemyTankState: Equatable, Sendable {
    case patrol, attack, search, retreat
}

public struct EnemyPerception: Sendable {
    public var canSeePlayer: Bool
    public var distanceToPlayer: Double
    public var armorFraction: Double
    public var reachedSearchPoint: Bool

    public init(canSeePlayer: Bool, distanceToPlayer: Double, armorFraction: Double, reachedSearchPoint: Bool) {
        self.canSeePlayer = canSeePlayer
        self.distanceToPlayer = distanceToPlayer
        self.armorFraction = armorFraction
        self.reachedSearchPoint = reachedSearchPoint
    }
}

/// Decides what an enemy tank should be doing. Movement and aiming live in the app.
public struct EnemyTankBrain: Sendable {
    public static let sightRange = 560.0
    public static let retreatArmorFraction = 0.25
    public static let searchTimeout = 8.0
    public static let retreatDuration = 6.0

    public private(set) var state: EnemyTankState = .patrol
    public private(set) var timeInState: Double = 0

    public init() {}

    @discardableResult
    public mutating func update(_ p: EnemyPerception, dt: Double) -> EnemyTankState {
        timeInState += dt
        let spotted = p.canSeePlayer && p.distanceToPlayer <= Self.sightRange
        let crippled = p.armorFraction <= Self.retreatArmorFraction
        let next: EnemyTankState
        switch state {
        case .patrol:
            next = spotted ? (crippled ? .retreat : .attack) : .patrol
        case .attack:
            if crippled { next = .retreat } else { next = spotted ? .attack : .search }
        case .search:
            if spotted {
                next = crippled ? .retreat : .attack
            } else if p.reachedSearchPoint || timeInState >= Self.searchTimeout {
                next = .patrol
            } else {
                next = .search
            }
        case .retreat:
            next = (!spotted && timeInState >= Self.retreatDuration) ? .patrol : .retreat
        }
        if next != state {
            state = next
            timeInState = 0
        }
        return state
    }
}
