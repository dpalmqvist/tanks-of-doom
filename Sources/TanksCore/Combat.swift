import Foundation

public enum WeaponKind: CaseIterable, Sendable {
    case mainGun, machineGun, enemyShell, rifle, enemyMachineGun, bazooka, mortar
}

/// What a weapon can hurt. For enemy weapons `.tank` means the player's tank.
public enum TargetKind: Hashable, Sendable {
    case tank, infantry, building
}

public struct WeaponSpec: Sendable {
    public let damage: Int
    /// Points; 0 means no splash.
    public let splashRadius: Double
    /// Seconds between shots.
    public let reload: Double
    /// Points per second (mortars fly a fixed-time arc instead).
    public let projectileSpeed: Double
    /// Points.
    public let range: Double
    public let targets: Set<TargetKind>
}

public enum Combat {
    public static func spec(_ weapon: WeaponKind) -> WeaponSpec {
        switch weapon {
        case .mainGun:
            return WeaponSpec(damage: 40, splashRadius: 70, reload: 1.2, projectileSpeed: 750, range: 750, targets: [.tank, .infantry, .building])
        case .machineGun:
            return WeaponSpec(damage: 4, splashRadius: 0, reload: 0.08, projectileSpeed: 1100, range: 550, targets: [.infantry])
        case .enemyShell:
            return WeaponSpec(damage: 12, splashRadius: 50, reload: 2.5, projectileSpeed: 550, range: 560, targets: [.tank])
        case .rifle:
            return WeaponSpec(damage: 2, splashRadius: 0, reload: 1.0, projectileSpeed: 800, range: 480, targets: [.tank])
        case .enemyMachineGun:
            return WeaponSpec(damage: 1, splashRadius: 0, reload: 0.12, projectileSpeed: 800, range: 420, targets: [.tank])
        case .bazooka:
            return WeaponSpec(damage: 18, splashRadius: 30, reload: 4.0, projectileSpeed: 260, range: 520, targets: [.tank])
        case .mortar:
            return WeaponSpec(damage: 20, splashRadius: 60, reload: 6.0, projectileSpeed: 0, range: 640, targets: [.tank])
        }
    }

    /// Damage dealt to a target `distance` points from the impact (0 = direct hit).
    public static func damage(_ weapon: WeaponKind, to target: TargetKind, distance: Double) -> Int {
        let s = spec(weapon)
        guard s.targets.contains(target) else { return 0 }
        if distance <= 0 { return s.damage }
        guard s.splashRadius > 0, distance < s.splashRadius else { return 0 }
        return Int((Double(s.damage) * (1 - distance / s.splashRadius)).rounded())
    }
}

extension InfantryKind {
    public var weapon: WeaponKind {
        switch self {
        case .rifleman: return .rifle
        case .machineGunner: return .enemyMachineGun
        case .bazooka: return .bazooka
        case .mortar: return .mortar
        }
    }
}
