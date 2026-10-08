import Foundation

/// Something the turret can lock onto.
public struct TargetCandidate: Equatable, Sendable {
    public let id: Int
    public let position: WorldPoint
    public let isTank: Bool

    public init(id: Int, position: WorldPoint, isTank: Bool) {
        self.id = id
        self.position = position
        self.isTank = isTank
    }
}

/// Picks what the auto-aiming turret should track: enemy tanks first, then nearest.
public enum TargetSelector {
    public static func prioritized(_ candidates: [TargetCandidate], from origin: WorldPoint) -> [TargetCandidate] {
        func distance(_ c: TargetCandidate) -> Double {
            let dx = c.position.x - origin.x
            let dy = c.position.y - origin.y
            return (dx * dx + dy * dy).squareRoot()
        }
        return candidates.sorted { a, b in
            if a.isTank != b.isTank { return a.isTank }
            return distance(a) < distance(b)
        }
    }

    /// Keeps the current lock while it is still a candidate; otherwise picks the best one.
    public static func autoTarget(current: Int?, candidates: [TargetCandidate], from origin: WorldPoint) -> TargetCandidate? {
        if let current, let locked = candidates.first(where: { $0.id == current }) { return locked }
        return prioritized(candidates, from: origin).first
    }

    /// The candidate after `current` in priority order, wrapping around.
    public static func next(after current: Int?, candidates: [TargetCandidate], from origin: WorldPoint) -> TargetCandidate? {
        let ordered = prioritized(candidates, from: origin)
        guard let current, let index = ordered.firstIndex(where: { $0.id == current }) else { return ordered.first }
        return ordered[(index + 1) % ordered.count]
    }
}

public enum AimMode: Equatable, Sendable {
    case auto, manual
}

/// Which input controls the turret. Manual (Q/E) control hands back to auto-aim a few
/// seconds after the keys are released.
public struct TurretAim: Sendable {
    public static let manualHold = 3.0

    public private(set) var mode: AimMode = .auto
    private var manualTimer: Double = 0

    public init() {}

    public mutating func manualInput() {
        mode = .manual
        manualTimer = Self.manualHold
    }

    public mutating func cycleTarget() {
        mode = .auto
    }

    public mutating func update(dt: Double, manualHeld: Bool) {
        guard mode == .manual else { return }
        if manualHeld {
            manualTimer = Self.manualHold
        } else {
            manualTimer -= dt
            if manualTimer <= 0 { mode = .auto }
        }
    }
}
