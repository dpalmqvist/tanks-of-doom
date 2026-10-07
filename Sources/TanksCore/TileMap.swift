import Foundation

/// A position in world points (64 pt per tile, y up).
public struct WorldPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

public struct TileMap: Equatable, Sendable {
    public static let tileSize = 64.0

    public let width: Int
    public let height: Int
    private var tiles: [Tile]

    public init(width: Int, height: Int, fill: Tile) {
        self.width = width
        self.height = height
        tiles = Array(repeating: fill, count: width * height)
    }

    public func contains(_ p: GridPoint) -> Bool {
        p.x >= 0 && p.y >= 0 && p.x < width && p.y < height
    }

    public subscript(_ p: GridPoint) -> Tile {
        get { contains(p) ? tiles[p.y * width + p.x] : .wall }
        set { if contains(p) { tiles[p.y * width + p.x] = newValue } }
    }

    public subscript(x x: Int, y y: Int) -> Tile {
        get { self[GridPoint(x, y)] }
        set { self[GridPoint(x, y)] = newValue }
    }

    public func neighbors4(of p: GridPoint) -> [GridPoint] {
        [GridPoint(p.x + 1, p.y), GridPoint(p.x - 1, p.y), GridPoint(p.x, p.y + 1), GridPoint(p.x, p.y - 1)]
            .filter(contains)
    }

    public var allPoints: [GridPoint] {
        var result: [GridPoint] = []
        result.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width { result.append(GridPoint(x, y)) }
        }
        return result
    }

    public func points(where predicate: (Tile) -> Bool) -> [GridPoint] {
        allPoints.filter { predicate(self[$0]) }
    }

    /// All passable tiles connected to `start` through 4-neighbour moves.
    public func reachable(from start: GridPoint) -> Set<GridPoint> {
        guard self[start].isPassable else { return [] }
        var seen: Set<GridPoint> = [start]
        var stack = [start]
        while let p = stack.popLast() {
            for n in neighbors4(of: p) where self[n].isPassable && !seen.contains(n) {
                seen.insert(n)
                stack.append(n)
            }
        }
        return seen
    }

    // MARK: World geometry

    public func gridPoint(at w: WorldPoint) -> GridPoint {
        GridPoint(Int((w.x / Self.tileSize).rounded(.down)), Int((w.y / Self.tileSize).rounded(.down)))
    }

    public func worldCenter(of p: GridPoint) -> WorldPoint {
        WorldPoint((Double(p.x) + 0.5) * Self.tileSize, (Double(p.y) + 0.5) * Self.tileSize)
    }

    /// True when a circle at `c` overlaps no impassable tile (anything outside the map is a wall).
    public func canOccupy(_ c: WorldPoint, radius: Double) -> Bool {
        let s = Self.tileSize
        let minX = Int(((c.x - radius) / s).rounded(.down))
        let maxX = Int(((c.x + radius) / s).rounded(.down))
        let minY = Int(((c.y - radius) / s).rounded(.down))
        let maxY = Int(((c.y + radius) / s).rounded(.down))
        for gy in minY...maxY {
            for gx in minX...maxX where !self[x: gx, y: gy].isPassable {
                let left = Double(gx) * s
                let bottom = Double(gy) * s
                let nearestX = min(max(c.x, left), left + s)
                let nearestY = min(max(c.y, bottom), bottom + s)
                let dx = c.x - nearestX
                let dy = c.y - nearestY
                if dx * dx + dy * dy < radius * radius { return false }
            }
        }
        return true
    }

    public func speedMultiplier(at w: WorldPoint) -> Double {
        self[gridPoint(at: w)].speedMultiplier
    }
}
