import Testing
@testable import TanksCore

private let sampleSeeds: [UInt64] = Array(1...12)

@Test func sameSeedSameCity() {
    let a = CityGenerator.generate(seed: 99, level: 3)
    let b = CityGenerator.generate(seed: 99, level: 3)
    #expect(a.map == b.map)
    #expect(a.caches == b.caches)
    #expect(a.enemyTanks == b.enemyTanks)
    #expect(a.infantry == b.infantry)
}

@Test func differentSeedsDifferentCities() {
    #expect(CityGenerator.generate(seed: 1, level: 1).map != CityGenerator.generate(seed: 2, level: 1).map)
}

@Test(arguments: [1, 5, 10])
func citiesAreCompletable(level: Int) {
    for seed in sampleSeeds {
        let city = CityGenerator.generate(seed: seed, level: level)
        let reachable = city.map.reachable(from: city.baseCenter)
        #expect(city.map[city.baseCenter] == .base)
        #expect(city.baseTiles.count == 36)
        #expect(city.caches.allSatisfy { reachable.contains($0.position) })
        #expect(city.enemyTanks.allSatisfy { reachable.contains($0.position) })
        #expect(city.enemyTanks.allSatisfy { $0.patrol.allSatisfy(reachable.contains) })
        #expect(city.map.points(where: { $0 == .road }).allSatisfy(reachable.contains))
    }
}

@Test(arguments: [1, 5, 10])
func citiesMatchDifficulty(level: Int) {
    let d = Difficulty(level: level)
    for seed in sampleSeeds {
        let city = CityGenerator.generate(seed: seed, level: level)
        #expect(city.enemyTanks.count == d.enemyTankCount)
        #expect(city.caches.filter { $0.kind == .gas }.count == d.gasCacheCount)
        #expect(city.caches.filter { $0.kind == .ammo }.count == d.ammoCacheCount)
        #expect(city.enemyTanks.allSatisfy { $0.position.distance(to: city.baseCenter) >= CityGenerator.minTankDistanceFromBase })
        #expect(city.caches.allSatisfy { $0.position.distance(to: city.baseCenter) >= CityGenerator.safeZoneRadius })
        #expect(Set(city.caches.map(\.position)).count == city.caches.count)
        #expect(!city.infantry.isEmpty)
    }
}

@Test func buildingsMatchTheMap() {
    for seed in sampleSeeds {
        let city = CityGenerator.generate(seed: seed, level: 4)
        #expect(city.buildings.count > 50)
        for (index, b) in city.buildings.enumerated() {
            #expect(b.id == index)
            #expect(b.tiles.allSatisfy { city.map[$0] == .building(b.id) })
            #expect(b.tiles.count == b.rect.width * b.rect.height)
        }
        #expect(city.infantry.allSatisfy { city.buildings.indices.contains($0.buildingID) })
    }
}

@Test func mapIsWalledIn() {
    let city = CityGenerator.generate(seed: 3, level: 1)
    let n = CityGenerator.mapSize
    #expect(city.map.width == n && city.map.height == n)
    for i in 0..<n {
        #expect(city.map[x: i, y: 0] == .wall)
        #expect(city.map[x: i, y: n - 1] == .wall)
        #expect(city.map[x: 0, y: i] == .wall)
        #expect(city.map[x: n - 1, y: i] == .wall)
    }
}
