import Foundation

/// Builds a walled, war-torn city: a grid of 2-wide avenues, blocks subdivided by
/// 1-wide streets, blocks filled with building lots, a home base in the bottom-left corner,
/// enemy tank patrols far from base, hidden caches and occupied buildings.
public enum CityGenerator {
    public static let mapSize = 80
    public static let minTankDistanceFromBase = 30.0
    public static let safeZoneRadius = 10.0
    static let baseOrigin = GridPoint(3, 3)
    static let baseSize = 6
    static let maxLeafSide = 9

    struct BlockRect {
        var x: Int, y: Int, w: Int, h: Int

        var points: [GridPoint] {
            var result: [GridPoint] = []
            for py in y..<(y + h) {
                for px in x..<(x + w) { result.append(GridPoint(px, py)) }
            }
            return result
        }
    }

    public static func generate(seed: UInt64, level: Int) -> Level {
        for attempt in 0..<100 {
            var rng = SeededRandom(seed: seed &+ UInt64(attempt) &* 0x9E37_79B9_7F4A_7C15)
            if let city = build(seed: seed, level: max(1, level), rng: &rng) { return city }
        }
        fatalError("CityGenerator could not build a valid city for seed \(seed)")
    }

    static func build(seed: UInt64, level number: Int, rng: inout SeededRandom) -> Level? {
        let n = mapSize
        let difficulty = Difficulty(level: number)
        // `.park` doubles as "unassigned" while building; leftovers stay as parks.
        var map = TileMap(width: n, height: n, fill: .park)
        for i in 0..<n {
            map[x: i, y: 0] = .wall
            map[x: i, y: n - 1] = .wall
            map[x: 0, y: i] = .wall
            map[x: n - 1, y: i] = .wall
        }

        // 1. Avenues, 2 tiles wide, including a ring road just inside the wall.
        let xs = avenuePositions(size: n, rng: &rng)
        let ys = avenuePositions(size: n, rng: &rng)
        for x in xs {
            for y in 1..<(n - 1) { map[x: x, y: y] = .road; map[x: x + 1, y: y] = .road }
        }
        for y in ys {
            for x in 1..<(n - 1) { map[x: x, y: y] = .road; map[x: x, y: y + 1] = .road }
        }

        // 2. Subdivide each block with 1-wide streets.
        var leaves: [BlockRect] = []
        for i in 0..<(xs.count - 1) {
            for j in 0..<(ys.count - 1) {
                let block = BlockRect(x: xs[i] + 2, y: ys[j] + 2, w: xs[i + 1] - xs[i] - 2, h: ys[j + 1] - ys[j] - 2)
                subdivide(block, map: &map, rng: &rng, into: &leaves)
            }
        }

        // 3. Home base.
        var baseTiles: [GridPoint] = []
        for y in baseOrigin.y..<(baseOrigin.y + baseSize) {
            for x in baseOrigin.x..<(baseOrigin.x + baseSize) {
                map[x: x, y: y] = .base
                baseTiles.append(GridPoint(x, y))
            }
        }
        let baseCenter = GridPoint(baseOrigin.x + baseSize / 2, baseOrigin.y + baseSize / 2)

        // 4. Building lots.
        var buildings: [Building] = []
        for leaf in leaves { fillLots(leaf, map: &map, buildings: &buildings, rng: &rng) }

        let roads = map.points { $0 == .road }
        let reachable = map.reachable(from: baseCenter)
        guard roads.allSatisfy(reachable.contains) else { return nil }

        // 5. Enemy tanks with patrol routes, far from base.
        var tanks: [EnemyTankSpawn] = []
        let farRoads = roads.filter { $0.distance(to: baseCenter) >= minTankDistanceFromBase }.shuffled(using: &rng)
        for candidate in farRoads where tanks.count < difficulty.enemyTankCount {
            guard tanks.allSatisfy({ $0.position.distance(to: candidate) >= 8 }) else { continue }
            let nearby = roads.filter { (6...25).contains($0.distance(to: candidate)) }
            guard nearby.count >= 4 else { continue }
            var patrol = [candidate]
            for _ in 0..<rng.int(2...4) { patrol.append(nearby[rng.int(0...(nearby.count - 1))]) }
            tanks.append(EnemyTankSpawn(position: candidate, patrol: patrol))
        }
        guard tanks.count == difficulty.enemyTankCount else { return nil }

        // 6. Hidden caches: alleys (narrow road tiles), rubble, craters and parks, biased away from base.
        let candidates = map.allPoints.filter { p in
            guard reachable.contains(p), p.distance(to: baseCenter) >= safeZoneRadius else { return false }
            switch map[p] {
            case .rubble, .crater, .park: return true
            case .road: return map.neighbors4(of: p).filter { map[$0].isPassable }.count <= 2
            default: return false
            }
        }
        guard !candidates.isEmpty else { return nil }
        let weights = candidates.map { $0.distance(to: baseCenter) }
        let totalWeight = weights.reduce(0, +)
        let kinds = Array(repeating: CacheKind.gas, count: difficulty.gasCacheCount)
            + Array(repeating: CacheKind.ammo, count: difficulty.ammoCacheCount)
        var caches: [Cache] = []
        for kind in kinds {
            var placed = false
            for _ in 0..<200 {
                let p = candidates[weightedIndex(weights, total: totalWeight, rng: &rng)]
                if caches.allSatisfy({ $0.position.distance(to: p) >= 6 }) {
                    caches.append(Cache(kind: kind, position: p))
                    placed = true
                    break
                }
            }
            guard placed else { return nil }
        }

        // 7. Infantry in buildings outside the safe zone around base.
        var infantry: [InfantrySpawn] = []
        for b in buildings {
            let center = b.tiles[b.tiles.count / 2]
            guard center.distance(to: baseCenter) >= safeZoneRadius + 2, rng.chance(difficulty.infantryChance) else { continue }
            let count = (b.tiles.count >= 9 && rng.chance(0.35)) ? 2 : 1
            for _ in 0..<count {
                infantry.append(InfantrySpawn(kind: difficulty.randomInfantryKind(using: &rng), buildingID: b.id))
            }
        }

        return Level(number: number, seed: seed, map: map, buildings: buildings, baseTiles: baseTiles,
                     baseCenter: baseCenter, caches: caches, infantry: infantry, enemyTanks: tanks)
    }

