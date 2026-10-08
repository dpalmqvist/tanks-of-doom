import Foundation

/// The player's armor, fuel and ammunition, and the rules for spending and restoring them.
public struct TankStats: Equatable, Sendable {
    public static let maxArmor = 100.0
    public static let maxFuel = 100.0
    public static let maxShells = 20
    public static let maxRounds = 300
    public static let fuelPerSecondMoving = 0.9
    public static let fuelPerSecondIdle = 0.1
    public static let baseRepairPerSecond = 8.0
    public static let baseRefuelPerSecond = 10.0
    public static let baseMinShells = 8
    public static let baseMinRounds = 150
    public static let gasCacheFuel = 45.0
    public static let ammoCacheShells = 8
    public static let ammoCacheRounds = 120

    public var armor: Double = TankStats.maxArmor
    public var fuel: Double = TankStats.maxFuel
    public var shells: Int = TankStats.maxShells
    public var rounds: Int = TankStats.maxRounds

    public init() {}

    public var canMove: Bool { fuel > 0 }
    public var isDestroyed: Bool { armor <= 0 }

    public mutating func burnFuel(seconds: Double, moving: Bool) {
        let rate = moving ? Self.fuelPerSecondMoving : Self.fuelPerSecondIdle
        fuel = max(0, fuel - seconds * rate)
    }

    public mutating func takeDamage(_ amount: Int) {
        armor = max(0, armor - Double(amount))
    }

    public mutating func consumeShell() -> Bool {
        guard shells > 0 else { return false }
        shells -= 1
        return true
    }

    public mutating func consumeRound() -> Bool {
        guard rounds > 0 else { return false }
        rounds -= 1
        return true
    }

    /// While parked at base: armor repairs first, then fuel fills up to full, both gradually;
    /// ammo jumps to the base minimums.
    public mutating func applyBase(seconds: Double) {
        let repairSeconds = min(seconds, (Self.maxArmor - armor) / Self.baseRepairPerSecond)
        armor = min(Self.maxArmor, armor + Self.baseRepairPerSecond * repairSeconds)
        if armor >= Self.maxArmor {
            fuel = min(Self.maxFuel, fuel + Self.baseRefuelPerSecond * (seconds - repairSeconds))
        }
        shells = max(shells, Self.baseMinShells)
        rounds = max(rounds, Self.baseMinRounds)
    }

    public mutating func collect(_ kind: CacheKind) {
        switch kind {
        case .gas:
            fuel = min(Self.maxFuel, fuel + Self.gasCacheFuel)
        case .ammo:
            shells = min(Self.maxShells, shells + Self.ammoCacheShells)
            rounds = min(Self.maxRounds, rounds + Self.ammoCacheRounds)
        }
    }
}
