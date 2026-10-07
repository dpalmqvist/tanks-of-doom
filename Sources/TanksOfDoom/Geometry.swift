import CoreGraphics
import TanksCore

let tileSize = CGFloat(TileMap.tileSize)

/// Draw order (the view ignores sibling order, so every node sets one of these).
enum Z {
    static let ground: CGFloat = 0
    static let tracks: CGFloat = 1
    static let pickups: CGFloat = 2
    static let tanks: CGFloat = 5
    static let buildings: CGFloat = 10
    static let infantry: CGFloat = 11
    static let projectiles: CGFloat = 12
    static let effects: CGFloat = 20
    static let hud: CGFloat = 100
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }

    init(angle: CGFloat, length: CGFloat) {
        self.init(x: cos(angle) * length, y: sin(angle) * length)
    }

    var length: CGFloat { hypot(x, y) }
    func distance(to other: CGPoint) -> CGFloat { hypot(other.x - x, other.y - y) }
    func angle(to other: CGPoint) -> CGFloat { atan2(other.y - y, other.x - x) }
    var world: WorldPoint { WorldPoint(Double(x), Double(y)) }
}

extension WorldPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

extension TileMap {
    func grid(_ point: CGPoint) -> GridPoint { gridPoint(at: point.world) }
    func center(_ point: GridPoint) -> CGPoint { worldCenter(of: point).cgPoint }
}

extension Building {
    var worldCenter: CGPoint {
        CGPoint(x: (CGFloat(rect.minX) + CGFloat(rect.width) / 2) * tileSize,
                y: (CGFloat(rect.minY) + CGFloat(rect.height) / 2) * tileSize)
    }
}

/// Wraps an angle into -π...π.
func normalizeAngle(_ angle: CGFloat) -> CGFloat {
    var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if a > .pi { a -= 2 * .pi }
    if a < -.pi { a += 2 * .pi }
    return a
}

/// Turns `current` toward `target` by at most `maxStep` radians.
func rotate(_ current: CGFloat, toward target: CGFloat, maxStep: CGFloat) -> CGFloat {
    let diff = normalizeAngle(target - current)
    if abs(diff) <= maxStep { return current + diff }
    return current + (diff > 0 ? maxStep : -maxStep)
}