    static func avenuePositions(size n: Int, rng: inout SeededRandom) -> [Int] {
        let last = n - 3
        var result = [1]
        var x = 1
        while true {
            x += 2 + rng.int(12...18)
            if x > last - 8 { break }
            result.append(x)
        }
        result.append(last)
        return result
    }

    static func subdivide(_ r: BlockRect, map: inout TileMap, rng: inout SeededRandom, into leaves: inout [BlockRect]) {
        let vertical = r.w >= r.h
        let length = vertical ? r.w : r.h
        guard length > maxLeafSide else {
            leaves.append(r)
            return
        }
        let cut = rng.int(4...(length - 5))
        if vertical {
            let sx = r.x + cut
            for y in r.y..<(r.y + r.h) { map[x: sx, y: y] = .road }
            subdivide(BlockRect(x: r.x, y: r.y, w: cut, h: r.h), map: &map, rng: &rng, into: &leaves)
            subdivide(BlockRect(x: sx + 1, y: r.y, w: r.w - cut - 1, h: r.h), map: &map, rng: &rng, into: &leaves)
        } else {
            let sy = r.y + cut
            for x in r.x..<(r.x + r.w) { map[x: x, y: sy] = .road }
            subdivide(BlockRect(x: r.x, y: r.y, w: r.w, h: cut), map: &map, rng: &rng, into: &leaves)
            subdivide(BlockRect(x: r.x, y: sy + 1, w: r.w, h: r.h - cut - 1), map: &map, rng: &rng, into: &leaves)
        }
    }

    /// Cuts a leaf block into strips across its short side (split in two when deep),
    /// occasionally leaving a 1-wide alley between strips. Every lot touches a street.
    static func fillLots(_ r: BlockRect, map: inout TileMap, buildings: inout [Building], rng: inout SeededRandom) {
        let alongX = r.w >= r.h
        let length = alongX ? r.w : r.h
        let depth = alongX ? r.h : r.w
        let halves: [(start: Int, size: Int)] = depth >= 6 ? [(0, depth / 2), (depth / 2, depth - depth / 2)] : [(0, depth)]
        var offset = 0
        while offset < length {
            let remaining = length - offset
            var stripWidth = min(rng.int(2...4), remaining)
            if remaining - stripWidth == 1 { stripWidth += 1 }
            for half in halves {
                let lot = alongX
                    ? BlockRect(x: r.x + offset, y: r.y + half.start, w: stripWidth, h: half.size)
                    : BlockRect(x: r.x + half.start, y: r.y + offset, w: half.size, h: stripWidth)
                placeLot(lot, map: &map, buildings: &buildings, rng: &rng)
            }
            offset += stripWidth
            if offset < length - 3 && rng.chance(0.15) {
                for d in 0..<depth {
                    let p = alongX ? GridPoint(r.x + offset, r.y + d) : GridPoint(r.x + d, r.y + offset)
                    if map[p] == .park { map[p] = .road }
                }
                offset += 1
            }
        }
    }

    static func placeLot(_ lot: BlockRect, map: inout TileMap, buildings: inout [Building], rng: inout SeededRandom) {
        let points = lot.points.filter { map[$0] == .park }
        guard !points.isEmpty else { return }
        let roll = rng.double()
        if roll < 0.07 { return }   // park
        if roll < 0.12 { points.forEach { map[$0] = .crater }; return }
        if roll < 0.20 { points.forEach { map[$0] = .rubble }; return }
        guard points.count == lot.w * lot.h else { return }   // clipped by the base: leave as park
        let id = buildings.count
        points.forEach { map[$0] = .building(id) }
        buildings.append(Building(id: id, tiles: points))
    }

    static func weightedIndex(_ weights: [Double], total: Double, rng: inout SeededRandom) -> Int {
        var roll = Double.random(in: 0..<total, using: &rng)
        for (index, weight) in weights.enumerated() {
            if roll < weight { return index }
            roll -= weight
        }
        return weights.count - 1
    }
}
