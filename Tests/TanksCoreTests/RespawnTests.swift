import Testing
@testable import TanksCore

/// One road row from x = 1 to x = width - 2, walls everywhere else.
private func strip(width: Int) -> TileMap {
    var map = TileMap(width: width, height: 3, fill: .wall)
    for x in 1..<(width - 1) { map[x: x, y: 1] = .road }
    return map
}

@Test func playerSpawnsOnlyOnReachableDrivableTiles() {
    var map = strip(width: 40)
    map[x: 10, y: 1] = .building(0)     // splits the strip: x 11...38 is unreachable from x = 1
    map[x: 5, y: 1] = .crater
    var rng = SeededRandom(seed: 1)
    for _ in 0..<200 {
        let p = RespawnPicker.playerSpawn(in: map, reachableFrom: GridPoint(1, 1), opponent: nil, aiTanks: [], using: &rng)
        #expect(p.y == 1 && (1...9).contains(p.x))
        #expect(p.x != 5)               // craters are not spawn tiles
    }
}

@Test func playerSpawnKeepsAwayFromOpponentAndAI() {
    let map = strip(width: 60)
    var rng = SeededRandom(seed: 2)
    for _ in 0..<200 {
        let p = RespawnPicker.playerSpawn(in: map, reachableFrom: GridPoint(1, 1), opponent: GridPoint(1, 1),
                                          aiTanks: [GridPoint(40, 1)], using: &rng)
        #expect(p.distance(to: GridPoint(1, 1)) >= RespawnPicker.minOpponentDistance)
        #expect(p.distance(to: GridPoint(40, 1)) >= RespawnPicker.minAITankDistance)
    }
}

@Test func playerSpawnRelaxesDistancesWhenNothingQualifies() {
    let map = strip(width: 10)          // road x 1...8
    var rng = SeededRandom(seed: 3)
    // Nothing is 15 (or 7.5) tiles from x = 4; at a quarter (3.75) only x = 8 qualifies.
    let p = RespawnPicker.playerSpawn(in: map, reachableFrom: GridPoint(1, 1), opponent: GridPoint(4, 1), aiTanks: [], using: &rng)
    #expect(p == GridPoint(8, 1))
}

@Test func spawnFallsBackToTheOriginWhenNothingIsDrivable() {
    let map = TileMap(width: 5, height: 5, fill: .wall)
    var rng = SeededRandom(seed: 4)
    #expect(RespawnPicker.playerSpawn(in: map, reachableFrom: GridPoint(2, 2), opponent: nil, aiTanks: [], using: &rng) == GridPoint(2, 2))
}

@Test func aiTanksRespawnOnRoadsFarFromBothPlayers() {
    var map = strip(width: 70)
    map[x: 50, y: 1] = .park
    var rng = SeededRandom(seed: 5)
    for _ in 0..<200 {
        let p = RespawnPicker.aiTankSpawn(in: map, reachableFrom: GridPoint(1, 1), players: [GridPoint(1, 1), GridPoint(68, 1)], using: &rng)
        #expect(map[p] == .road)
        #expect(p.distance(to: GridPoint(1, 1)) >= RespawnPicker.aiMinPlayerDistance)
        #expect(p.distance(to: GridPoint(68, 1)) >= RespawnPicker.aiMinPlayerDistance)
    }
}

@Test func sameSeedSameSpawn() {
    let map = strip(width: 60)
    var a = SeededRandom(seed: 9)
    var b = SeededRandom(seed: 9)
    #expect(RespawnPicker.playerSpawn(in: map, reachableFrom: GridPoint(1, 1), opponent: nil, aiTanks: [], using: &a)
        == RespawnPicker.playerSpawn(in: map, reachableFrom: GridPoint(1, 1), opponent: nil, aiTanks: [], using: &b))
}

@Test func queueReleasesItemsWhenTheirTimeIsUp() {
    var q = RespawnQueue<String>()
    q.schedule("tank", after: 20)
    q.schedule("soldier", after: 5)
    #expect(q.count == 2)
    #expect(q.tick(dt: 4.9).isEmpty)
    #expect(q.tick(dt: 0.2) == ["soldier"])
    #expect(q.tick(dt: 14.0).isEmpty)
    #expect(q.tick(dt: 1.0) == ["tank"])
    #expect(q.count == 0)
}

@Test func queueReleasesSimultaneousItemsInScheduleOrder() {
    var q = RespawnQueue<Int>()
    q.schedule(2, after: 1)
    q.schedule(1, after: 1)
    #expect(q.tick(dt: 1) == [2, 1])
}

@Test func versusTimingsMatchTheSpec() {
    #expect(VersusTimings.aiTankRespawn == 20)
    #expect(VersusTimings.infantryRespawn == 30)
    #expect(VersusTimings.pickupRespawn == 45)
}
