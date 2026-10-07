import Foundation

public enum InfantryState: Equatable, Sendable {
    case hidden, exposed
}

public enum InfantryEvent: Equatable, Sendable {
    case expose, hide
}

/// Pop-up behaviour of a soldier inside a building: hide, appear at a window to fire, duck back.
public struct InfantryBrain: Sendable {
    public let kind: InfantryKind
    public private(set) var state: InfantryState = .hidden
    public private(set) var timer: Double

    public init(kind: InfantryKind, initialDelay: Double) {
        self.kind = kind
        timer = initialDelay
    }

    public var range: Double { Combat.spec(kind.weapon).range }

    public var exposedDuration: Double {
        switch kind {
        case .rifleman: return 1.8
        case .machineGunner: return 2.4
        case .bazooka: return 1.4
        case .mortar: return 1.2
        }
    }

    public var hiddenDuration: Double {
        switch kind {
        case .rifleman: return 2.0
        case .machineGunner: return 2.5
        case .bazooka: return 3.5
        case .mortar: return 5.0
        }
    }

    /// Mortars lob shells over buildings, so they only need the player in range.
    public var needsLineOfSight: Bool { kind != .mortar }

    public mutating func update(dt: Double, playerVisible: Bool, distance: Double) -> InfantryEvent? {
        timer = max(0, timer - dt)
        switch state {
        case .hidden:
            let canEngage = distance <= range && (playerVisible || !needsLineOfSight)
            guard timer <= 0, canEngage else { return nil }
            state = .exposed
            timer = exposedDuration
            return .expose
        case .exposed:
            guard timer <= 0 else { return nil }
            state = .hidden
            timer = hiddenDuration
            return .hide
        }
    }
}
