import Foundation

public struct GridRect: Equatable, Sendable {
    public let minX: Int
    public let minY: Int
    public let width: Int
    public let height: Int

    public init(minX: Int, minY: Int, width: Int, height: Int) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }
}

public struct Building: Equatable, Sendable {
    public let id: Int
    public let tiles: [GridPoint]
    public let rect: GridRect
    public let maxHP: Int
    public internal(set) var hp: Int

    public init(id: Int, tiles: [GridPoint]) {
        self.id = id
        self.tiles = tiles
        let xs = tiles.map(\.x)
        let ys = tiles.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        rect = GridRect(minX: minX, minY: minY, width: (xs.max() ?? 0) - minX + 1, height: (ys.max() ?? 0) - minY + 1)
        maxHP = Building.hitPoints(forArea: tiles.count)
        hp = maxHP
    }

    public static func hitPoints(forArea area: Int) -> Int {
        min(30 + 10 * area, 200)
    }

    public var isDestroyed: Bool { hp <= 0 }

    /// 0 intact, 1 cracked, 2 heavily damaged, 3 destroyed.
    public var damageStage: Int {
        if hp <= 0 { return 3 }
        let fraction = Double(hp) / Double(maxHP)
        if fraction > 0.66 { return 0 }
        return fraction > 0.33 ? 1 : 2
    }
}

public enum InfantryKind: CaseIterable, Sendable {
    case rifleman, machineGunner, bazooka, mortar
}

public struct InfantrySpawn: Equatable, Sendable {
    public let kind: InfantryKind
    public let buildingID: Int

    public init(kind: InfantryKind, buildingID: Int) {
        self.kind = kind
        self.buildingID = buildingID
    }
}

public enum CacheKind: Equatable, Sendable {
    case gas, ammo
}

public struct Cache: Equatable, Sendable {
    public let kind: CacheKind
    public let position: GridPoint

    public init(kind: CacheKind, position: GridPoint) {
        self.kind = kind
        self.position = position
    }
}

public struct EnemyTankSpawn: Equatable, Sendable {
    public let position: GridPoint
    public let patrol: [GridPoint]

    public init(position: GridPoint, patrol: [GridPoint]) {
        self.position = position
        self.patrol = patrol
    }
}

public enum BuildingHitResult: Equatable, Sendable {
    case none
    case damaged(stage: Int)
    case destroyed
}

public struct Level: Sendable {
    public let number: Int
    public let seed: UInt64
    public internal(set) var map: TileMap
    /// Indexed by building id.
    public internal(set) var buildings: [Building]
    public let baseTiles: [GridPoint]
    public let baseCenter: GridPoint
    public let caches: [Cache]
    public let infantry: [InfantrySpawn]
    public let enemyTanks: [EnemyTankSpawn]

    public init(number: Int, seed: UInt64, map: TileMap, buildings: [Building], baseTiles: [GridPoint],
                baseCenter: GridPoint, caches: [Cache], infantry: [InfantrySpawn], enemyTanks: [EnemyTankSpawn]) {
        self.number = number
        self.seed = seed
        self.map = map
        self.buildings = buildings
        self.baseTiles = baseTiles
        self.baseCenter = baseCenter
        self.caches = caches
        self.infantry = infantry
        self.enemyTanks = enemyTanks
    }

    public func isBase(_ p: GridPoint) -> Bool { map[p] == .base }

    /// Applies damage; a building at 0 HP collapses and its tiles become rubble.
    public mutating func damageBuilding(_ id: Int, by amount: Int) -> BuildingHitResult {
        guard buildings.indices.contains(id), !buildings[id].isDestroyed else { return .none }
        buildings[id].hp -= amount
        guard buildings[id].isDestroyed else { return .damaged(stage: buildings[id].damageStage) }
        for tile in buildings[id].tiles { map[tile] = .rubble }
        return .destroyed
    }
}
