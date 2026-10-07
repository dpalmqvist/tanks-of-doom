import Testing
@testable import TanksCore

private func smallLevel() -> Level {
    var map = TileMap(width: 4, height: 4, fill: .road)
    let tiles = [GridPoint(1, 1), GridPoint(2, 1)]
    for t in tiles { map[t] = .building(0) }
    map[x: 0, y: 0] = .base
    return Level(number: 1, seed: 0, map: map, buildings: [Building(id: 0, tiles: tiles)],
                 baseTiles: [GridPoint(0, 0)], baseCenter: GridPoint(0, 0), caches: [], infantry: [], enemyTanks: [])
}

@Test func buildingHitPointsScaleWithArea() {
    #expect(Building.hitPoints(forArea: 2) == 50)
    #expect(Building.hitPoints(forArea: 4) == 70)
    #expect(Building.hitPoints(forArea: 30) == 200)
}

@Test func buildingRectAndStages() {
    var b = Building(id: 3, tiles: [GridPoint(2, 5), GridPoint(3, 5), GridPoint(2, 6), GridPoint(3, 6)])
    #expect(b.rect == GridRect(minX: 2, minY: 5, width: 2, height: 2))
    #expect(b.damageStage == 0)
    b.hp = 40   // of 70
    #expect(b.damageStage == 1)
    b.hp = 10
    #expect(b.damageStage == 2)
    b.hp = 0
    #expect(b.damageStage == 3)
    #expect(b.isDestroyed)
}

@Test func buildingCollapsesIntoRubble() {
    var level = smallLevel()   // building hp 50
    #expect(level.damageBuilding(0, by: 20) == .damaged(stage: 1))
    #expect(level.map[GridPoint(1, 1)] == .building(0))
    #expect(level.damageBuilding(0, by: 40) == .destroyed)
    #expect(level.map[GridPoint(1, 1)] == .rubble)
    #expect(level.map[GridPoint(2, 1)] == .rubble)
    #expect(level.damageBuilding(0, by: 40) == .none)
    #expect(level.damageBuilding(99, by: 40) == .none)
}

@Test func baseLookup() {
    let level = smallLevel()
    #expect(level.isBase(GridPoint(0, 0)))
    #expect(!level.isBase(GridPoint(3, 3)))
}

@Test func difficultyScales() {
    let easy = Difficulty(level: 1)
    let hard = Difficulty(level: 6)
    #expect(easy.enemyTankCount == 3)
    #expect(hard.enemyTankCount > easy.enemyTankCount)
    #expect(hard.enemyTankArmor > easy.enemyTankArmor)
    #expect(hard.enemyTankSpeed > easy.enemyTankSpeed)
    #expect(hard.enemyReactionTime < easy.enemyReactionTime)
    #expect(hard.infantryChance > easy.infantryChance)
}

@Test func difficultyIsCapped() {
    let d = Difficulty(level: 100)
    #expect(d.enemyTankCount == 10)
    #expect(d.enemyTankArmor == 200)
    #expect(d.enemyTankSpeed == 150)
    #expect(d.enemyReactionTime == 0.3)
    #expect(d.infantryChance == 0.6)
    #expect(d.gasCacheCount == 4)
    #expect(d.ammoCacheCount == 4)
    #expect(Difficulty(level: 0).level == 1)
}

@Test func noMortarsOnLevelOne() {
    var rng = SeededRandom(seed: 5)
    let d = Difficulty(level: 1)
    let kinds = (0..<500).map { _ in d.randomInfantryKind(using: &rng) }
    #expect(!kinds.contains(.mortar))
    #expect(kinds.contains(.rifleman))
}

@Test func mortarsAppearLater() {
    var rng = SeededRandom(seed: 5)
    let d = Difficulty(level: 5)
    let kinds = (0..<500).map { _ in d.randomInfantryKind(using: &rng) }
    #expect(kinds.contains(.mortar))
}
