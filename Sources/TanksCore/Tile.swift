import Foundation

public enum Tile: Equatable, Sendable {
    case wall
    case road
    case building(Int)
    case rubble
    case park
    case crater
    case base

    public var isPassable: Bool {
        switch self {
        case .wall, .building: return false
        default: return true
        }
    }

    /// Relative cost of crossing this tile for pathfinding; nil when impassable.
    public var moveCost: Int? {
        switch self {
        case .wall, .building: return nil
        case .rubble, .crater: return 2
        default: return 1
        }
    }

    /// Vehicle speed multiplier while on this tile.
    public var speedMultiplier: Double { moveCost == 2 ? 0.5 : 1.0 }

    public var blocksSight: Bool { !isPassable }

    public var buildingID: Int? {
        if case .building(let id) = self { return id }
        return nil
    }
}
