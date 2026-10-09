import Testing
@testable import TanksCore

/// FNV-1a over everything the generator decides. Pins campaign output so versus changes can't alter it.
private func fingerprint(_ level: Level) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    func mix(_ v: Int) { h = (h ^ UInt64(bitPattern: Int64(v))) &* 0x100_0000_01b3 }
    for p in level.map.allPoints {
        switch level.map[p] {
        case .wall: mix(1)
        case .road: mix(2)
        case .building(let id): mix(100 + id)
        case .rubble: mix(3)
        case .park: mix(4)
        case .crater: mix(5)
        case .base: mix(6)
        }
    }
    for c in level.caches { mix(c.kind == .gas ? 7 : 8); mix(c.position.x); mix(c.position.y) }
    for t in level.enemyTanks { mix(t.position.x); mix(t.position.y); for p in t.patrol { mix(p.x); mix(p.y) } }
    for i in level.infantry { mix(i.buildingID); mix(InfantryKind.allCases.firstIndex(of: i.kind)!) }
    return h
}

@Test func singleBaseCitiesAreUnchanged() {
    // Values recorded from the generator before multiplayer work began (commit a1359ff).
    let golden: [(seed: UInt64, level: Int, fingerprint: UInt64)] = [
        (99, 3, 0x17e9_678c_242d_9667),
        (7, 1, 0x52e8_5ea9_b9e0_0c83),
        (12345, 8, 0xc474_b4ae_dac4_0230),
    ]
    for g in golden {
        #expect(fingerprint(CityGenerator.generate(seed: g.seed, level: g.level)) == g.fingerprint, "seed \(g.seed)")
    }
}

@Test func campaignLevelHasOneBaseSite() {
    let city = CityGenerator.generate(seed: 5, level: 2)
    #expect(city.bases == [BaseSite(center: city.baseCenter, tiles: city.baseTiles)])
}

@Test(arguments: [1, 3, 6])
func twoBaseCitiesAreConnectedAndFair(level: Int) {
    for seed in UInt64(1)...12 {
        let city = CityGenerator.generate(seed: seed, level: level, bases: 2)
        #expect(city.bases.count == 2)
        #expect(city.bases[0].center == GridPoint(6, 6))
        #expect(city.bases[1].center == GridPoint(74, 74))
        for base in city.bases {
            #expect(base.tiles.count == 36)
            #expect(base.tiles.allSatisfy { city.map[$0] == .base })
        }
        let reachable = city.map.reachable(from: city.bases[0].center)
        #expect(reachable.contains(city.bases[1].center))
        #expect(city.caches.allSatisfy { reachable.contains($0.position) })
        for tank in city.enemyTanks {
            #expect(city.bases.allSatisfy { $0.center.distance(to: tank.position) >= CityGenerator.minTankDistanceFromBase })
        }
        for soldier in city.infantry {
            let building = city.buildings[soldier.buildingID]
            let center = building.tiles[building.tiles.count / 2]
            #expect(city.bases.allSatisfy { $0.center.distance(to: center) >= CityGenerator.safeZoneRadius + 2 })
        }
    }
}

@Test func baseIndexFindsTheRightBase() {
    let city = CityGenerator.generate(seed: 3, level: 1, bases: 2)
    #expect(city.baseIndex(at: city.bases[0].center) == 0)
    #expect(city.baseIndex(at: city.bases[1].center) == 1)
    #expect(city.baseIndex(at: GridPoint(40, 0)) == nil)
}

@Test func settingBuildingHPMirrorsDamageAndCollapse() {
    var map = TileMap(width: 4, height: 4, fill: .road)
    let tiles = [GridPoint(1, 1), GridPoint(2, 1)]
    for t in tiles { map[t] = .building(0) }
    var level = Level(number: 1, seed: 0, map: map, buildings: [Building(id: 0, tiles: tiles)], baseTiles: [],
                      baseCenter: GridPoint(0, 0), caches: [], infantry: [], enemyTanks: [])
    #expect(level.setBuildingHP(0, to: 30) == .damaged(stage: 1))   // 50 max HP
    #expect(level.buildings[0].hp == 30)
    #expect(level.setBuildingHP(0, to: 30) == .none)
    #expect(level.setBuildingHP(0, to: 40) == .none)                 // never heals
    #expect(level.setBuildingHP(0, to: 0) == .destroyed)
    #expect(level.map[GridPoint(1, 1)] == .rubble)
    #expect(level.setBuildingHP(7, to: 0) == .none)
}
