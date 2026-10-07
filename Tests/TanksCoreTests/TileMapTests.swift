import Testing
@testable import TanksCore

@Test func tileRules() {
    #expect(Tile.road.isPassable)
    #expect(!Tile.building(3).isPassable)
    #expect(!Tile.wall.isPassable)
    #expect(Tile.rubble.moveCost == 2)
    #expect(Tile.crater.moveCost == 2)
    #expect(Tile.road.moveCost == 1)
    #expect(Tile.building(1).moveCost == nil)
    #expect(Tile.rubble.speedMultiplier == 0.5)
    #expect(Tile.road.speedMultiplier == 1)
    #expect(!Tile.rubble.blocksSight)
    #expect(Tile.building(0).blocksSight)
    #expect(Tile.building(7).buildingID == 7)
    #expect(Tile.road.buildingID == nil)
}

@Test func outOfBoundsReadsAsWall() {
    var map = TileMap(width: 4, height: 4, fill: .road)
    #expect(map[x: -1, y: 0] == .wall)
    #expect(map[x: 4, y: 0] == .wall)
    #expect(map[x: 0, y: 4] == .wall)
    map[x: 9, y: 9] = .road   // ignored, must not crash
    #expect(map[x: 3, y: 3] == .road)
}

@Test func floodFillStopsAtBuildings() {
    var map = TileMap(width: 5, height: 1, fill: .road)
    map[x: 2, y: 0] = .building(0)
    #expect(map.reachable(from: GridPoint(0, 0)) == [GridPoint(0, 0), GridPoint(1, 0)])
}

@Test func worldGridRoundTrip() {
    let map = TileMap(width: 10, height: 10, fill: .road)
    let center = map.worldCenter(of: GridPoint(3, 7))
    #expect(center == WorldPoint(3.5 * 64, 7.5 * 64))
    #expect(map.gridPoint(at: center) == GridPoint(3, 7))
    #expect(map.gridPoint(at: WorldPoint(-1, 10)) == GridPoint(-1, 0))
}

@Test func circleCollisionRespectsBuildingsAndEdges() {
    var map = TileMap(width: 3, height: 3, fill: .road)
    map[x: 1, y: 1] = .building(0)
    let s = TileMap.tileSize
    #expect(map.canOccupy(WorldPoint(s * 0.5, s * 0.5), radius: 20))
    #expect(!map.canOccupy(WorldPoint(s * 1.5, s - 10), radius: 20))   // 10 pt below the building
    #expect(map.canOccupy(WorldPoint(s * 1.5, s - 25), radius: 20))    // 25 pt below the building
    #expect(!map.canOccupy(WorldPoint(10, s * 0.5), radius: 20))       // overlaps the map edge
}

@Test func speedMultiplierFollowsTile() {
    var map = TileMap(width: 2, height: 1, fill: .road)
    map[x: 1, y: 0] = .rubble
    #expect(map.speedMultiplier(at: WorldPoint(32, 32)) == 1)
    #expect(map.speedMultiplier(at: WorldPoint(96, 32)) == 0.5)
}
