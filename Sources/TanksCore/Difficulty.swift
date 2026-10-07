import Foundation

/// Tuning numbers for a level. Everything ramps up with the level number and is capped.
public struct Difficulty: Sendable {
    public let level: Int

    public init(level: Int) {
        self.level = max(1, level)
    }

    private var step: Double { Double(level - 1) }

    public var enemyTankCount: Int { min(2 + level, 10) }
    public var enemyTankArmor: Int { min(60 + 15 * (level - 1), 200) }
    /// Points per second.
    public var enemyTankSpeed: Double { min(90 + 6 * step, 150) }
    /// Seconds an enemy tank waits after spotting the player before its first shot.
    public var enemyReactionTime: Double { max(1.2 - 0.1 * step, 0.3) }
    /// Probability that a building is occupied.
    public var infantryChance: Double { min(0.25 + 0.04 * step, 0.6) }
    public var gasCacheCount: Int { max(4, 7 - level / 3) }
    public var ammoCacheCount: Int { max(4, 7 - level / 3) }

    public func infantryWeights() -> [(kind: InfantryKind, weight: Double)] {
        [
            (.rifleman, max(1, 6 - step)),
            (.machineGunner, 2 + step * 0.5),
            (.bazooka, 1 + step * 0.6),
            (.mortar, level >= 2 ? 0.5 + step * 0.4 : 0),
        ]
    }

    public func randomInfantryKind(using rng: inout SeededRandom) -> InfantryKind {
        let weights = infantryWeights()
        let total = weights.reduce(0) { $0 + $1.weight }
        var roll = Double.random(in: 0..<total, using: &rng)
        for entry in weights {
            if roll < entry.weight { return entry.kind }
            roll -= entry.weight
        }
        return .rifleman
    }
}
