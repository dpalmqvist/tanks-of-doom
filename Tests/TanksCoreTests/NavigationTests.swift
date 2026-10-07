import Testing
@testable import TanksCore

@Test func straightPathOnOpenRoad() {
    let map = TileMap(width: 5, height: 1, fill: .road)
    let path = Pathfinder.findPath(in: map, from: GridPoint(0, 0), to: GridPoint(4, 0))
    #expect(path == [GridPoint(0, 0), GridPoint(1, 0), GridPoint(2, 0), GridPoint(3, 0), GridPoint(4, 0)])
}

@Test func pathGoesAroundBuildingsWithoutCuttingCorners() {
    var map = TileMap(width: 3, height: 3, fill: .road)
    map[x: 1, y: 1] = .building(0)
    let path = Pathfinder.findPath(in: map, from: GridPoint(0, 1), to: GridPoint(2, 1))!
    #expect(path.first == GridPoint(0, 1))
    #expect(path.last == GridPoint(2, 1))
    #expect(!path.contains(GridPoint(1, 1)))
    #expect(path.count == 5)   // diagonals past the building corner are not allowed
}

@Test func pathPrefersRoadOverRubble() {
    var map = TileMap(width: 5, height: 3, fill: .road)
    for x in 1...3 { map[x: x, y: 1] = .rubble }
    let path = Pathfinder.findPath(in: map, from: GridPoint(0, 1), to: GridPoint(4, 1))!
    #expect(path.allSatisfy { map[$0] != .rubble })
}

@Test func unreachableGoalReturnsNil() {
    var map = TileMap(width: 3, height: 3, fill: .road)
    for y in 0..<3 { map[x: 1, y: y] = .wall }
    #expect(Pathfinder.findPath(in: map, from: GridPoint(0, 0), to: GridPoint(2, 2)) == nil)
    #expect(Pathfinder.findPath(in: map, from: GridPoint(0, 0), to: GridPoint(1, 1)) == nil)
}

@Test func pathToSelf() {
    let map = TileMap(width: 2, height: 2, fill: .road)
    #expect(Pathfinder.findPath(in: map, from: GridPoint(1, 1), to: GridPoint(1, 1)) == [GridPoint(1, 1)])
}

@Test func buildingsBlockSightButRubbleDoesNot() {
    var map = TileMap(width: 7, height: 1, fill: .road)
    #expect(LineOfSight.isClear(in: map, from: GridPoint(0, 0), to: GridPoint(6, 0)))
    map[x: 3, y: 0] = .rubble
    #expect(LineOfSight.isClear(in: map, from: GridPoint(0, 0), to: GridPoint(6, 0)))
    map[x: 3, y: 0] = .building(2)
    #expect(!LineOfSight.isClear(in: map, from: GridPoint(0, 0), to: GridPoint(6, 0)))
}

@Test func lineOfSightCanIgnoreOwnBuilding() {
    var map = TileMap(width: 6, height: 1, fill: .road)
    map[x: 0, y: 0] = .building(4)
    map[x: 1, y: 0] = .building(4)
    #expect(LineOfSight.isClear(in: map, from: GridPoint(0, 0), to: GridPoint(5, 0), ignoringBuilding: 4))
    #expect(!LineOfSight.isClear(in: map, from: GridPoint(0, 0), to: GridPoint(5, 0)))
    map[x: 3, y: 0] = .building(9)
    #expect(!LineOfSight.isClear(in: map, from: GridPoint(0, 0), to: GridPoint(5, 0), ignoringBuilding: 4))
}
