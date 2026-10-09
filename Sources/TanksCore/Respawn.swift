import Foundation

/// Chooses where tanks come back in versus: random, reachable, and away from whoever would kill them at once.
public enum RespawnPicker {
    public static let minOpponentDistance = 15.0
    public static let minAITankDistance = 8.0
    public static let aiMinPlayerDistance = 15.0
    /// Keep-away distances are scaled by these in turn until some tile qualifies.
    static let relaxSteps = [1.0, 0.5, 0.25, 0.0]

    /// A destroyed player's new spot: a road, rubble or park tile reachable from their base.
    public static func playerSpawn(in map: TileMap, reachableFrom origin: GridPoint, opponent: GridPoint?,
                                   aiTanks: [GridPoint], using rng: inout some RandomNumberGenerator) -> GridPoint {
        var keepAway: [(point: GridPoint, distance: Double)] = aiTanks.map { (point: $0, distance: minAITankDistance) }
        if let opponent { keepAway.append((point: opponent, distance: minOpponentDistance)) }
        return pick(in: map, reachableFrom: origin, keepAway: keepAway,
                    allowed: { $0 == .road || $0 == .rubble || $0 == .park }, using: &rng)
    }

    /// A destroyed AI tank's new spot: a road tile far from both players.
    public static func aiTankSpawn(in map: TileMap, reachableFrom origin: GridPoint, players: [GridPoint],
                                   using rng: inout some RandomNumberGenerator) -> GridPoint {
        pick(in: map, reachableFrom: origin, keepAway: players.map { (point: $0, distance: aiMinPlayerDistance) },
             allowed: { $0 == .road }, using: &rng)
    }

    static func pick(in map: TileMap, reachableFrom origin: GridPoint, keepAway: [(point: GridPoint, distance: Double)],
                     allowed: (Tile) -> Bool, using rng: inout some RandomNumberGenerator) -> GridPoint {
        // Sorted, because Set order changes between runs and the same seed must give the same spot.
        let tiles = map.reachable(from: origin).filter { allowed(map[$0]) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        for factor in relaxSteps {
            let safe = tiles.filter { tile in keepAway.allSatisfy { tile.distance(to: $0.point) >= $0.distance * factor } }
            if let choice = safe.randomElement(using: &rng) { return choice }
        }
        return origin   // nothing drivable at all
    }
}

/// Things waiting to come back (AI tanks, soldiers, pickups), each with its own countdown.
public struct RespawnQueue<Item: Sendable>: Sendable {
    private var pending: [(item: Item, remaining: Double)] = []

    public init() {}

    public var count: Int { pending.count }

    public mutating func schedule(_ item: Item, after delay: Double) {
        pending.append((item: item, remaining: delay))
    }

    /// Advances every countdown; returns the items whose time is up, in the order they were scheduled.
    public mutating func tick(dt: Double) -> [Item] {
        var due: [Item] = []
        pending = pending.compactMap { entry in
            let left = entry.remaining - dt
            if left <= 0 {
                due.append(entry.item)
                return nil
            }
            return (item: entry.item, remaining: left)
        }
        return due
    }
}

/// How long the AI hazards and pickups stay gone in versus.
public enum VersusTimings {
    public static let aiTankRespawn = 20.0
    public static let infantryRespawn = 30.0
    public static let pickupRespawn = 45.0
}
