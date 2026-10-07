# Tanks of Doom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS top-down tank shooter in Swift/SpriteKit with endless procedurally generated city levels.

**Architecture:** A Swift package with a pure-logic library `TanksCore` (seeded city generation, pathfinding, line of sight, combat/fuel rules, AI state machines — fully unit tested) and an executable `TanksOfDoom` (AppKit window + SpriteKit scenes, nodes, HUD, effects, synthesized audio). The app asks the core for decisions; all art and sound are generated in code.

**Tech Stack:** Swift 6 toolchain (language mode 5), Swift Package Manager, SpriteKit, AppKit, AVFoundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-07-tanks-of-doom-design.md`

## Global Constraints

- macOS 14+ (`platforms: [.macOS(.v14)]`); build with `swift build`, run with `swift run TanksOfDoom`, test with `swift test`.
- No Xcode project, no external asset files, no third-party dependencies.
- `TanksCore` imports Foundation only — never SpriteKit/AppKit.
- Tile size 64 pt; map 80×80 tiles; grid y axis points up (row 0 at the bottom), matching SpriteKit.
- Player: armor 100, fuel 100, 20 shells, 300 MG rounds; main gun 1.2 s reload with splash; MG hurts infantry only.
- Rubble/craters: passable at 50% speed, do not block line of sight. Standing buildings block movement and sight.
- Controls: W/S drive, A/D turn (arrow keys also work), mouse aims, left click main gun, right click/Space MG, Esc pause, M minimap size, R abandon tank (only at 0 fuel).
- Commit after every task; commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Stranded with zero fuel far from base** — the player must never be soft-locked: HUD says so and R ends the run (Task 14, Step 4 verification).
2. **Window resized, including larger than the 5120 pt map** — HUD re-anchors to the new corners and the camera centres the map instead of showing past its edge (Task 9 Step 7 and Task 13 Step 5 verification).
3. **Enemy tank blocked by another tank or a corner** — it must reverse and re-route within ~2 s rather than grind in place forever (Task 11 Step 5 verification).
4. **Frame hitch / fast projectiles vs. 2-tile-thick buildings** — shells must never tunnel through a building (dt clamp + 16 pt sub-steps; Task 10 Step 6 verification).
5. **Building collapses while its infantry are exposed or mid-burst** — the occupants die immediately, fire no further shots, and in-flight projectiles carry on harmlessly (Task 12 Step 4 verification).

---

## File Structure

```
Package.swift
Sources/TanksCore/
  SeededRandom.swift      deterministic RNG + GridPoint
  Tile.swift              tile kinds and their movement/sight rules
  TileMap.swift           grid storage, flood fill, world<->grid geometry, circle collision
  Pathfinder.swift        A* (8-way, no corner cutting) + MinHeap
  LineOfSight.swift       grid raycast
  Level.swift             Building, GridRect, spawns, caches, Level (+ building damage)
  Difficulty.swift        level number -> tuning numbers
  CityGenerator.swift     procedural city
  Combat.swift            weapon specs, damage rules
  TankStats.swift         armor/fuel/ammo rules
  EnemyTankBrain.swift    patrol/attack/search/retreat state machine
  InfantryBrain.swift     hidden/exposed state machine
Tests/TanksCoreTests/
  BasicsTests.swift, TileMapTests.swift, NavigationTests.swift, LevelTests.swift,
  CityGeneratorTests.swift, CombatTests.swift, BrainTests.swift
Sources/TanksOfDoom/
  main.swift, AppDelegate.swift, GameView.swift
  Geometry.swift          CGPoint math, angle helpers, z-order constants, core<->CG bridges
  RunStats.swift          per-run stats + HighScores (UserDefaults)
  MenuScene.swift         title / level complete / game over screens
  Textures.swift          procedural art
  Audio.swift             synthesized sound effects
  Effects.swift           explosions, sparks, tracks, floating text
  WorldRenderer.swift     ground tile map + building sprites
  Tanks.swift             TankNode, PlayerTank
  Pickups.swift           PickupNode
  InputState.swift
  GameScene.swift         scene state, setup, main loop, camera
  GameScene+Input.swift, GameScene+Player.swift, GameScene+Combat.swift,
  GameScene+Enemies.swift, GameScene+Infantry.swift, GameScene+HUD.swift, GameScene+Flow.swift
  Projectile.swift        Projectile, MortarShell, Hostile protocol
  EnemyTank.swift
  InfantryNode.swift
  HUD.swift, Minimap.swift
```

---

### Task 1: Package scaffold, SeededRandom, GridPoint

**Files:**
- Create: `Package.swift`, `Sources/TanksCore/SeededRandom.swift`
- Test: `Tests/TanksCoreTests/BasicsTests.swift`

**Interfaces:**
- Produces: `struct GridPoint: Hashable { var x, y: Int; init(_ x: Int, _ y: Int); func distance(to: GridPoint) -> Double }`; `struct SeededRandom: RandomNumberGenerator { init(seed: UInt64); mutating func int(_ ClosedRange<Int>) -> Int; mutating func double() -> Double; mutating func chance(_ p: Double) -> Bool }`

- [ ] **Step 1: Create the package manifest**

`Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TanksOfDoom",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TanksCore"),
        .testTarget(name: "TanksCoreTests", dependencies: ["TanksCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Write the failing tests**

`Tests/TanksCoreTests/BasicsTests.swift`:
```swift
import Testing
@testable import TanksCore

@Test func seededRandomIsDeterministic() {
    var a = SeededRandom(seed: 42)
    var b = SeededRandom(seed: 42)
    for _ in 0..<100 { #expect(a.next() == b.next()) }
}

@Test func seededRandomDiffersBySeed() {
    var a = SeededRandom(seed: 1)
    var b = SeededRandom(seed: 2)
    let first = (0..<10).map { _ in a.next() }
    let second = (0..<10).map { _ in b.next() }
    #expect(first != second)
}

@Test func seededRandomHelpersStayInRange() {
    var rng = SeededRandom(seed: 7)
    for _ in 0..<1000 {
        #expect((3...9).contains(rng.int(3...9)))
        let d = rng.double()
        #expect(d >= 0 && d < 1)
    }
    #expect(!rng.chance(0))
    #expect(rng.chance(1))
}

@Test func gridPointDistance() {
    #expect(GridPoint(0, 0).distance(to: GridPoint(3, 4)) == 5)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test`
Expected: build failure — `cannot find 'SeededRandom' in scope`.

- [ ] **Step 4: Implement**

`Sources/TanksCore/SeededRandom.swift`:
```swift
import Foundation

/// A tile coordinate. Row 0 is the bottom of the map.
public struct GridPoint: Hashable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public var description: String { "(\(x),\(y))" }

    public func distance(to other: GridPoint) -> Double {
        let dx = Double(x - other.x)
        let dy = Double(y - other.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Deterministic SplitMix64 generator so a seed always produces the same city.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    public mutating func double() -> Double {
        Double.random(in: 0..<1, using: &self)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        double() < probability
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: 4 tests passed.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat(core): package scaffold, seeded RNG and grid points

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Tiles, TileMap and world geometry

**Files:**
- Create: `Sources/TanksCore/Tile.swift`, `Sources/TanksCore/TileMap.swift`
- Test: `Tests/TanksCoreTests/TileMapTests.swift`

**Interfaces:**
- Consumes: `GridPoint`
- Produces:
  - `enum Tile: Equatable { case wall, road, building(Int), rubble, park, crater, base }` with `isPassable: Bool`, `moveCost: Int?` (nil = impassable, 2 for rubble/crater), `speedMultiplier: Double`, `blocksSight: Bool`, `buildingID: Int?`
  - `struct WorldPoint: Equatable { var x, y: Double; init(_ x: Double, _ y: Double) }`
  - `struct TileMap: Equatable` — `static let tileSize = 64.0`, `init(width:height:fill:)`, `width`, `height`, `contains(_:)`, `subscript(GridPoint) -> Tile` (out of bounds reads `.wall`, writes ignored), `subscript(x:y:)`, `neighbors4(of:)`, `allPoints`, `points(where:)`, `reachable(from:) -> Set<GridPoint>`, `gridPoint(at: WorldPoint)`, `worldCenter(of: GridPoint) -> WorldPoint`, `canOccupy(_ center: WorldPoint, radius: Double) -> Bool`, `speedMultiplier(at: WorldPoint) -> Double`

- [ ] **Step 1: Write the failing tests**

`Tests/TanksCoreTests/TileMapTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: build failure — `cannot find 'Tile' in scope`.

- [ ] **Step 3: Implement**

`Sources/TanksCore/Tile.swift`:
```swift
import Foundation

public enum Tile: Equatable, Sendable {
    case wall
    case road
    case building(Int)
    case rubble
    case park
    case crater
    case base

    public var isPassable: Bool {
        switch self {
        case .wall, .building: return false
        default: return true
        }
    }

    /// Relative cost of crossing this tile for pathfinding; nil when impassable.
    public var moveCost: Int? {
        switch self {
        case .wall, .building: return nil
        case .rubble, .crater: return 2
        default: return 1
        }
    }

    /// Vehicle speed multiplier while on this tile.
    public var speedMultiplier: Double { moveCost == 2 ? 0.5 : 1.0 }

    public var blocksSight: Bool { !isPassable }

    public var buildingID: Int? {
        if case .building(let id) = self { return id }
        return nil
    }
}
```

`Sources/TanksCore/TileMap.swift`:
```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass (10 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksCore Tests/TanksCoreTests
git commit -m "feat(core): tile map with flood fill and circle collision

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Pathfinder and line of sight

**Files:**
- Create: `Sources/TanksCore/Pathfinder.swift`, `Sources/TanksCore/LineOfSight.swift`
- Test: `Tests/TanksCoreTests/NavigationTests.swift`

**Interfaces:**
- Consumes: `TileMap`, `Tile.moveCost`, `Tile.blocksSight`, `Tile.buildingID`
- Produces: `Pathfinder.findPath(in: TileMap, from: GridPoint, to: GridPoint) -> [GridPoint]?` (includes start and goal; nil if either end is impassable or unreachable); `LineOfSight.isClear(in: TileMap, from: GridPoint, to: GridPoint, ignoringBuilding: Int? = nil) -> Bool` (endpoints never block)

- [ ] **Step 1: Write the failing tests**

`Tests/TanksCoreTests/NavigationTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: build failure — `cannot find 'Pathfinder' in scope`.

- [ ] **Step 3: Implement**

`Sources/TanksCore/Pathfinder.swift`:
```swift
import Foundation

/// A* over the tile grid: 8-way movement, no diagonal corner cutting, rubble costs double.
public enum Pathfinder {
    private static let directions = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]

    public static func findPath(in map: TileMap, from start: GridPoint, to goal: GridPoint) -> [GridPoint]? {
        guard map[start].isPassable, map[goal].isPassable else { return nil }
        if start == goal { return [start] }

        var open = MinHeap()
        var closed: Set<GridPoint> = []
        var cameFrom: [GridPoint: GridPoint] = [:]
        var cost: [GridPoint: Int] = [start: 0]
        open.push(start, priority: heuristic(start, goal))

        while let current = open.pop() {
            if current == goal { return reconstruct(cameFrom, to: goal) }
            if closed.contains(current) { continue }
            closed.insert(current)
            let currentCost = cost[current]!

            for (dx, dy) in directions {
                let next = GridPoint(current.x + dx, current.y + dy)
                guard let tileCost = map[next].moveCost, !closed.contains(next) else { continue }
                let diagonal = dx != 0 && dy != 0
                if diagonal && (!map[x: current.x + dx, y: current.y].isPassable || !map[x: current.x, y: current.y + dy].isPassable) {
                    continue
                }
                let tentative = currentCost + (diagonal ? 14 : 10) * tileCost
                if tentative < cost[next, default: .max] {
                    cost[next] = tentative
                    cameFrom[next] = current
                    open.push(next, priority: tentative + heuristic(next, goal))
                }
            }
        }
        return nil
    }

    /// Octile distance in the same units as step costs.
    static func heuristic(_ a: GridPoint, _ b: GridPoint) -> Int {
        let dx = abs(a.x - b.x)
        let dy = abs(a.y - b.y)
        return 10 * (dx + dy) - 6 * min(dx, dy)
    }

    private static func reconstruct(_ cameFrom: [GridPoint: GridPoint], to goal: GridPoint) -> [GridPoint] {
        var path = [goal]
        var current = goal
        while let previous = cameFrom[current] {
            path.append(previous)
            current = previous
        }
        return path.reversed()
    }
}

/// Binary min-heap keyed by integer priority.
struct MinHeap {
    private var items: [(point: GridPoint, priority: Int)] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func push(_ point: GridPoint, priority: Int) {
        items.append((point, priority))
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].priority < items[parent].priority else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> GridPoint? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < items.count && items[left].priority < items[smallest].priority { smallest = left }
            if right < items.count && items[right].priority < items[smallest].priority { smallest = right }
            if smallest == parent { break }
            items.swapAt(parent, smallest)
            parent = smallest
        }
        return top.point
    }
}
```

`Sources/TanksCore/LineOfSight.swift`:
```swift
import Foundation

public enum LineOfSight {
    /// Bresenham walk between two tiles. The endpoints never block, and tiles of
    /// `ignoringBuilding` never block (so a soldier can see out of their own building).
    public static func isClear(in map: TileMap, from a: GridPoint, to b: GridPoint, ignoringBuilding: Int? = nil) -> Bool {
        var x = a.x
        var y = a.y
        let dx = abs(b.x - a.x)
        let dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1
        let sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        while !(x == b.x && y == b.y) {
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
            if x == b.x && y == b.y { break }
            let tile = map[x: x, y: y]
            if tile.blocksSight && (tile.buildingID == nil || tile.buildingID != ignoringBuilding) {
                return false
            }
        }
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksCore Tests/TanksCoreTests
git commit -m "feat(core): A* pathfinding and line of sight

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Level model and difficulty

**Files:**
- Create: `Sources/TanksCore/Level.swift`, `Sources/TanksCore/Difficulty.swift`
- Test: `Tests/TanksCoreTests/LevelTests.swift`

**Interfaces:**
- Consumes: `TileMap`, `GridPoint`, `SeededRandom`
- Produces:
  - `struct GridRect: Equatable { minX, minY, width, height: Int }`
  - `struct Building: Equatable { id: Int; tiles: [GridPoint]; rect: GridRect; maxHP: Int; hp: Int; isDestroyed: Bool; damageStage: Int /*0 intact,1 cracked,2 heavy,3 destroyed*/; static func hitPoints(forArea:) -> Int; init(id:tiles:) }`
  - `enum InfantryKind: CaseIterable { case rifleman, machineGunner, bazooka, mortar }`
  - `struct InfantrySpawn: Equatable { kind: InfantryKind; buildingID: Int }`
  - `enum CacheKind { case gas, ammo }`, `struct Cache: Equatable { kind: CacheKind; position: GridPoint }`
  - `struct EnemyTankSpawn: Equatable { position: GridPoint; patrol: [GridPoint] }`
  - `enum BuildingHitResult: Equatable { case none, damaged(stage: Int), destroyed }`
  - `struct Level { number, seed, map, buildings, baseTiles, baseCenter, caches, infantry, enemyTanks; func isBase(_:) -> Bool; mutating func damageBuilding(_ id: Int, by: Int) -> BuildingHitResult }` with a public memberwise-style `init(number:seed:map:buildings:baseTiles:baseCenter:caches:infantry:enemyTanks:)`
  - `struct Difficulty { level; enemyTankCount; enemyTankArmor; enemyTankSpeed; enemyReactionTime; infantryChance; gasCacheCount; ammoCacheCount; infantryWeights(); randomInfantryKind(using: inout SeededRandom) }`

- [ ] **Step 1: Write the failing tests**

`Tests/TanksCoreTests/LevelTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: build failure — `cannot find 'Level' in scope`.

- [ ] **Step 3: Implement**

`Sources/TanksCore/Level.swift`:
```swift
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
```

`Sources/TanksCore/Difficulty.swift`:
```swift
import Foundation

/// Tuning numbers for a level. Everything ramps up with the level number and is capped.
public struct Difficulty: Sendable {
    public let level: Int

    public init(level: Int) {
        self.level = max(1, level)
    }

    private var step: Double { Double(level - 1) }

    public var enemyTankCount: Int { min(2 + level, 10) }
    public var enemyTankArmor: Int { min(60 + 15 * (level - 1), 200) }
    /// Points per second.
    public var enemyTankSpeed: Double { min(90 + 6 * step, 150) }
    /// Seconds an enemy tank waits after spotting the player before its first shot.
    public var enemyReactionTime: Double { max(1.2 - 0.1 * step, 0.3) }
    /// Probability that a building is occupied.
    public var infantryChance: Double { min(0.25 + 0.04 * step, 0.6) }
    public var gasCacheCount: Int { max(4, 7 - level / 3) }
    public var ammoCacheCount: Int { max(4, 7 - level / 3) }

    public func infantryWeights() -> [(kind: InfantryKind, weight: Double)] {
        [
            (.rifleman, max(1, 6 - step)),
            (.machineGunner, 2 + step * 0.5),
            (.bazooka, 1 + step * 0.6),
            (.mortar, level >= 2 ? 0.5 + step * 0.4 : 0),
        ]
    }

    public func randomInfantryKind(using rng: inout SeededRandom) -> InfantryKind {
        let weights = infantryWeights()
        let total = weights.reduce(0) { $0 + $1.weight }
        var roll = Double.random(in: 0..<total, using: &rng)
        for entry in weights {
            if roll < entry.weight { return entry.kind }
            roll -= entry.weight
        }
        return .rifleman
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksCore Tests/TanksCoreTests
git commit -m "feat(core): level model, building damage and difficulty curve

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: City generator

**Files:**
- Create: `Sources/TanksCore/CityGenerator.swift`
- Test: `Tests/TanksCoreTests/CityGeneratorTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–4
- Produces: `CityGenerator.generate(seed: UInt64, level: Int) -> Level`; constants `CityGenerator.mapSize = 80`, `minTankDistanceFromBase = 30.0`, `safeZoneRadius = 10.0`. Base occupies tiles x,y ∈ 3...8 (36 tiles), `baseCenter == GridPoint(6, 6)`. `buildings[i].id == i`.

- [ ] **Step 1: Write the failing tests**

`Tests/TanksCoreTests/CityGeneratorTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: build failure — `cannot find 'CityGenerator' in scope`.

- [ ] **Step 3: Implement**

`Sources/TanksCore/CityGenerator.swift`:
```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass. If `citiesMatchDifficulty` fails on `!city.infantry.isEmpty` for some seed at level 1, that is a real tuning bug — report it rather than deleting the assertion.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksCore Tests/TanksCoreTests
git commit -m "feat(core): procedural city generator

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Combat rules and tank stats

**Files:**
- Create: `Sources/TanksCore/Combat.swift`, `Sources/TanksCore/TankStats.swift`
- Test: `Tests/TanksCoreTests/CombatTests.swift`

**Interfaces:**
- Consumes: `InfantryKind`, `CacheKind`
- Produces:
  - `enum WeaponKind: CaseIterable { case mainGun, machineGun, enemyShell, rifle, enemyMachineGun, bazooka, mortar }`
  - `enum TargetKind: Hashable { case tank, infantry, building }` (enemy weapons list `.tank` = the player's tank)
  - `struct WeaponSpec { damage: Int; splashRadius: Double; reload: Double; projectileSpeed: Double; range: Double; targets: Set<TargetKind> }`
  - `Combat.spec(_ WeaponKind) -> WeaponSpec`, `Combat.damage(_ WeaponKind, to: TargetKind, distance: Double) -> Int` (distance 0 = direct hit; linear splash falloff)
  - `InfantryKind.weapon: WeaponKind`
  - `struct TankStats: Equatable` — statics `maxArmor (Double 100)`, `maxFuel (100)`, `maxShells (20)`, `maxRounds (300)`, `fuelPerSecondMoving 0.9`, `fuelPerSecondIdle 0.1`, `baseRepairPerSecond 8`, `baseMinFuel 50`, `baseMinShells 8`, `baseMinRounds 150`, `gasCacheFuel 45`, `ammoCacheShells 8`, `ammoCacheRounds 120`; vars `armor: Double`, `fuel: Double`, `shells: Int`, `rounds: Int`; `canMove`, `isDestroyed`, `burnFuel(seconds:moving:)`, `takeDamage(_ Int)`, `consumeShell() -> Bool`, `consumeRound() -> Bool`, `applyBase(seconds:)`, `collect(_ CacheKind)`

- [ ] **Step 1: Write the failing tests**

`Tests/TanksCoreTests/CombatTests.swift`:
```swift
import Testing
@testable import TanksCore

@Test func machineGunOnlyHurtsInfantry() {
    #expect(Combat.damage(.machineGun, to: .infantry, distance: 0) == 4)
    #expect(Combat.damage(.machineGun, to: .tank, distance: 0) == 0)
    #expect(Combat.damage(.machineGun, to: .building, distance: 0) == 0)
}

@Test func mainGunHurtsEverythingWithSplashFalloff() {
    let spec = Combat.spec(.mainGun)
    #expect(Combat.damage(.mainGun, to: .tank, distance: 0) == 40)
    #expect(Combat.damage(.mainGun, to: .building, distance: 0) == 40)
    #expect(Combat.damage(.mainGun, to: .infantry, distance: spec.splashRadius / 2) == 20)
    #expect(Combat.damage(.mainGun, to: .tank, distance: spec.splashRadius) == 0)
    #expect(Combat.damage(.mainGun, to: .tank, distance: spec.splashRadius + 50) == 0)
}

@Test func enemyWeaponsOnlyHurtThePlayer() {
    for weapon in [WeaponKind.enemyShell, .rifle, .enemyMachineGun, .bazooka, .mortar] {
        #expect(Combat.damage(weapon, to: .tank, distance: 0) > 0)
        #expect(Combat.damage(weapon, to: .building, distance: 0) == 0)
        #expect(Combat.damage(weapon, to: .infantry, distance: 0) == 0)
    }
}

@Test func bazookaIsSlowAndHeavy() {
    #expect(Combat.spec(.bazooka).projectileSpeed < Combat.spec(.rifle).projectileSpeed)
    #expect(Combat.spec(.bazooka).damage > Combat.spec(.rifle).damage)
    #expect(Combat.spec(.mainGun).reload == 1.2)
}

@Test func infantryWeapons() {
    #expect(InfantryKind.rifleman.weapon == .rifle)
    #expect(InfantryKind.machineGunner.weapon == .enemyMachineGun)
    #expect(InfantryKind.bazooka.weapon == .bazooka)
    #expect(InfantryKind.mortar.weapon == .mortar)
}

@Test func freshTankIsFullyStocked() {
    let stats = TankStats()
    #expect(stats.armor == 100 && stats.fuel == 100 && stats.shells == 20 && stats.rounds == 300)
    #expect(stats.canMove && !stats.isDestroyed)
}

@Test func fuelBurnsFasterWhileMovingAndStopsAtZero() {
    var moving = TankStats()
    var idle = TankStats()
    moving.burnFuel(seconds: 10, moving: true)
    idle.burnFuel(seconds: 10, moving: false)
    #expect(moving.fuel < idle.fuel)
    moving.burnFuel(seconds: 10_000, moving: true)
    #expect(moving.fuel == 0)
    #expect(!moving.canMove)
}

@Test func ammoRunsOut() {
    var stats = TankStats()
    stats.shells = 1
    #expect(stats.consumeShell())
    #expect(!stats.consumeShell())
    #expect(stats.shells == 0)
    stats.rounds = 0
    #expect(!stats.consumeRound())
}

@Test func damageDestroysAtZeroArmor() {
    var stats = TankStats()
    stats.takeDamage(60)
    #expect(stats.armor == 40)
    stats.takeDamage(60)
    #expect(stats.armor == 0)
    #expect(stats.isDestroyed)
}

@Test func baseRepairsAndTopsUpToMinimumsOnly() {
    var low = TankStats()
    low.armor = 50; low.fuel = 5; low.shells = 0; low.rounds = 10
    low.applyBase(seconds: 1)
    #expect(low.armor == 58)
    #expect(low.fuel == TankStats.baseMinFuel)
    #expect(low.shells == TankStats.baseMinShells)
    #expect(low.rounds == TankStats.baseMinRounds)
    low.applyBase(seconds: 100)
    #expect(low.armor == 100)

    var full = TankStats()
    full.applyBase(seconds: 1)
    #expect(full == TankStats())   // never reduces anything
}

@Test func cachesRefillUpToMaximum() {
    var stats = TankStats()
    stats.fuel = 10; stats.shells = 2; stats.rounds = 0
    stats.collect(.gas)
    #expect(stats.fuel == 55)
    stats.collect(.ammo)
    #expect(stats.shells == 10 && stats.rounds == 120)
    stats.collect(.gas); stats.collect(.gas)
    #expect(stats.fuel == TankStats.maxFuel)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: build failure — `cannot find 'Combat' in scope`.

- [ ] **Step 3: Implement**

`Sources/TanksCore/Combat.swift`:
```swift
import Foundation

public enum WeaponKind: CaseIterable, Sendable {
    case mainGun, machineGun, enemyShell, rifle, enemyMachineGun, bazooka, mortar
}

/// What a weapon can hurt. For enemy weapons `.tank` means the player's tank.
public enum TargetKind: Hashable, Sendable {
    case tank, infantry, building
}

public struct WeaponSpec: Sendable {
    public let damage: Int
    /// Points; 0 means no splash.
    public let splashRadius: Double
    /// Seconds between shots.
    public let reload: Double
    /// Points per second (mortars fly a fixed-time arc instead).
    public let projectileSpeed: Double
    /// Points.
    public let range: Double
    public let targets: Set<TargetKind>
}

public enum Combat {
    public static func spec(_ weapon: WeaponKind) -> WeaponSpec {
        switch weapon {
        case .mainGun:
            return WeaponSpec(damage: 40, splashRadius: 70, reload: 1.2, projectileSpeed: 750, range: 750, targets: [.tank, .infantry, .building])
        case .machineGun:
            return WeaponSpec(damage: 4, splashRadius: 0, reload: 0.08, projectileSpeed: 1100, range: 550, targets: [.infantry])
        case .enemyShell:
            return WeaponSpec(damage: 12, splashRadius: 50, reload: 2.5, projectileSpeed: 550, range: 560, targets: [.tank])
        case .rifle:
            return WeaponSpec(damage: 2, splashRadius: 0, reload: 1.0, projectileSpeed: 800, range: 480, targets: [.tank])
        case .enemyMachineGun:
            return WeaponSpec(damage: 1, splashRadius: 0, reload: 0.12, projectileSpeed: 800, range: 420, targets: [.tank])
        case .bazooka:
            return WeaponSpec(damage: 18, splashRadius: 30, reload: 4.0, projectileSpeed: 260, range: 520, targets: [.tank])
        case .mortar:
            return WeaponSpec(damage: 20, splashRadius: 60, reload: 6.0, projectileSpeed: 0, range: 640, targets: [.tank])
        }
    }

    /// Damage dealt to a target `distance` points from the impact (0 = direct hit).
    public static func damage(_ weapon: WeaponKind, to target: TargetKind, distance: Double) -> Int {
        let s = spec(weapon)
        guard s.targets.contains(target) else { return 0 }
        if distance <= 0 { return s.damage }
        guard s.splashRadius > 0, distance < s.splashRadius else { return 0 }
        return Int((Double(s.damage) * (1 - distance / s.splashRadius)).rounded())
    }
}

extension InfantryKind {
    public var weapon: WeaponKind {
        switch self {
        case .rifleman: return .rifle
        case .machineGunner: return .enemyMachineGun
        case .bazooka: return .bazooka
        case .mortar: return .mortar
        }
    }
}
```

`Sources/TanksCore/TankStats.swift`:
```swift
import Foundation

/// The player's armor, fuel and ammunition, and the rules for spending and restoring them.
public struct TankStats: Equatable, Sendable {
    public static let maxArmor = 100.0
    public static let maxFuel = 100.0
    public static let maxShells = 20
    public static let maxRounds = 300
    public static let fuelPerSecondMoving = 0.9
    public static let fuelPerSecondIdle = 0.1
    public static let baseRepairPerSecond = 8.0
    public static let baseMinFuel = 50.0
    public static let baseMinShells = 8
    public static let baseMinRounds = 150
    public static let gasCacheFuel = 45.0
    public static let ammoCacheShells = 8
    public static let ammoCacheRounds = 120

    public var armor: Double = TankStats.maxArmor
    public var fuel: Double = TankStats.maxFuel
    public var shells: Int = TankStats.maxShells
    public var rounds: Int = TankStats.maxRounds

    public init() {}

    public var canMove: Bool { fuel > 0 }
    public var isDestroyed: Bool { armor <= 0 }

    public mutating func burnFuel(seconds: Double, moving: Bool) {
        let rate = moving ? Self.fuelPerSecondMoving : Self.fuelPerSecondIdle
        fuel = max(0, fuel - seconds * rate)
    }

    public mutating func takeDamage(_ amount: Int) {
        armor = max(0, armor - Double(amount))
    }

    public mutating func consumeShell() -> Bool {
        guard shells > 0 else { return false }
        shells -= 1
        return true
    }

    public mutating func consumeRound() -> Bool {
        guard rounds > 0 else { return false }
        rounds -= 1
        return true
    }

    /// While parked at base: armor repairs gradually; fuel and ammo jump to the base minimums.
    public mutating func applyBase(seconds: Double) {
        armor = min(Self.maxArmor, armor + Self.baseRepairPerSecond * seconds)
        fuel = max(fuel, Self.baseMinFuel)
        shells = max(shells, Self.baseMinShells)
        rounds = max(rounds, Self.baseMinRounds)
    }

    public mutating func collect(_ kind: CacheKind) {
        switch kind {
        case .gas:
            fuel = min(Self.maxFuel, fuel + Self.gasCacheFuel)
        case .ammo:
            shells = min(Self.maxShells, shells + Self.ammoCacheShells)
            rounds = min(Self.maxRounds, rounds + Self.ammoCacheRounds)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksCore Tests/TanksCoreTests
git commit -m "feat(core): weapon specs, damage rules and tank stats

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: AI brains

**Files:**
- Create: `Sources/TanksCore/EnemyTankBrain.swift`, `Sources/TanksCore/InfantryBrain.swift`
- Test: `Tests/TanksCoreTests/BrainTests.swift`

**Interfaces:**
- Consumes: `InfantryKind.weapon`, `Combat.spec`
- Produces:
  - `enum EnemyTankState { case patrol, attack, search, retreat }`
  - `struct EnemyPerception { canSeePlayer: Bool; distanceToPlayer: Double; armorFraction: Double; reachedSearchPoint: Bool; init(...) }`
  - `struct EnemyTankBrain { static sightRange = 560, retreatArmorFraction = 0.25, searchTimeout = 8, retreatDuration = 6; state; timeInState; init(); @discardableResult mutating func update(_ EnemyPerception, dt: Double) -> EnemyTankState }`
  - `enum InfantryState { case hidden, exposed }`, `enum InfantryEvent { case expose, hide }`
  - `struct InfantryBrain { kind; state; timer; init(kind:initialDelay:); range; exposedDuration; hiddenDuration; needsLineOfSight; mutating func update(dt:playerVisible:distance:) -> InfantryEvent? }`

- [ ] **Step 1: Write the failing tests**

`Tests/TanksCoreTests/BrainTests.swift`:
```swift
import Testing
@testable import TanksCore

private func seeing(_ distance: Double = 300, armor: Double = 1) -> EnemyPerception {
    EnemyPerception(canSeePlayer: true, distanceToPlayer: distance, armorFraction: armor, reachedSearchPoint: false)
}

private func blind(armor: Double = 1, reached: Bool = false) -> EnemyPerception {
    EnemyPerception(canSeePlayer: false, distanceToPlayer: 2000, armorFraction: armor, reachedSearchPoint: reached)
}

@Test func tankPatrolsUntilPlayerSeen() {
    var brain = EnemyTankBrain()
    #expect(brain.update(blind(), dt: 1) == .patrol)
    #expect(brain.update(seeing(), dt: 0.1) == .attack)
}

@Test func tankIgnoresPlayerBeyondSightRange() {
    var brain = EnemyTankBrain()
    #expect(brain.update(seeing(EnemyTankBrain.sightRange + 1), dt: 0.1) == .patrol)
}

@Test func tankSearchesLastKnownPositionThenPatrols() {
    var brain = EnemyTankBrain()
    brain.update(seeing(), dt: 0.1)
    #expect(brain.update(blind(), dt: 0.1) == .search)
    #expect(brain.update(blind(), dt: 0.1) == .search)
    #expect(brain.update(blind(reached: true), dt: 0.1) == .patrol)
}

@Test func tankSearchTimesOut() {
    var brain = EnemyTankBrain()
    brain.update(seeing(), dt: 0.1)
    brain.update(blind(), dt: 0.1)
    #expect(brain.update(blind(), dt: EnemyTankBrain.searchTimeout) == .patrol)
}

@Test func tankReacquiresDuringSearch() {
    var brain = EnemyTankBrain()
    brain.update(seeing(), dt: 0.1)
    brain.update(blind(), dt: 0.1)
    #expect(brain.update(seeing(), dt: 0.1) == .attack)
}

@Test func badlyDamagedTankRetreatsThenRecovers() {
    var brain = EnemyTankBrain()
    brain.update(seeing(), dt: 0.1)
    #expect(brain.update(seeing(armor: 0.2), dt: 0.1) == .retreat)
    #expect(brain.update(seeing(armor: 0.2), dt: 10) == .retreat)   // still sees the player
    #expect(brain.update(blind(armor: 0.2), dt: EnemyTankBrain.retreatDuration) == .patrol)
    #expect(brain.update(seeing(armor: 0.2), dt: 0.1) == .retreat)
}

@Test func timeInStateResetsOnTransition() {
    var brain = EnemyTankBrain()
    brain.update(blind(), dt: 3)
    #expect(brain.timeInState == 3)
    brain.update(seeing(), dt: 0.1)
    #expect(brain.timeInState == 0)
    brain.update(seeing(), dt: 0.5)
    #expect(brain.timeInState == 0.5)
}

@Test func infantryWaitsForInitialDelay() {
    var brain = InfantryBrain(kind: .rifleman, initialDelay: 1)
    #expect(brain.update(dt: 0.5, playerVisible: true, distance: 100) == nil)
    #expect(brain.update(dt: 0.6, playerVisible: true, distance: 100) == .expose)
    #expect(brain.state == .exposed)
}

@Test func infantryStaysHiddenWithoutSightOrOutOfRange() {
    var brain = InfantryBrain(kind: .rifleman, initialDelay: 0)
    #expect(brain.update(dt: 0.1, playerVisible: false, distance: 100) == nil)
    #expect(brain.update(dt: 0.1, playerVisible: true, distance: brain.range + 1) == nil)
    #expect(brain.state == .hidden)
}

@Test func infantryHidesAfterExposureThenWaits() {
    var brain = InfantryBrain(kind: .bazooka, initialDelay: 0)
    #expect(brain.update(dt: 0.1, playerVisible: true, distance: 100) == .expose)
    #expect(brain.update(dt: brain.exposedDuration, playerVisible: true, distance: 100) == .hide)
    #expect(brain.state == .hidden)
    #expect(brain.update(dt: 0.1, playerVisible: true, distance: 100) == nil)
    #expect(brain.update(dt: brain.hiddenDuration, playerVisible: true, distance: 100) == .expose)
}

@Test func mortarFiresWithoutLineOfSight() {
    var brain = InfantryBrain(kind: .mortar, initialDelay: 0)
    #expect(!brain.needsLineOfSight)
    #expect(brain.update(dt: 0.1, playerVisible: false, distance: 300) == .expose)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: build failure — `cannot find 'EnemyTankBrain' in scope`.

- [ ] **Step 3: Implement**

`Sources/TanksCore/EnemyTankBrain.swift`:
```swift
import Foundation

public enum EnemyTankState: Equatable, Sendable {
    case patrol, attack, search, retreat
}

public struct EnemyPerception: Sendable {
    public var canSeePlayer: Bool
    public var distanceToPlayer: Double
    public var armorFraction: Double
    public var reachedSearchPoint: Bool

    public init(canSeePlayer: Bool, distanceToPlayer: Double, armorFraction: Double, reachedSearchPoint: Bool) {
        self.canSeePlayer = canSeePlayer
        self.distanceToPlayer = distanceToPlayer
        self.armorFraction = armorFraction
        self.reachedSearchPoint = reachedSearchPoint
    }
}

/// Decides what an enemy tank should be doing. Movement and aiming live in the app.
public struct EnemyTankBrain: Sendable {
    public static let sightRange = 560.0
    public static let retreatArmorFraction = 0.25
    public static let searchTimeout = 8.0
    public static let retreatDuration = 6.0

    public private(set) var state: EnemyTankState = .patrol
    public private(set) var timeInState: Double = 0

    public init() {}

    @discardableResult
    public mutating func update(_ p: EnemyPerception, dt: Double) -> EnemyTankState {
        timeInState += dt
        let spotted = p.canSeePlayer && p.distanceToPlayer <= Self.sightRange
        let crippled = p.armorFraction <= Self.retreatArmorFraction
        let next: EnemyTankState
        switch state {
        case .patrol:
            next = spotted ? (crippled ? .retreat : .attack) : .patrol
        case .attack:
            if crippled { next = .retreat } else { next = spotted ? .attack : .search }
        case .search:
            if spotted {
                next = crippled ? .retreat : .attack
            } else if p.reachedSearchPoint || timeInState >= Self.searchTimeout {
                next = .patrol
            } else {
                next = .search
            }
        case .retreat:
            next = (!spotted && timeInState >= Self.retreatDuration) ? .patrol : .retreat
        }
        if next != state {
            state = next
            timeInState = 0
        }
        return state
    }
}
```

`Sources/TanksCore/InfantryBrain.swift`:
```swift
import Foundation

public enum InfantryState: Equatable, Sendable {
    case hidden, exposed
}

public enum InfantryEvent: Equatable, Sendable {
    case expose, hide
}

/// Pop-up behaviour of a soldier inside a building: hide, appear at a window to fire, duck back.
public struct InfantryBrain: Sendable {
    public let kind: InfantryKind
    public private(set) var state: InfantryState = .hidden
    public private(set) var timer: Double

    public init(kind: InfantryKind, initialDelay: Double) {
        self.kind = kind
        timer = initialDelay
    }

    public var range: Double { Combat.spec(kind.weapon).range }

    public var exposedDuration: Double {
        switch kind {
        case .rifleman: return 1.8
        case .machineGunner: return 2.4
        case .bazooka: return 1.4
        case .mortar: return 1.2
        }
    }

    public var hiddenDuration: Double {
        switch kind {
        case .rifleman: return 2.0
        case .machineGunner: return 2.5
        case .bazooka: return 3.5
        case .mortar: return 5.0
        }
    }

    /// Mortars lob shells over buildings, so they only need the player in range.
    public var needsLineOfSight: Bool { kind != .mortar }

    public mutating func update(dt: Double, playerVisible: Bool, distance: Double) -> InfantryEvent? {
        timer = max(0, timer - dt)
        switch state {
        case .hidden:
            let canEngage = distance <= range && (playerVisible || !needsLineOfSight)
            guard timer <= 0, canEngage else { return nil }
            state = .exposed
            timer = exposedDuration
            return .expose
        case .exposed:
            guard timer <= 0 else { return nil }
            state = .hidden
            timer = hiddenDuration
            return .hide
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksCore Tests/TanksCoreTests
git commit -m "feat(core): enemy tank and infantry AI state machines

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: App shell — window, input forwarding, title screen

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TanksOfDoom/main.swift`, `Sources/TanksOfDoom/AppDelegate.swift`, `Sources/TanksOfDoom/GameView.swift`, `Sources/TanksOfDoom/Geometry.swift`, `Sources/TanksOfDoom/RunStats.swift`, `Sources/TanksOfDoom/MenuScene.swift`

**Interfaces:**
- Consumes: `TileMap`, `WorldPoint`, `GridPoint`, `Building.rect`
- Produces:
  - Global `let tileSize: CGFloat` (64); `enum Z` z-order constants `ground 0, tracks 1, pickups 2, tanks 5, buildings 10, infantry 11, projectiles 12, effects 20, hud 100`
  - `CGPoint` operators `+ - *(CGFloat)`, `length`, `distance(to:)`, `angle(to:)`, `init(angle:length:)`, `world: WorldPoint`; `WorldPoint.cgPoint`; `TileMap.grid(_ CGPoint) -> GridPoint`, `TileMap.center(_ GridPoint) -> CGPoint`; `Building.worldCenter: CGPoint`; `normalizeAngle(_:)`, `rotate(_:toward:maxStep:)`
  - `struct RunStats { levelsCleared, tanksDestroyed, infantryKilled: Int; kills: Int }`; `enum HighScores { bestLevels; bestKills; @discardableResult record(_ RunStats) -> Bool }`
  - `final class MenuScene: SKScene` with `struct Line(text:size:color:font:)`, `init(size:lines:prompt:onContinue:)`, `static func title(size:) -> MenuScene`
  - `SKLabelNode.make(_ text:size:color:font:) -> SKLabelNode`
  - `final class GameView: SKView` forwarding key/mouse events (incl. mouseMoved and right mouse) to `scene`

- [ ] **Step 1: Add the executable target**

Replace the `targets:` array in `Package.swift` with:
```swift
    targets: [
        .target(name: "TanksCore"),
        .executableTarget(name: "TanksOfDoom", dependencies: ["TanksCore"]),
        .testTarget(name: "TanksCoreTests", dependencies: ["TanksCore"]),
    ],
```

- [ ] **Step 2: Create the app entry point and window**

`Sources/TanksOfDoom/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
```

`Sources/TanksOfDoom/AppDelegate.swift`:
```swift
import AppKit
import SpriteKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Tanks of Doom"
        window.minSize = NSSize(width: 800, height: 500)
        window.acceptsMouseMovedEvents = true

        let view = GameView(frame: frame)
        view.ignoresSiblingOrder = true
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate()
        view.presentScene(MenuScene.title(size: frame.size))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Tanks of Doom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
```

`Sources/TanksOfDoom/GameView.swift`:
```swift
import AppKit
import SpriteKit

/// SKView that forwards every keyboard and mouse event (including mouse-moved and right
/// mouse) straight to the presented scene.
final class GameView: SKView {
    private var mouseTracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTracking { removeTrackingArea(mouseTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        mouseTracking = area
    }

    override func keyDown(with event: NSEvent) { scene?.keyDown(with: event) }
    override func keyUp(with event: NSEvent) { scene?.keyUp(with: event) }
    override func mouseDown(with event: NSEvent) { scene?.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { scene?.mouseUp(with: event) }
    override func mouseDragged(with event: NSEvent) { scene?.mouseDragged(with: event) }
    override func mouseMoved(with event: NSEvent) { scene?.mouseMoved(with: event) }
    override func rightMouseDown(with event: NSEvent) { scene?.rightMouseDown(with: event) }
    override func rightMouseUp(with event: NSEvent) { scene?.rightMouseUp(with: event) }
    override func rightMouseDragged(with event: NSEvent) { scene?.rightMouseDragged(with: event) }
}
```

- [ ] **Step 3: Geometry helpers and run stats**

`Sources/TanksOfDoom/Geometry.swift`:
```swift
import CoreGraphics
import TanksCore

let tileSize = CGFloat(TileMap.tileSize)

/// Draw order (the view ignores sibling order, so every node sets one of these).
enum Z {
    static let ground: CGFloat = 0
    static let tracks: CGFloat = 1
    static let pickups: CGFloat = 2
    static let tanks: CGFloat = 5
    static let buildings: CGFloat = 10
    static let infantry: CGFloat = 11
    static let projectiles: CGFloat = 12
    static let effects: CGFloat = 20
    static let hud: CGFloat = 100
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }

    init(angle: CGFloat, length: CGFloat) {
        self.init(x: cos(angle) * length, y: sin(angle) * length)
    }

    var length: CGFloat { hypot(x, y) }
    func distance(to other: CGPoint) -> CGFloat { hypot(other.x - x, other.y - y) }
    func angle(to other: CGPoint) -> CGFloat { atan2(other.y - y, other.x - x) }
    var world: WorldPoint { WorldPoint(Double(x), Double(y)) }
}

extension WorldPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

extension TileMap {
    func grid(_ point: CGPoint) -> GridPoint { gridPoint(at: point.world) }
    func center(_ point: GridPoint) -> CGPoint { worldCenter(of: point).cgPoint }
}

extension Building {
    var worldCenter: CGPoint {
        CGPoint(x: (CGFloat(rect.minX) + CGFloat(rect.width) / 2) * tileSize,
                y: (CGFloat(rect.minY) + CGFloat(rect.height) / 2) * tileSize)
    }
}

/// Wraps an angle into -π...π.
func normalizeAngle(_ angle: CGFloat) -> CGFloat {
    var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if a > .pi { a -= 2 * .pi }
    if a < -.pi { a += 2 * .pi }
    return a
}

/// Turns `current` toward `target` by at most `maxStep` radians.
func rotate(_ current: CGFloat, toward target: CGFloat, maxStep: CGFloat) -> CGFloat {
    let diff = normalizeAngle(target - current)
    if abs(diff) <= maxStep { return current + diff }
    return current + (diff > 0 ? maxStep : -maxStep)
}
```

`Sources/TanksOfDoom/RunStats.swift`:
```swift
import Foundation

struct RunStats {
    var levelsCleared = 0
    var tanksDestroyed = 0
    var infantryKilled = 0

    var kills: Int { tanksDestroyed + infantryKilled }
}

/// Best run, ranked by levels cleared, then kills.
enum HighScores {
    private static let defaults = UserDefaults.standard

    static var bestLevels: Int { defaults.integer(forKey: "bestLevels") }
    static var bestKills: Int { defaults.integer(forKey: "bestKills") }

    @discardableResult
    static func record(_ run: RunStats) -> Bool {
        let better = run.levelsCleared > bestLevels || (run.levelsCleared == bestLevels && run.kills > bestKills)
        if better {
            defaults.set(run.levelsCleared, forKey: "bestLevels")
            defaults.set(run.kills, forKey: "bestKills")
        }
        return better
    }
}
```

- [ ] **Step 4: Menu scene with the title screen**

`Sources/TanksOfDoom/MenuScene.swift`:
```swift
import AppKit
import SpriteKit

extension SKLabelNode {
    static func make(_ text: String, size: CGFloat, color: NSColor = .white, font: String = "Impact") -> SKLabelNode {
        let label = SKLabelNode(fontNamed: font)
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }
}

/// A centred stack of text lines plus a blinking prompt; Enter, Space or a click continues.
final class MenuScene: SKScene {
    struct Line {
        var text: String
        var size: CGFloat
        var color: NSColor = .white
        var font: String = "Impact"
    }

    private let lines: [Line]
    private let prompt: String
    private let onContinue: (MenuScene) -> Void
    private var acceptsInput = false

    init(size: CGSize, lines: [Line], prompt: String, onContinue: @escaping (MenuScene) -> Void) {
        self.lines = lines
        self.prompt = prompt
        self.onContinue = onContinue
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.06, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        layoutContent()
        // Ignore input briefly so a key held from the previous screen doesn't skip this one.
        run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in self?.acceptsInput = true }]))
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutContent()
    }

    private func layoutContent() {
        removeAllChildren()
        let spacing: CGFloat = 1.5
        let total = lines.reduce(CGFloat(0)) { $0 + $1.size * spacing } + 70
        var y = size.height / 2 + total / 2
        for line in lines {
            y -= line.size * spacing
            let label = SKLabelNode.make(line.text, size: line.size, color: line.color, font: line.font)
            label.position = CGPoint(x: size.width / 2, y: y)
            addChild(label)
        }
        let promptLabel = SKLabelNode.make(prompt, size: 28, color: .systemYellow)
        promptLabel.position = CGPoint(x: size.width / 2, y: y - 70)
        promptLabel.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)])))
        addChild(promptLabel)
    }

    override func keyDown(with event: NSEvent) {
        if [36, 76, 49].contains(event.keyCode) { proceed() }   // Return, keypad Enter, Space
    }

    override func mouseDown(with event: NSEvent) {
        proceed()
    }

    private func proceed() {
        guard acceptsInput else { return }
        acceptsInput = false
        onContinue(self)
    }
}

extension MenuScene {
    static func title(size: CGSize) -> MenuScene {
        let mono = "Menlo-Bold"
        var lines: [Line] = [
            Line(text: "TANKS OF DOOM", size: 88, color: NSColor(calibratedRed: 0.9, green: 0.3, blue: 0.15, alpha: 1)),
            Line(text: "Hunt down every enemy tank in the ruined city.", size: 24),
            Line(text: " ", size: 10),
            Line(text: "W/S drive · A/D turn · MOUSE aim turret", size: 17, color: .lightGray, font: mono),
            Line(text: "LEFT CLICK main gun · RIGHT CLICK or SPACE machine gun", size: 17, color: .lightGray, font: mono),
            Line(text: "Find hidden GAS and AMMO caches · return to BASE for repairs", size: 17, color: .lightGray, font: mono),
            Line(text: "ESC pause · M minimap size · R abandon tank when out of fuel", size: 17, color: .lightGray, font: mono),
        ]
        if HighScores.bestLevels > 0 || HighScores.bestKills > 0 {
            lines.append(Line(text: " ", size: 10))
            lines.append(Line(text: "BEST RUN: \(HighScores.bestLevels) levels cleared, \(HighScores.bestKills) kills",
                              size: 20, color: .systemGreen, font: mono))
        }
        // Task 9 replaces this closure body to start the game.
        return MenuScene(size: size, lines: lines, prompt: "PRESS ENTER TO START") { _ in }
    }
}
```

- [ ] **Step 5: Build and run**

Run: `swift build`
Expected: `Build complete!` (warnings acceptable, no errors).

Run: `swift run TanksOfDoom`
Expected: a 1280×800 window titled "Tanks of Doom" with the red title, control lines and a blinking yellow "PRESS ENTER TO START". Resizing re-centres the text; Cmd-Q quits.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/TanksOfDoom
git commit -m "feat(app): window, input forwarding and title screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Drivable city — art, world rendering, player tank, pickups, base, camera, audio

**Files:**
- Create: `Sources/TanksOfDoom/Textures.swift`, `Sources/TanksOfDoom/Audio.swift`, `Sources/TanksOfDoom/Effects.swift`, `Sources/TanksOfDoom/WorldRenderer.swift`, `Sources/TanksOfDoom/Tanks.swift`, `Sources/TanksOfDoom/Pickups.swift`, `Sources/TanksOfDoom/InputState.swift`, `Sources/TanksOfDoom/GameScene.swift`, `Sources/TanksOfDoom/GameScene+Input.swift`, `Sources/TanksOfDoom/GameScene+Player.swift`
- Modify: `Sources/TanksOfDoom/MenuScene.swift` (title closure)

**Interfaces:**
- Consumes: Task 8 helpers; `CityGenerator.generate`, `Level`, `TankStats`, `TileMap.canOccupy`, `TileMap.speedMultiplier`, `WeaponKind`, `InfantryKind`
- Produces:
  - `enum Textures` — `playerHull, playerTurret, enemyHull, enemyTurret, turretAnchor, road, park, rubble, crater, base, wall, building(width:height:variant:stage:), infantry(_:), gasCan, ammoCrate, projectile(_:), mortarShell, spark, trackMark, scorch`
  - `final class Audio` — `static let shared`, `enum Sound { cannon, machineGun, explosion, bigExplosion, hit, rocket, pickup, empty }`, `play(_:volume:)`
  - `final class Effects` — `init(layer:)`, `explosion(at:scale:)`, `spark(at:)`, `dustPuff(at:)`, `muzzleFlash(at:angle:big:)`, `smokePuff(at:)`, `trackMark(at:angle:)`, `floatingText(_:at:color:)`
  - `final class WorldRenderer` — `root: SKNode`, `init(level:)`, `update(_ building: Building)` (new damage texture, or rubble on collapse)
  - `class TankNode: SKNode` — `static radius: CGFloat = 22`, `hull`, `turret`, `heading`, `turretAngle`, `distanceSinceTrack`, `muzzlePosition`, `init(hullTexture:turretTexture:)`, `move(by:in:blockers:) -> CGFloat`
  - `final class PlayerTank: TankNode` — statics `forwardSpeed 170, reverseSpeed 100, turnRate 2.2, turretTurnRate 4.0`; `stats: TankStats`, `mainCooldown`, `machineGunCooldown`, `isDestroyed`, `showWreck()`
  - `final class PickupNode: SKSpriteNode` — `kind: CacheKind`, `init(cache:)`
  - `struct InputState` — `forward, backward, left, right, leftMouse, rightMouse, space`, computed `firePrimary`, `fireSecondary`
  - `final class GameScene: SKScene` — `init(size:levelNumber:runStats:)`, properties `levelNumber`, `runStats`, `level`, `worldNode`, `cameraNode`, `renderer`, `effects`, `playerTank`, `pickups`, `input`, `inBase`; methods `buildWorld()`, `aimPoint`, `shake(_:duration:)`, `updateCamera(dt:)`, `updatePlayer(dt:)`, `leaveTracks(_:moved:)`, `collectPickups()`, `playSound(_:at:volume:)`

- [ ] **Step 1: Procedural textures**

`Sources/TanksOfDoom/Textures.swift`:
```swift
import AppKit
import SpriteKit
import TanksCore

/// All game art, drawn with Core Graphics at launch. Tanks and soldiers face +x.
enum Textures {
    static func render(_ size: CGSize, _ draw: @escaping (CGContext, CGSize) -> Void) -> SKTexture {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(ctx, size)
            return true
        }
        return SKTexture(image: image)
    }

    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    // MARK: Tanks

    static let turretAnchor = CGPoint(x: 20.0 / 64.0, y: 0.5)
    /// Distance from the turret pivot to the muzzle.
    static let muzzleOffset: CGFloat = 44

    static let playerHull = tankHull(body: color(0.36, 0.45, 0.22), dark: color(0.2, 0.26, 0.12))
    static let playerTurret = tankTurret(body: color(0.42, 0.52, 0.26), dark: color(0.2, 0.26, 0.12))
    static let enemyHull = tankHull(body: color(0.55, 0.27, 0.2), dark: color(0.3, 0.13, 0.1))
    static let enemyTurret = tankTurret(body: color(0.62, 0.32, 0.24), dark: color(0.3, 0.13, 0.1))

    static func tankHull(body: CGColor, dark: CGColor) -> SKTexture {
        render(CGSize(width: 56, height: 42)) { ctx, s in
            ctx.setFillColor(color(0.12, 0.12, 0.12))
            ctx.fill(CGRect(x: 0, y: 0, width: s.width, height: 10))
            ctx.fill(CGRect(x: 0, y: s.height - 10, width: s.width, height: 10))
            ctx.setFillColor(color(0.3, 0.3, 0.3))
            var x: CGFloat = 2
            while x < s.width {
                ctx.fill(CGRect(x: x, y: 1, width: 3, height: 8))
                ctx.fill(CGRect(x: x, y: s.height - 9, width: 3, height: 8))
                x += 6
            }
            let bodyRect = CGRect(x: 3, y: 8, width: s.width - 6, height: s.height - 16)
            ctx.setFillColor(body)
            ctx.addPath(CGPath(roundedRect: bodyRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.fillPath()
            ctx.setStrokeColor(dark)
            ctx.setLineWidth(2)
            ctx.stroke(bodyRect.insetBy(dx: 4, dy: 3))
            ctx.setFillColor(dark)
            ctx.fill(CGRect(x: s.width - 9, y: s.height / 2 - 6, width: 4, height: 12))
        }
    }

    static func tankTurret(body: CGColor, dark: CGColor) -> SKTexture {
        render(CGSize(width: 64, height: 26)) { ctx, s in
            ctx.setFillColor(dark)
            ctx.fill(CGRect(x: 28, y: s.height / 2 - 3, width: 36, height: 6))
            ctx.fill(CGRect(x: 58, y: s.height / 2 - 4, width: 6, height: 8))
            ctx.setFillColor(body)
            ctx.fillEllipse(in: CGRect(x: 7, y: 0, width: 26, height: 26))
            ctx.setStrokeColor(dark)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: 8, y: 1, width: 24, height: 24))
            ctx.setFillColor(dark)
            ctx.fillEllipse(in: CGRect(x: 14, y: 8, width: 8, height: 8))
        }
    }

    // MARK: Ground

    static func speckled(_ base: CGColor, seed: UInt64, specks: Int = 140,
                         extra: ((CGContext, inout SeededRandom) -> Void)? = nil) -> SKTexture {
        render(CGSize(width: 64, height: 64)) { ctx, s in
            var rng = SeededRandom(seed: seed)
            ctx.setFillColor(base)
            ctx.fill(CGRect(origin: .zero, size: s))
            for _ in 0..<specks {
                ctx.setFillColor(CGColor(gray: rng.chance(0.5) ? 1 : 0, alpha: 0.07))
                ctx.fill(CGRect(x: CGFloat.random(in: 0..<64, using: &rng), y: CGFloat.random(in: 0..<64, using: &rng), width: 2, height: 2))
            }
            extra?(ctx, &rng)
        }
    }

    static let road = speckled(color(0.23, 0.23, 0.24), seed: 1)

    static let park = speckled(color(0.27, 0.31, 0.17), seed: 2, specks: 220) { ctx, rng in
        ctx.setFillColor(color(0.36, 0.38, 0.2))
        for _ in 0..<14 {
            ctx.fill(CGRect(x: CGFloat.random(in: 0..<60, using: &rng), y: CGFloat.random(in: 0..<60, using: &rng), width: 3, height: 5))
        }
    }

    static let rubble = speckled(color(0.36, 0.33, 0.29), seed: 3) { ctx, rng in
        for _ in 0..<22 {
            let g = CGFloat.random(in: 0.25...0.6, using: &rng)
            ctx.setFillColor(color(g, g * 0.95, g * 0.88))
            let w = CGFloat.random(in: 4...12, using: &rng)
            let h = CGFloat.random(in: 3...9, using: &rng)
            ctx.fill(CGRect(x: CGFloat.random(in: 0..<(64 - w), using: &rng), y: CGFloat.random(in: 0..<(64 - h), using: &rng), width: w, height: h))
        }
    }

    static let crater = speckled(color(0.31, 0.26, 0.19), seed: 4) { ctx, _ in
        ctx.setFillColor(color(0.18, 0.15, 0.11))
        ctx.fillEllipse(in: CGRect(x: 10, y: 10, width: 44, height: 44))
        ctx.setFillColor(color(0.1, 0.08, 0.06))
        ctx.fillEllipse(in: CGRect(x: 20, y: 20, width: 24, height: 24))
    }

    static let base = speckled(color(0.45, 0.45, 0.43), seed: 5) { ctx, _ in
        ctx.setStrokeColor(color(0.85, 0.7, 0.1))
        ctx.setLineWidth(3)
        ctx.stroke(CGRect(x: 2, y: 2, width: 60, height: 60))
    }

    static let wall = speckled(color(0.12, 0.11, 0.1), seed: 6) { ctx, _ in
        ctx.setStrokeColor(color(0.2, 0.18, 0.16))
        ctx.setLineWidth(2)
        for row in 0..<4 {
            for col in -1..<3 {
                ctx.stroke(CGRect(x: CGFloat(col) * 32 + (row % 2 == 0 ? 0 : 16), y: CGFloat(row) * 16, width: 32, height: 16))
            }
        }
    }

    // MARK: Buildings

    private static var buildingCache: [String: SKTexture] = [:]
    private static let roofColors: [CGColor] = [
        color(0.42, 0.38, 0.34), color(0.36, 0.34, 0.33), color(0.47, 0.36, 0.28), color(0.33, 0.36, 0.38),
    ]

    /// Roof texture for a building footprint; stage 0 intact, 1 cracked, 2 heavily damaged.
    static func building(width: Int, height: Int, variant: Int, stage: Int) -> SKTexture {
        let style = variant % roofColors.count
        let key = "\(width)x\(height)-\(style)-\(stage)"
        if let cached = buildingCache[key] { return cached }
        let roof = roofColors[style]
        let texture = render(CGSize(width: CGFloat(width) * 64, height: CGFloat(height) * 64)) { ctx, s in
            var rng = SeededRandom(seed: UInt64(width * 1000 + height * 100 + style))
            let rect = CGRect(origin: .zero, size: s)
            ctx.setFillColor(color(0.15, 0.14, 0.13))
            ctx.fill(rect)
            ctx.setFillColor(roof)
            ctx.fill(rect.insetBy(dx: 5, dy: 5))
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.25))
            ctx.setLineWidth(2)
            ctx.stroke(rect.insetBy(dx: 10, dy: 10))
            for _ in 0..<(width * height / 2 + 1) {
                let w = CGFloat.random(in: 10...22, using: &rng)
                let h = CGFloat.random(in: 10...22, using: &rng)
                let unit = CGRect(x: CGFloat.random(in: 14...(s.width - 14 - w), using: &rng),
                                  y: CGFloat.random(in: 14...(s.height - 14 - h), using: &rng), width: w, height: h)
                ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
                ctx.fill(unit)
                ctx.setStrokeColor(CGColor(gray: 0.25, alpha: 1))
                ctx.setLineWidth(1.5)
                ctx.stroke(unit)
            }
            if stage >= 1 {
                drawDamage(ctx, s, rng: &rng, cracks: stage == 1 ? 4 : 10, holes: stage == 1 ? 0 : 3)
            }
        }
        buildingCache[key] = texture
        return texture
    }

    private static func drawDamage(_ ctx: CGContext, _ s: CGSize, rng: inout SeededRandom, cracks: Int, holes: Int) {
        ctx.setStrokeColor(CGColor(gray: 0.08, alpha: 0.9))
        ctx.setLineWidth(2)
        for _ in 0..<cracks {
            var p = CGPoint(x: CGFloat.random(in: 8...(s.width - 8), using: &rng), y: CGFloat.random(in: 8...(s.height - 8), using: &rng))
            ctx.move(to: p)
            for _ in 0..<4 {
                p.x += CGFloat.random(in: -18...18, using: &rng)
                p.y += CGFloat.random(in: -18...18, using: &rng)
                ctx.addLine(to: p)
            }
            ctx.strokePath()
        }
        for _ in 0..<holes {
            let r = CGFloat.random(in: 12...22, using: &rng)
            let c = CGPoint(x: CGFloat.random(in: r...(s.width - r), using: &rng), y: CGFloat.random(in: r...(s.height - r), using: &rng))
            ctx.setFillColor(CGColor(gray: 0.05, alpha: 0.6))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 1.5, y: c.y - r * 1.5, width: r * 3, height: r * 3))
            ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
    }

    // MARK: Infantry

    static func soldier(_ uniform: CGColor, weaponLength: CGFloat, weaponWidth: CGFloat) -> SKTexture {
        render(CGSize(width: 32, height: 24)) { ctx, _ in
            ctx.setFillColor(color(0.08, 0.08, 0.08))
            ctx.fill(CGRect(x: 12, y: 13, width: weaponLength, height: weaponWidth))
            ctx.setFillColor(uniform)
            ctx.fillEllipse(in: CGRect(x: 3, y: 2, width: 16, height: 20))
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
            ctx.fillEllipse(in: CGRect(x: 6, y: 7, width: 10, height: 10))
        }
    }

    static let rifleman = soldier(color(0.55, 0.5, 0.35), weaponLength: 16, weaponWidth: 3)
    static let machineGunner = soldier(color(0.3, 0.36, 0.22), weaponLength: 18, weaponWidth: 5)
    static let bazookaSoldier = soldier(color(0.45, 0.33, 0.22), weaponLength: 20, weaponWidth: 7)
    static let mortarSoldier = soldier(color(0.4, 0.4, 0.42), weaponLength: 10, weaponWidth: 9)

    static func infantry(_ kind: InfantryKind) -> SKTexture {
        switch kind {
        case .rifleman: return rifleman
        case .machineGunner: return machineGunner
        case .bazooka: return bazookaSoldier
        case .mortar: return mortarSoldier
        }
    }

    // MARK: Pickups

    static let gasCan = render(CGSize(width: 24, height: 30)) { ctx, _ in
        ctx.setFillColor(color(0.75, 0.12, 0.1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 2, y: 2, width: 20, height: 24), cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(color(0.45, 0.06, 0.05))
        ctx.fill(CGRect(x: 14, y: 24, width: 6, height: 6))
        ctx.setStrokeColor(color(0.95, 0.85, 0.2))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 6, y: 6)); ctx.addLine(to: CGPoint(x: 18, y: 22))
        ctx.move(to: CGPoint(x: 18, y: 6)); ctx.addLine(to: CGPoint(x: 6, y: 22))
        ctx.strokePath()
    }

    static let ammoCrate = render(CGSize(width: 28, height: 22)) { ctx, _ in
        ctx.setFillColor(color(0.3, 0.38, 0.2))
        ctx.fill(CGRect(x: 1, y: 1, width: 26, height: 20))
        ctx.setStrokeColor(color(0.15, 0.2, 0.1))
        ctx.setLineWidth(2)
        ctx.stroke(CGRect(x: 2, y: 2, width: 24, height: 18))
        ctx.setFillColor(color(0.95, 0.8, 0.2))
        ctx.fill(CGRect(x: 6, y: 9, width: 16, height: 4))
    }

    // MARK: Projectiles and particles

    static let shell = render(CGSize(width: 12, height: 5)) { ctx, s in
        ctx.setFillColor(color(1, 0.9, 0.5))
        ctx.fillEllipse(in: CGRect(origin: .zero, size: s))
    }

    static let bullet = render(CGSize(width: 7, height: 2)) { ctx, s in
        ctx.setFillColor(color(1, 0.95, 0.6))
        ctx.fill(CGRect(origin: .zero, size: s))
    }

    static let rocket = render(CGSize(width: 16, height: 6)) { ctx, _ in
        ctx.setFillColor(color(0.3, 0.32, 0.25))
        ctx.fill(CGRect(x: 4, y: 1, width: 12, height: 4))
        ctx.setFillColor(color(1, 0.6, 0.1))
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 6, height: 6))
    }

    static let mortarShell = render(CGSize(width: 10, height: 10)) { ctx, s in
        ctx.setFillColor(color(0.15, 0.15, 0.15))
        ctx.fillEllipse(in: CGRect(origin: .zero, size: s))
    }

    static func projectile(_ weapon: WeaponKind) -> SKTexture {
        switch weapon {
        case .mainGun, .enemyShell: return shell
        case .machineGun, .rifle, .enemyMachineGun: return bullet
        case .bazooka: return rocket
        case .mortar: return mortarShell
        }
    }

    static func radialGradient(size: CGFloat, inner: CGColor, outer: CGColor) -> SKTexture {
        render(CGSize(width: size, height: size)) { ctx, _ in
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [inner, outer] as CFArray, locations: [0, 1])!
            let c = CGPoint(x: size / 2, y: size / 2)
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size / 2, options: [])
        }
    }

    static let spark = radialGradient(size: 16, inner: color(1, 1, 1, 1), outer: color(1, 1, 1, 0))
    static let scorch = radialGradient(size: 64, inner: color(0, 0, 0, 0.55), outer: color(0, 0, 0, 0))

    /// Two track imprints, perpendicular to the direction of travel.
    static let trackMark = render(CGSize(width: 6, height: 42)) { ctx, _ in
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.28))
        ctx.fill(CGRect(x: 0, y: 1, width: 6, height: 8))
        ctx.fill(CGRect(x: 0, y: 33, width: 6, height: 8))
    }
}
```

- [ ] **Step 2: Synthesized audio and visual effects**

`Sources/TanksOfDoom/Audio.swift`:
```swift
import AVFoundation
import TanksCore

/// Tiny synthesizer: every sound effect is generated in code at startup.
/// If no audio output is available the game simply runs silently.
final class Audio {
    enum Sound: CaseIterable {
        case cannon, machineGun, explosion, bigExplosion, hit, rocket, pickup, empty
    }

    static let shared = Audio()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var isReady = false

    private init() {
        for sound in Sound.allCases { buffers[sound] = synthesize(sound) }
        for _ in 0..<16 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.6
        do {
            try engine.start()
            players.forEach { $0.play() }
            isReady = true
        } catch {
            isReady = false
        }
    }

    func play(_ sound: Sound, volume: Float = 1) {
        guard isReady, volume > 0.02, let buffer = buffers[sound] else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = min(1, volume)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func synthesize(_ sound: Sound) -> AVAudioPCMBuffer {
        let tau = 2 * Double.pi
        switch sound {
        case .cannon:
            return render(duration: 0.6, cutoff: 900) { (t: Double, n: Double) -> Double in
                let blast = 5 * n * exp(-t * 6)
                let thump = 0.6 * sin(tau * 55 * t) * exp(-t * 8)
                return blast + thump
            }
        case .machineGun:
            return render(duration: 0.08, cutoff: 3_000) { (t: Double, n: Double) -> Double in
                3 * n * exp(-t * 50)
            }
        case .explosion:
            return render(duration: 1.0, cutoff: 600) { (t: Double, n: Double) -> Double in
                let roar = 6 * n * exp(-t * 4)
                let boom = 0.4 * sin(tau * 45 * t) * exp(-t * 5)
                return roar + boom
            }
        case .bigExplosion:
            return render(duration: 1.8, cutoff: 400) { (t: Double, n: Double) -> Double in
                let roar = 9 * n * exp(-t * 2.2)
                let boom = 0.6 * sin(tau * 35 * t) * exp(-t * 3)
                return roar + boom
            }
        case .hit:
            return render(duration: 0.3, cutoff: 4_000) { (t: Double, n: Double) -> Double in
                let crack = 2 * n * exp(-t * 30)
                let ring1 = 0.5 * sin(tau * 420 * t) * exp(-t * 12)
                let ring2 = 0.3 * sin(tau * 690 * t) * exp(-t * 15)
                return crack + ring1 + ring2
            }
        case .rocket:
            return render(duration: 0.5, cutoff: 2_000) { (t: Double, n: Double) -> Double in
                let envelope = t < 0.05 ? t / 0.05 : exp(-(t - 0.05) * 5)
                return 2 * n * envelope
            }
        case .pickup:
            return render(duration: 0.35, cutoff: 1_000) { (t: Double, _: Double) -> Double in
                let phase = tau * (500 * t + 700 * t * t)
                return 0.4 * sin(phase) * (1 - t / 0.35)
            }
        case .empty:
            return render(duration: 0.06, cutoff: 1_000) { (t: Double, _: Double) -> Double in
                0.4 * sin(tau * 1_200 * t) * exp(-t * 80)
            }
        }
    }

    /// Renders `sample(time, lowPassedNoise)` into a mono buffer.
    private func render(duration: Double, cutoff: Double, _ sample: (Double, Double) -> Double) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(duration * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        var rng = SeededRandom(seed: 0xA0D10)
        let alpha = min(1, 2 * Double.pi * cutoff / rate)
        var noise = 0.0
        for i in 0..<Int(frames) {
            noise += alpha * (Double.random(in: -1...1, using: &rng) - noise)
            data[i] = Float(max(-1, min(1, sample(Double(i) / rate, noise))))
        }
        return buffer
    }
}
```

`Sources/TanksOfDoom/Effects.swift`:
```swift
import AppKit
import SpriteKit

/// Short-lived visual effects added to the world layer.
final class Effects {
    private unowned let layer: SKNode

    init(layer: SKNode) {
        self.layer = layer
    }

    func explosion(at point: CGPoint, scale: CGFloat) {
        let fire = emitter(count: Int(50 * scale), lifetime: 0.5, speed: 130 * scale, size: 1.4 * scale,
                           colors: [.white, .yellow, .orange, NSColor(red: 0.3, green: 0.1, blue: 0.05, alpha: 1)], additive: true)
        fire.position = point
        fire.zPosition = Z.effects
        let smoke = emitter(count: Int(24 * scale), lifetime: 1.6, speed: 45 * scale, size: 2.0 * scale,
                            colors: [NSColor(white: 0.35, alpha: 0.8), NSColor(white: 0.15, alpha: 0)], additive: false)
        smoke.particleScaleSpeed = 1.0
        smoke.position = point
        smoke.zPosition = Z.effects - 0.5
        let scorch = SKSpriteNode(texture: Textures.scorch, size: CGSize(width: 90 * scale, height: 90 * scale))
        scorch.position = point
        scorch.zPosition = Z.tracks
        scorch.run(.sequence([.wait(forDuration: 15), .fadeOut(withDuration: 5), .removeFromParent()]))
        fire.run(.sequence([.wait(forDuration: 2.5), .removeFromParent()]))
        smoke.run(.sequence([.wait(forDuration: 2.5), .removeFromParent()]))
        layer.addChild(scorch)
        layer.addChild(smoke)
        layer.addChild(fire)
    }

    func spark(at point: CGPoint) {
        let sparks = emitter(count: 8, lifetime: 0.2, speed: 90, size: 0.4, colors: [.white, .yellow], additive: true)
        sparks.position = point
        sparks.zPosition = Z.effects
        sparks.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
        layer.addChild(sparks)
    }

    func dustPuff(at point: CGPoint) {
        let dust = emitter(count: 14, lifetime: 0.6, speed: 50, size: 0.9,
                           colors: [NSColor(white: 0.6, alpha: 0.8), NSColor(white: 0.4, alpha: 0)], additive: false)
        dust.position = point
        dust.zPosition = Z.effects
        dust.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
        layer.addChild(dust)
    }

    func muzzleFlash(at point: CGPoint, angle: CGFloat, big: Bool) {
        let flash = SKSpriteNode(texture: Textures.spark)
        flash.color = .yellow
        flash.colorBlendFactor = 0.6
        flash.blendMode = .add
        flash.size = big ? CGSize(width: 46, height: 26) : CGSize(width: 16, height: 9)
        flash.position = point
        flash.zRotation = angle
        flash.zPosition = Z.effects
        flash.run(.sequence([.fadeOut(withDuration: big ? 0.12 : 0.05), .removeFromParent()]))
        layer.addChild(flash)
    }

    func smokePuff(at point: CGPoint) {
        let puff = SKSpriteNode(texture: Textures.spark)
        puff.color = .gray
        puff.colorBlendFactor = 1
        puff.alpha = 0.5
        puff.size = CGSize(width: 10, height: 10)
        puff.position = point
        puff.zPosition = Z.projectiles - 0.5
        puff.run(.sequence([.group([.scale(to: 2.5, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        layer.addChild(puff)
    }

    func trackMark(at point: CGPoint, angle: CGFloat) {
        let mark = SKSpriteNode(texture: Textures.trackMark)
        mark.position = point
        mark.zRotation = angle
        mark.zPosition = Z.tracks
        mark.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 2), .removeFromParent()]))
        layer.addChild(mark)
    }

    func floatingText(_ text: String, at point: CGPoint, color: NSColor) {
        let label = SKLabelNode.make(text, size: 18, color: color, font: "Menlo-Bold")
        label.position = point
        label.zPosition = Z.effects + 1
        label.run(.sequence([.group([.moveBy(x: 0, y: 40, duration: 1), .fadeOut(withDuration: 1)]), .removeFromParent()]))
        layer.addChild(label)
    }

    private func emitter(count: Int, lifetime: CGFloat, speed: CGFloat, size: CGFloat, colors: [NSColor], additive: Bool) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Textures.spark
        e.particleBirthRate = 4000
        e.numParticlesToEmit = max(1, count)
        e.particleLifetime = lifetime
        e.particleLifetimeRange = lifetime * 0.5
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.7
        e.emissionAngleRange = .pi * 2
        e.particleScale = size
        e.particleScaleRange = size * 0.4
        e.particleAlphaSpeed = -1 / lifetime
        e.particleColorBlendFactor = 1
        let times = colors.indices.map { NSNumber(value: Double($0) / Double(max(1, colors.count - 1))) }
        e.particleColorSequence = SKKeyframeSequence(keyframeValues: colors, times: times)
        e.particleBlendMode = additive ? .add : .alpha
        return e
    }
}
```

- [ ] **Step 3: World renderer, tanks, pickups, input state**

`Sources/TanksOfDoom/WorldRenderer.swift`:
```swift
import SpriteKit
import TanksCore

/// Draws the ground tile map and one sprite per building, and keeps them in sync with damage.
final class WorldRenderer {
    let root = SKNode()
    private let ground: SKTileMapNode
    private let groups: [String: SKTileGroup]
    private var buildingNodes: [Int: SKSpriteNode] = [:]

    init(level: Level) {
        let textures: [String: SKTexture] = [
            "road": Textures.road, "park": Textures.park, "rubble": Textures.rubble,
            "crater": Textures.crater, "base": Textures.base, "wall": Textures.wall,
        ]
        let tile = CGSize(width: tileSize, height: tileSize)
        var groups: [String: SKTileGroup] = [:]
        for (name, texture) in textures {
            let group = SKTileGroup(tileDefinition: SKTileDefinition(texture: texture, size: tile))
            group.name = name
            groups[name] = group
        }
        self.groups = groups
        let map = level.map
        ground = SKTileMapNode(tileSet: SKTileSet(tileGroups: Array(groups.values)), columns: map.width, rows: map.height, tileSize: tile)
        ground.anchorPoint = .zero
        ground.zPosition = Z.ground
        root.addChild(ground)
        for y in 0..<map.height {
            for x in 0..<map.width { setTile(GridPoint(x, y), map[x: x, y: y]) }
        }
        for building in level.buildings { addBuilding(building) }
    }

    func update(_ building: Building) {
        guard let node = buildingNodes[building.id] else { return }
        if building.isDestroyed {
            node.removeFromParent()
            buildingNodes[building.id] = nil
            for tile in building.tiles { setTile(tile, .rubble) }
        } else {
            node.texture = Textures.building(width: building.rect.width, height: building.rect.height,
                                             variant: building.id, stage: building.damageStage)
        }
    }

    private func setTile(_ p: GridPoint, _ tile: Tile) {
        ground.setTileGroup(groups[Self.groupName(for: tile)], forColumn: p.x, row: p.y)
    }

    private static func groupName(for tile: Tile) -> String {
        switch tile {
        case .road: return "road"
        case .park: return "park"
        case .rubble, .building: return "rubble"   // rubble shows once a building collapses
        case .crater: return "crater"
        case .base: return "base"
        case .wall: return "wall"
        }
    }

    private func addBuilding(_ building: Building) {
        let r = building.rect
        let node = SKSpriteNode(texture: Textures.building(width: r.width, height: r.height, variant: building.id, stage: building.damageStage))
        node.anchorPoint = .zero
        node.size = CGSize(width: CGFloat(r.width) * tileSize, height: CGFloat(r.height) * tileSize)
        node.position = CGPoint(x: CGFloat(r.minX) * tileSize, y: CGFloat(r.minY) * tileSize)
        node.zPosition = Z.buildings
        let shadow = SKSpriteNode(color: NSColor(white: 0, alpha: 0.35), size: node.size)
        shadow.anchorPoint = .zero
        shadow.position = CGPoint(x: 8, y: -8)
        shadow.zPosition = -0.5
        node.addChild(shadow)
        root.addChild(node)
        buildingNodes[building.id] = node
    }
}
```

`Sources/TanksOfDoom/Tanks.swift`:
```swift
import SpriteKit
import TanksCore

/// A tank: a hull that drives and a turret that aims independently.
class TankNode: SKNode {
    static let radius: CGFloat = 22

    let hull: SKSpriteNode
    let turret: SKSpriteNode
    var heading: CGFloat = 0 { didSet { hull.zRotation = heading } }
    var turretAngle: CGFloat = 0 { didSet { turret.zRotation = turretAngle } }
    var distanceSinceTrack: CGFloat = 0

    init(hullTexture: SKTexture, turretTexture: SKTexture) {
        hull = SKSpriteNode(texture: hullTexture)
        turret = SKSpriteNode(texture: turretTexture)
        super.init()
        turret.anchorPoint = Textures.turretAnchor
        hull.zPosition = 0
        turret.zPosition = 1
        addChild(hull)
        addChild(turret)
        zPosition = Z.tanks
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    var muzzlePosition: CGPoint { position + CGPoint(angle: turretAngle, length: Textures.muzzleOffset) }

    /// Moves with wall sliding. Other tanks block, unless the move separates overlapping tanks.
    /// Returns the distance actually travelled.
    @discardableResult
    func move(by delta: CGPoint, in map: TileMap, blockers: [TankNode]) -> CGFloat {
        let start = position
        func isFree(_ p: CGPoint) -> Bool {
            guard map.canOccupy(p.world, radius: Double(Self.radius)) else { return false }
            return !blockers.contains { other in
                other !== self && other.position.distance(to: p) < Self.radius * 2
                    && other.position.distance(to: p) < other.position.distance(to: start)
            }
        }
        let target = position + delta
        if isFree(target) {
            position = target
        } else if isFree(CGPoint(x: target.x, y: position.y)) {
            position.x = target.x
        } else if isFree(CGPoint(x: position.x, y: target.y)) {
            position.y = target.y
        }
        return position.distance(to: start)
    }
}

final class PlayerTank: TankNode {
    static let forwardSpeed: CGFloat = 170
    static let reverseSpeed: CGFloat = 100
    static let turnRate: CGFloat = 2.2
    static let turretTurnRate: CGFloat = 4.0

    var stats = TankStats()
    var mainCooldown: Double = 0
    var machineGunCooldown: Double = 0
    var isDestroyed: Bool { stats.isDestroyed }

    init() {
        super.init(hullTexture: Textures.playerHull, turretTexture: Textures.playerTurret)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showWreck() {
        for part in [hull, turret] {
            part.color = .black
            part.colorBlendFactor = 0.75
        }
    }
}
```

`Sources/TanksOfDoom/Pickups.swift`:
```swift
import SpriteKit
import TanksCore

final class PickupNode: SKSpriteNode {
    let kind: CacheKind

    init(cache: Cache) {
        kind = cache.kind
        let texture = cache.kind == .gas ? Textures.gasCan : Textures.ammoCrate
        super.init(texture: texture, color: .clear, size: texture.size())
        zPosition = Z.pickups
        run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.6), .scale(to: 1.0, duration: 0.6)])))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}
```

`Sources/TanksOfDoom/InputState.swift`:
```swift
struct InputState {
    var forward = false
    var backward = false
    var left = false
    var right = false
    var leftMouse = false
    var rightMouse = false
    var space = false

    var firePrimary: Bool { leftMouse }
    var fireSecondary: Bool { rightMouse || space }
}
```

- [ ] **Step 4: Game scene, input and player driving**

`Sources/TanksOfDoom/GameScene.swift`:
```swift
import AppKit
import SpriteKit
import TanksCore

final class GameScene: SKScene {
    let levelNumber: Int
    var runStats: RunStats
    var level: Level

    let worldNode = SKNode()
    let cameraNode = SKCameraNode()
    let crosshair = SKShapeNode(circleOfRadius: 10)
    var renderer: WorldRenderer!
    var effects: Effects!
    let playerTank = PlayerTank()
    var pickups: [PickupNode] = []

    var input = InputState()
    var mouseInCamera = CGPoint.zero
    var lastUpdate: TimeInterval = 0
    var cameraBase = CGPoint.zero
    var shakeTime: Double = 0
    var shakeMagnitude: CGFloat = 0
    var inBase = false
    private var isSetUp = false
    private var resignObserver: NSObjectProtocol?

    init(size: CGSize, levelNumber: Int, runStats: RunStats) {
        self.levelNumber = levelNumber
        self.runStats = runStats
        self.level = CityGenerator.generate(seed: .random(in: 0...UInt64.max), level: levelNumber)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        guard !isSetUp else { return }
        isSetUp = true
        buildWorld()
        // Keys released while the window is in the background never arrive; forget them.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: view.window, queue: .main) { [weak self] _ in
            self?.input = InputState()
        }
    }

    override func willMove(from view: SKView) {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func buildWorld() {
        addChild(worldNode)
        renderer = WorldRenderer(level: level)
        worldNode.addChild(renderer.root)
        effects = Effects(layer: worldNode)

        let baseLabel = SKLabelNode.make("BASE", size: 40, color: NSColor(white: 1, alpha: 0.35))
        baseLabel.position = level.map.center(level.baseCenter) - CGPoint(x: tileSize / 2, y: tileSize / 2)
        baseLabel.zPosition = Z.tracks
        worldNode.addChild(baseLabel)

        for cache in level.caches {
            let pickup = PickupNode(cache: cache)
            pickup.position = level.map.center(cache.position)
            worldNode.addChild(pickup)
            pickups.append(pickup)
        }

        playerTank.position = level.map.center(level.baseCenter)
        playerTank.heading = .pi / 4
        playerTank.turretAngle = .pi / 4
        worldNode.addChild(playerTank)

        addChild(cameraNode)
        camera = cameraNode
        cameraBase = playerTank.position
        cameraNode.position = cameraBase
        crosshair.strokeColor = .white
        crosshair.lineWidth = 2
        crosshair.zPosition = Z.hud + 10
        cameraNode.addChild(crosshair)
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(currentTime - lastUpdate, 1.0 / 30)
        lastUpdate = currentTime
        updatePlayer(dt: dt)
        updateCamera(dt: dt)
    }

    var aimPoint: CGPoint { cameraNode.convert(mouseInCamera, to: worldNode) }

    func shake(_ magnitude: CGFloat, duration: Double) {
        guard magnitude >= shakeMagnitude || shakeTime <= 0 else { return }
        shakeMagnitude = magnitude
        shakeTime = duration
    }

    func updateCamera(dt: Double) {
        let follow = CGFloat(min(1, 6 * dt))
        var p = cameraBase + (playerTank.position - cameraBase) * follow
        p.x = clampCamera(p.x, half: size.width / 2, extent: CGFloat(level.map.width) * tileSize)
        p.y = clampCamera(p.y, half: size.height / 2, extent: CGFloat(level.map.height) * tileSize)
        cameraBase = p
        var offset = CGPoint.zero
        if shakeTime > 0 {
            shakeTime -= dt
            offset = CGPoint(x: .random(in: -shakeMagnitude...shakeMagnitude), y: .random(in: -shakeMagnitude...shakeMagnitude))
            if shakeTime <= 0 { shakeMagnitude = 0 }
        }
        cameraNode.position = p + offset
        crosshair.position = mouseInCamera
    }

    /// Keeps the view inside the map; centres the map when the view is larger than it.
    private func clampCamera(_ value: CGFloat, half: CGFloat, extent: CGFloat) -> CGFloat {
        if extent <= half * 2 { return extent / 2 }
        return min(max(value, half), extent - half)
    }

    func playSound(_ sound: Audio.Sound, at point: CGPoint, volume: Float = 1) {
        let distance = Float(point.distance(to: playerTank.position))
        Audio.shared.play(sound, volume: volume * max(0, 1 - distance / 1400))
    }
}
```

`Sources/TanksOfDoom/GameScene+Input.swift`:
```swift
import AppKit
import SpriteKit

extension GameScene {
    override func keyDown(with event: NSEvent) {
        setKey(event.keyCode, down: true)
    }

    override func keyUp(with event: NSEvent) {
        setKey(event.keyCode, down: false)
    }

    func setKey(_ code: UInt16, down: Bool) {
        switch code {
        case 13, 126: input.forward = down    // W, up arrow
        case 1, 125: input.backward = down    // S, down arrow
        case 0, 123: input.left = down        // A, left arrow
        case 2, 124: input.right = down       // D, right arrow
        case 49: input.space = down
        default: break
        }
    }

    override func mouseDown(with event: NSEvent) { input.leftMouse = true; trackMouse(event) }
    override func mouseUp(with event: NSEvent) { input.leftMouse = false }
    override func mouseDragged(with event: NSEvent) { trackMouse(event) }
    override func rightMouseDown(with event: NSEvent) { input.rightMouse = true; trackMouse(event) }
    override func rightMouseUp(with event: NSEvent) { input.rightMouse = false }
    override func rightMouseDragged(with event: NSEvent) { trackMouse(event) }
    override func mouseMoved(with event: NSEvent) { trackMouse(event) }

    /// Stored in camera space so the aim stays correct while the camera moves.
    func trackMouse(_ event: NSEvent) {
        mouseInCamera = event.location(in: cameraNode)
    }
}
```

`Sources/TanksOfDoom/GameScene+Player.swift`:
```swift
import SpriteKit
import TanksCore

extension GameScene {
    func updatePlayer(dt: Double) {
        guard !playerTank.isDestroyed else { return }
        let map = level.map
        var turn: CGFloat = 0
        if input.left { turn += 1 }
        if input.right { turn -= 1 }
        var drive: CGFloat = 0
        if input.forward { drive += 1 }
        if input.backward { drive -= 1 }

        var moving = false
        if playerTank.stats.canMove {
            if turn != 0 {
                playerTank.heading += turn * PlayerTank.turnRate * CGFloat(dt)
                moving = true
            }
            if drive != 0 {
                let speed = (drive > 0 ? PlayerTank.forwardSpeed : PlayerTank.reverseSpeed)
                    * CGFloat(map.speedMultiplier(at: playerTank.position.world))
                let moved = playerTank.move(by: CGPoint(angle: playerTank.heading, length: drive * speed * CGFloat(dt)),
                                            in: map, blockers: [])
                if moved > 0 {
                    moving = true
                    leaveTracks(playerTank, moved: moved)
                }
            }
        }
        let hadFuel = playerTank.stats.fuel > 0
        playerTank.stats.burnFuel(seconds: dt, moving: moving)
        if hadFuel && playerTank.stats.fuel <= 0 {
            effects.floatingText("OUT OF FUEL!", at: playerTank.position + CGPoint(x: 0, y: 44), color: .systemOrange)
        }

        let aim = playerTank.position.angle(to: aimPoint)
        playerTank.turretAngle = rotate(playerTank.turretAngle, toward: aim, maxStep: PlayerTank.turretTurnRate * CGFloat(dt))

        inBase = level.isBase(map.grid(playerTank.position))
        if inBase { playerTank.stats.applyBase(seconds: dt) }
        collectPickups()
    }

    func leaveTracks(_ tank: TankNode, moved: CGFloat) {
        tank.distanceSinceTrack += moved
        guard tank.distanceSinceTrack >= 12 else { return }
        tank.distanceSinceTrack = 0
        effects.trackMark(at: tank.position, angle: tank.heading)
    }

    func collectPickups() {
        for pickup in pickups where pickup.position.distance(to: playerTank.position) < 40 {
            playerTank.stats.collect(pickup.kind)
            effects.floatingText(pickup.kind == .gas ? "+GAS" : "+AMMO", at: pickup.position, color: .systemGreen)
            Audio.shared.play(.pickup)
            pickup.removeFromParent()
            pickups.removeAll { $0 === pickup }
        }
    }
}
```

- [ ] **Step 5: Start the game from the title screen**

In `Sources/TanksOfDoom/MenuScene.swift`, replace:
```swift
        // Task 9 replaces this closure body to start the game.
        return MenuScene(size: size, lines: lines, prompt: "PRESS ENTER TO START") { _ in }
```
with:
```swift
        return MenuScene(size: size, lines: lines, prompt: "PRESS ENTER TO START") { scene in
            let game = GameScene(size: scene.size, levelNumber: 1, runStats: RunStats())
            scene.view?.presentScene(game, transition: .fade(withDuration: 0.6))
        }
```

- [ ] **Step 6: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 7: Run and verify by playing**

Run: `swift run TanksOfDoom`, press Enter. Verify:
- The city appears: grey roads, avenues, roofed buildings with shadows, parks/craters/rubble, a yellow-bordered BASE in the bottom-left; the tank starts on the base.
- W/S/A/D (and arrows) drive; the tank slides along buildings and cannot leave the walled map; rubble/craters halve speed; track marks appear and fade.
- The turret follows the mouse crosshair, including while the camera moves.
- Driving onto a gas can or ammo crate removes it with "+GAS"/"+AMMO" and a chirp.
- Review Focus #2: resize the window very small and very large (full screen on a big display) — the camera never shows outside the map, and centres the map if the window is larger than it.
- Switch to another app while holding W, return — the tank is not still driving.

- [ ] **Step 8: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): drivable procedural city with tank, pickups, base and audio

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Combat — projectiles, player weapons, building destruction

**Files:**
- Create: `Sources/TanksOfDoom/Projectile.swift`, `Sources/TanksOfDoom/GameScene+Combat.swift`
- Modify: `Sources/TanksOfDoom/GameScene.swift`

**Interfaces:**
- Consumes: `Combat.spec/damage`, `Level.damageBuilding`, `WorldRenderer.update`, `Effects`, `Audio`, `Building.worldCenter`
- Produces:
  - `protocol Hostile: SKNode { hitRadius: CGFloat; targetKind: TargetKind; canBeHit: Bool; func applyDamage(_ amount: Int, in scene: GameScene) }`
  - `final class Projectile: SKSpriteNode` (`weapon`, `byPlayer`, `ownerBuilding`, `velocity`, `remainingRange`, `smokeTimer`)
  - `final class MortarShell: SKSpriteNode` (`static flightTime = 1.8`, `target`, `marker`, `advance(dt:) -> Bool`)
  - On `GameScene`: stored `projectiles`, `mortars`; computed `hostiles: [Hostile]`; `fire(_:from:angle:byPlayer:ownerBuilding:)`, `fireMortar(from:at:)`, `updatePlayerWeapons(dt:)`, `updateProjectiles(dt:)`, `updateMortars(dt:)`, `applySplash(_:at:byPlayer:excluding:)`, `damagePlayer(_:)`, `damageBuilding(_:amount:)`, `buildingDestroyed(_:)`

- [ ] **Step 1: Projectiles and the Hostile protocol**

`Sources/TanksOfDoom/Projectile.swift`:
```swift
import AppKit
import SpriteKit
import TanksCore

/// Something the player's weapons can hit (enemy tanks, exposed infantry).
protocol Hostile: SKNode {
    var hitRadius: CGFloat { get }
    var targetKind: TargetKind { get }
    var canBeHit: Bool { get }
    func applyDamage(_ amount: Int, in scene: GameScene)
}

/// A straight-flying shot.
final class Projectile: SKSpriteNode {
    let weapon: WeaponKind
    let byPlayer: Bool
    /// Infantry shots start inside their own building, so that building never stops them.
    let ownerBuilding: Int?
    let velocity: CGVector
    var remainingRange: CGFloat
    var smokeTimer: Double = 0

    init(weapon: WeaponKind, angle: CGFloat, byPlayer: Bool, ownerBuilding: Int?) {
        let spec = Combat.spec(weapon)
        self.weapon = weapon
        self.byPlayer = byPlayer
        self.ownerBuilding = ownerBuilding
        velocity = CGVector(dx: cos(angle) * spec.projectileSpeed, dy: sin(angle) * spec.projectileSpeed)
        remainingRange = CGFloat(spec.range)
        let texture = Textures.projectile(weapon)
        super.init(texture: texture, color: .clear, size: texture.size())
        zRotation = angle
        zPosition = Z.projectiles
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// A mortar round: flies a fixed-time arc over buildings to a marked target.
final class MortarShell: SKSpriteNode {
    static let flightTime = 1.8

    let start: CGPoint
    let target: CGPoint
    let marker: SKShapeNode
    private var elapsed: Double = 0

    init(from start: CGPoint, to target: CGPoint) {
        self.start = start
        self.target = target
        marker = SKShapeNode(circleOfRadius: CGFloat(Combat.spec(.mortar).splashRadius))
        marker.strokeColor = NSColor.systemRed.withAlphaComponent(0.8)
        marker.fillColor = NSColor.systemRed.withAlphaComponent(0.12)
        marker.lineWidth = 2
        marker.position = target
        marker.zPosition = Z.pickups
        marker.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.25), .fadeAlpha(to: 1, duration: 0.25)])))
        super.init(texture: Textures.mortarShell, color: .clear, size: Textures.mortarShell.size())
        position = start
        zPosition = Z.effects - 1
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Advances along the arc; returns true on landing.
    func advance(dt: Double) -> Bool {
        elapsed += dt
        let t = CGFloat(min(1, elapsed / Self.flightTime))
        position = start + (target - start) * t
        setScale(1 + 1.8 * sin(.pi * t))
        return t >= 1
    }
}
```

- [ ] **Step 2: Scene state for combat**

In `Sources/TanksOfDoom/GameScene.swift`, after `var pickups: [PickupNode] = []` add:
```swift
    var projectiles: [Projectile] = []
    var mortars: [MortarShell] = []
    /// Everything the player can shoot. Tasks 11 and 12 add enemy tanks and infantry.
    var hostiles: [Hostile] { [] }
```

Replace the body of `update(_:)` with:
```swift
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(currentTime - lastUpdate, 1.0 / 30)
        lastUpdate = currentTime
        updatePlayer(dt: dt)
        updatePlayerWeapons(dt: dt)
        updateProjectiles(dt: dt)
        updateMortars(dt: dt)
        updateCamera(dt: dt)
```

- [ ] **Step 3: Combat logic**

`Sources/TanksOfDoom/GameScene+Combat.swift`:
```swift
import AppKit
import SpriteKit
import TanksCore

extension GameScene {
    enum Impact {
        case hostile(Hostile)
        case player
        case building(Int)
        case solid
    }

    func fire(_ weapon: WeaponKind, from origin: CGPoint, angle: CGFloat, byPlayer: Bool, ownerBuilding: Int? = nil) {
        let projectile = Projectile(weapon: weapon, angle: angle, byPlayer: byPlayer, ownerBuilding: ownerBuilding)
        projectile.position = origin
        worldNode.addChild(projectile)
        projectiles.append(projectile)
        switch weapon {
        case .mainGun, .enemyShell:
            effects.muzzleFlash(at: origin, angle: angle, big: true)
            playSound(.cannon, at: origin)
        case .bazooka:
            playSound(.rocket, at: origin)
        default:
            effects.muzzleFlash(at: origin, angle: angle, big: false)
            playSound(.machineGun, at: origin, volume: 0.5)
        }
    }

    func fireMortar(from origin: CGPoint, at target: CGPoint) {
        let shell = MortarShell(from: origin, to: target)
        worldNode.addChild(shell.marker)
        worldNode.addChild(shell)
        mortars.append(shell)
        playSound(.cannon, at: origin, volume: 0.4)
    }

    func updatePlayerWeapons(dt: Double) {
        guard !playerTank.isDestroyed else { return }
        playerTank.mainCooldown -= dt
        playerTank.machineGunCooldown -= dt

        if input.firePrimary && playerTank.mainCooldown <= 0 {
            if playerTank.stats.consumeShell() {
                fire(.mainGun, from: playerTank.muzzlePosition, angle: playerTank.turretAngle, byPlayer: true)
                playerTank.mainCooldown = Combat.spec(.mainGun).reload
                shake(4, duration: 0.15)
            } else {
                playerTank.mainCooldown = 0.5
                Audio.shared.play(.empty)
                effects.floatingText("NO SHELLS", at: playerTank.position + CGPoint(x: 0, y: 40), color: .systemYellow)
            }
        }

        if input.fireSecondary && playerTank.machineGunCooldown <= 0 {
            if playerTank.stats.consumeRound() {
                let side = CGPoint(angle: playerTank.turretAngle - .pi / 2, length: 7)
                let origin = playerTank.position + CGPoint(angle: playerTank.turretAngle, length: 30) + side
                fire(.machineGun, from: origin, angle: playerTank.turretAngle + .random(in: -0.04...0.04), byPlayer: true)
                playerTank.machineGunCooldown = Combat.spec(.machineGun).reload
            } else {
                playerTank.machineGunCooldown = 0.5
                Audio.shared.play(.empty)
                effects.floatingText("NO MG AMMO", at: playerTank.position + CGPoint(x: 0, y: 40), color: .systemYellow)
            }
        }
    }

    /// Moves every projectile in ≤16 pt sub-steps so fast shots can't tunnel through buildings.
    func updateProjectiles(dt: Double) {
        for projectile in projectiles {
            let start = projectile.position
            let step = CGPoint(x: projectile.velocity.dx * dt, y: projectile.velocity.dy * dt)
            let length = step.length
            let substeps = max(1, Int((length / 16).rounded(.up)))
            var impact: (Impact, CGPoint)?
            for i in 1...substeps {
                let point = start + step * (CGFloat(i) / CGFloat(substeps))
                if let hit = collision(for: projectile, at: point) {
                    impact = (hit, point)
                    break
                }
            }
            if let (hit, point) = impact {
                resolve(hit, projectile: projectile, at: point)
                continue
            }
            projectile.position = start + step
            projectile.remainingRange -= length
            if projectile.weapon == .bazooka {
                projectile.smokeTimer -= dt
                if projectile.smokeTimer <= 0 {
                    effects.smokePuff(at: projectile.position)
                    projectile.smokeTimer = 0.03
                }
            }
            if projectile.remainingRange <= 0 {
                if Combat.spec(projectile.weapon).splashRadius > 0 {
                    detonate(projectile, at: projectile.position, direct: nil)
                } else {
                    removeProjectile(projectile)
                }
            }
        }
    }

    private func collision(for projectile: Projectile, at point: CGPoint) -> Impact? {
        if projectile.byPlayer {
            if let target = hostiles.first(where: { $0.canBeHit && $0.position.distance(to: point) < $0.hitRadius }) {
                return .hostile(target)
            }
        } else if !playerTank.isDestroyed && playerTank.position.distance(to: point) < TankNode.radius {
            return .player
        }
        let tile = level.map[level.map.grid(point)]
        if let id = tile.buildingID {
            return id == projectile.ownerBuilding ? nil : .building(id)
        }
        return tile == .wall ? .solid : nil
    }

    private func resolve(_ impact: Impact, projectile: Projectile, at point: CGPoint) {
        var direct: AnyObject?
        switch impact {
        case .hostile(let target):
            direct = target
            let damage = Combat.damage(projectile.weapon, to: target.targetKind, distance: 0)
            if damage > 0 { target.applyDamage(damage, in: self) }
        case .player:
            direct = playerTank
            damagePlayer(Combat.damage(projectile.weapon, to: .tank, distance: 0))
        case .building(let id):
            let damage = Combat.damage(projectile.weapon, to: .building, distance: 0)
            if damage > 0 { damageBuilding(id, amount: damage) }
        case .solid:
            break
        }
        if Combat.spec(projectile.weapon).splashRadius > 0 {
            detonate(projectile, at: point, direct: direct)
        } else {
            effects.spark(at: point)
            removeProjectile(projectile)
        }
    }

    private func detonate(_ projectile: Projectile, at point: CGPoint, direct: AnyObject?) {
        applySplash(projectile.weapon, at: point, byPlayer: projectile.byPlayer, excluding: direct)
        let heavy = projectile.weapon == .mainGun || projectile.weapon == .enemyShell
        effects.explosion(at: point, scale: heavy ? 1.0 : 0.7)
        playSound(.explosion, at: point, volume: 0.7)
        removeProjectile(projectile)
    }

    /// Splash damage around an impact; `excluding` already took the direct hit.
    func applySplash(_ weapon: WeaponKind, at point: CGPoint, byPlayer: Bool, excluding: AnyObject?) {
        if byPlayer {
            for target in hostiles where target.canBeHit && target !== excluding {
                let damage = Combat.damage(weapon, to: target.targetKind, distance: Double(target.position.distance(to: point)))
                if damage > 0 { target.applyDamage(damage, in: self) }
            }
        } else if excluding !== playerTank && !playerTank.isDestroyed {
            let damage = Combat.damage(weapon, to: .tank, distance: Double(playerTank.position.distance(to: point)))
            if damage > 0 { damagePlayer(damage) }
        }
    }

    private func removeProjectile(_ projectile: Projectile) {
        projectile.removeFromParent()
        projectiles.removeAll { $0 === projectile }
    }

    func updateMortars(dt: Double) {
        for shell in mortars {
            guard shell.advance(dt: dt) else { continue }
            applySplash(.mortar, at: shell.target, byPlayer: false, excluding: nil)
            effects.explosion(at: shell.target, scale: 0.9)
            playSound(.explosion, at: shell.target, volume: 0.8)
            shell.marker.removeFromParent()
            shell.removeFromParent()
            mortars.removeAll { $0 === shell }
        }
    }

    func damagePlayer(_ amount: Int) {
        guard amount > 0, !playerTank.isDestroyed else { return }
        playerTank.stats.takeDamage(amount)
        effects.floatingText("-\(amount)", at: playerTank.position + CGPoint(x: 0, y: 36), color: .systemRed)
        Audio.shared.play(.hit, volume: 0.8)
        shake(min(14, 3 + CGFloat(amount) * 0.5), duration: 0.25)
        if playerTank.isDestroyed {
            effects.explosion(at: playerTank.position, scale: 2.2)
            playSound(.bigExplosion, at: playerTank.position)
            playerTank.showWreck()
            shake(20, duration: 0.6)
        }
    }

    func damageBuilding(_ id: Int, amount: Int) {
        let result = level.damageBuilding(id, by: amount)
        guard result != .none else { return }
        renderer.update(level.buildings[id])
        if result == .destroyed { buildingDestroyed(id) }
    }

    func buildingDestroyed(_ id: Int) {
        let center = level.buildings[id].worldCenter
        effects.explosion(at: center, scale: 2.0)
        effects.dustPuff(at: center)
        playSound(.bigExplosion, at: center)
        shake(10, duration: 0.4)
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Run and verify weapons**

Run: `swift run TanksOfDoom`. Verify:
- Left click fires a shell from the barrel tip with flash, boom and small screen shake; holding left click fires once per 1.2 s.
- Right click / Space fires a stream of bullets that spark on buildings and do nothing else.
- A building hit by shells shows cracks (stage 1), then holes (stage 2), then collapses into rubble with a big explosion; the tank can then drive over the rubble at half speed.
- Firing all 20 shells shows "NO SHELLS" and a click; driving back to base refills to 8.

- [ ] **Step 6: Review Focus #4 — no tunnelling**

Fire the main gun at the narrowest (2-tile) building, from point-blank and from max range, ~10 times each. Expected: every shell explodes on the building's near face; none appear on the far side.

- [ ] **Step 7: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): projectiles, player weapons and destructible buildings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Enemy tanks

**Files:**
- Create: `Sources/TanksOfDoom/EnemyTank.swift`, `Sources/TanksOfDoom/GameScene+Enemies.swift`
- Modify: `Sources/TanksOfDoom/GameScene.swift`, `Sources/TanksOfDoom/GameScene+Player.swift`

**Interfaces:**
- Consumes: `EnemyTankBrain`, `EnemyPerception`, `Difficulty`, `Pathfinder`, `LineOfSight`, `TankNode.move`, `GameScene.fire`, `leaveTracks`, `Hostile`
- Produces:
  - `final class EnemyTank: TankNode, Hostile` — `init(spawn:difficulty:)`, `armor`, `maxArmor`, `update(dt:scene:)`
  - On `GameScene`: stored `enemies: [EnemyTank]`; `allTanks: [TankNode]`, `spawnEnemies()`, `updateEnemies(dt:)`, `hasLineOfSight(from:to:ignoringBuilding:)`, `enemyDestroyed(_:)`

- [ ] **Step 1: Enemy tank node**

`Sources/TanksOfDoom/EnemyTank.swift`:
```swift
import AppKit
import SpriteKit
import TanksCore

final class EnemyTank: TankNode, Hostile {
    static let turnRate: CGFloat = 1.8
    static let turretTurnRate: CGFloat = 1.8

    let maxArmor: Double
    private(set) var armor: Double
    let speed: CGFloat
    let reactionTime: Double
    let patrol: [GridPoint]

    private var brain = EnemyTankBrain()
    private var patrolIndex = 0
    private var path: [CGPoint] = []
    private var repathTimer: Double = 0
    private var stuckTime: Double = 0
    private var reverseTime: Double = 0
    private var fireCooldown: Double = 1
    private var lastKnownPlayer: CGPoint?
    private let healthBack = SKSpriteNode(color: NSColor(white: 0, alpha: 0.6), size: CGSize(width: 42, height: 6))
    private let healthBar = SKSpriteNode(color: .systemRed, size: CGSize(width: 40, height: 4))

    var hitRadius: CGFloat { TankNode.radius }
    var targetKind: TargetKind { .tank }
    var canBeHit: Bool { armor > 0 }

    init(spawn: EnemyTankSpawn, difficulty: Difficulty) {
        maxArmor = Double(difficulty.enemyTankArmor)
        armor = maxArmor
        speed = CGFloat(difficulty.enemyTankSpeed)
        reactionTime = difficulty.enemyReactionTime
        patrol = spawn.patrol
        super.init(hullTexture: Textures.enemyHull, turretTexture: Textures.enemyTurret)
        healthBack.position = CGPoint(x: 0, y: 34)
        healthBack.zPosition = 3
        healthBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        healthBar.position = CGPoint(x: -20, y: 34)
        healthBar.zPosition = 4
        healthBack.isHidden = true
        healthBar.isHidden = true
        addChild(healthBack)
        addChild(healthBar)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyDamage(_ amount: Int, in scene: GameScene) {
        guard armor > 0 else { return }
        armor -= Double(amount)
        healthBack.isHidden = false
        healthBar.isHidden = false
        healthBar.xScale = CGFloat(max(0, armor / maxArmor))
        scene.effects.floatingText("-\(amount)", at: position + CGPoint(x: 0, y: 40), color: .systemYellow)
        if armor <= 0 { scene.enemyDestroyed(self) }
    }

    func update(dt: Double, scene: GameScene) {
        let map = scene.level.map
        let player = scene.playerTank
        let toPlayer = position.distance(to: player.position)
        let sees = !player.isDestroyed && Double(toPlayer) <= EnemyTankBrain.sightRange
            && scene.hasLineOfSight(from: position, to: player.position)
        if sees { lastKnownPlayer = player.position }
        let reachedSearchPoint = lastKnownPlayer.map { position.distance(to: $0) < tileSize } ?? true

        let previous = brain.state
        let perception = EnemyPerception(canSeePlayer: sees, distanceToPlayer: Double(toPlayer),
                                         armorFraction: armor / maxArmor, reachedSearchPoint: reachedSearchPoint)
        let state = brain.update(perception, dt: dt)
        if state != previous {
            path = []
            repathTimer = 0
        }
        repathTimer -= dt
        fireCooldown -= dt

        switch state {
        case .patrol:
            if path.isEmpty && repathTimer <= 0 {
                patrolIndex = (patrolIndex + 1) % patrol.count
                setPath(to: map.center(patrol[patrolIndex]), map: map)
                repathTimer = 0.5
            }
            aimTurret(at: heading, dt: dt)
        case .attack:
            if toPlayer > CGFloat(Combat.spec(.enemyShell).range) * 0.7 {
                if repathTimer <= 0 {
                    setPath(to: player.position, map: map)
                    repathTimer = 1.5
                }
            } else {
                path = []
            }
            engage(player, scene: scene, dt: dt)
        case .search:
            if path.isEmpty && repathTimer <= 0, let target = lastKnownPlayer {
                setPath(to: target, map: map)
                repathTimer = 2
            }
            aimTurret(at: heading, dt: dt)
        case .retreat:
            if path.isEmpty && repathTimer <= 0 {
                let refuge = patrol.max { map.center($0).distance(to: player.position) < map.center($1).distance(to: player.position) } ?? patrol[0]
                setPath(to: map.center(refuge), map: map)
                repathTimer = 2
            }
            if sees { engage(player, scene: scene, dt: dt) } else { aimTurret(at: heading, dt: dt) }
        }
        followPath(dt: dt, scene: scene)
    }

    private func engage(_ player: PlayerTank, scene: GameScene, dt: Double) {
        let angle = position.angle(to: player.position)
        aimTurret(at: angle, dt: dt)
        let aligned = abs(normalizeAngle(turretAngle - angle)) < 0.08
        let ready = brain.timeInState >= reactionTime || brain.state == .retreat
        guard aligned, ready, fireCooldown <= 0, scene.hasLineOfSight(from: position, to: player.position) else { return }
        scene.fire(.enemyShell, from: muzzlePosition, angle: turretAngle + .random(in: -0.06...0.06), byPlayer: false)
        fireCooldown = Combat.spec(.enemyShell).reload
    }

    private func aimTurret(at angle: CGFloat, dt: Double) {
        turretAngle = rotate(turretAngle, toward: angle, maxStep: Self.turretTurnRate * CGFloat(dt))
    }

    private func setPath(to target: CGPoint, map: TileMap) {
        guard let route = Pathfinder.findPath(in: map, from: map.grid(position), to: map.grid(target)) else {
            path = []
            return
        }
        path = route.dropFirst().map { map.center($0) }
    }

    private func followPath(dt: Double, scene: GameScene) {
        let map = scene.level.map
        let step = speed * CGFloat(map.speedMultiplier(at: position.world)) * CGFloat(dt)
        if reverseTime > 0 {
            // Unsticking: back up while turning, then pick a fresh route.
            reverseTime -= dt
            heading += Self.turnRate * 0.5 * CGFloat(dt)
            move(by: CGPoint(angle: heading + .pi, length: step * 0.6), in: map, blockers: scene.allTanks)
            return
        }
        guard let next = path.first else { return }
        if position.distance(to: next) < 14 {
            path.removeFirst()
            return
        }
        let desired = position.angle(to: next)
        heading = rotate(heading, toward: desired, maxStep: Self.turnRate * CGFloat(dt))
        guard abs(normalizeAngle(desired - heading)) < 0.6 else { return }
        let moved = move(by: CGPoint(angle: heading, length: step), in: map, blockers: scene.allTanks)
        scene.leaveTracks(self, moved: moved)
        if moved < step * 0.2 {
            stuckTime += dt
            if stuckTime > 1.0 {
                stuckTime = 0
                path = []
                reverseTime = 0.7
                repathTimer = 0
            }
        } else {
            stuckTime = 0
        }
    }
}
```

- [ ] **Step 2: Scene integration**

`Sources/TanksOfDoom/GameScene+Enemies.swift`:
```swift
import SpriteKit
import TanksCore

extension GameScene {
    var allTanks: [TankNode] {
        var tanks: [TankNode] = [playerTank]
        tanks.append(contentsOf: enemies)
        return tanks
    }

    func spawnEnemies() {
        let difficulty = Difficulty(level: levelNumber)
        for spawn in level.enemyTanks {
            let tank = EnemyTank(spawn: spawn, difficulty: difficulty)
            tank.position = level.map.center(spawn.position)
            tank.heading = .random(in: -.pi ... .pi)
            tank.turretAngle = tank.heading
            worldNode.addChild(tank)
            enemies.append(tank)
        }
    }

    func updateEnemies(dt: Double) {
        for tank in enemies { tank.update(dt: dt, scene: self) }
    }

    func hasLineOfSight(from a: CGPoint, to b: CGPoint, ignoringBuilding: Int? = nil) -> Bool {
        LineOfSight.isClear(in: level.map, from: level.map.grid(a), to: level.map.grid(b), ignoringBuilding: ignoringBuilding)
    }

    func enemyDestroyed(_ tank: EnemyTank) {
        runStats.tanksDestroyed += 1
        effects.explosion(at: tank.position, scale: 1.8)
        playSound(.bigExplosion, at: tank.position)
        shake(8, duration: 0.3)
        let wreck = SKSpriteNode(texture: Textures.enemyHull)
        wreck.color = .black
        wreck.colorBlendFactor = 0.75
        wreck.position = tank.position
        wreck.zRotation = tank.heading
        wreck.zPosition = Z.tracks + 0.5
        worldNode.addChild(wreck)
        tank.removeFromParent()
        enemies.removeAll { $0 === tank }
    }
}
```

In `Sources/TanksOfDoom/GameScene.swift`:
- Replace
  ```swift
      /// Everything the player can shoot. Tasks 11 and 12 add enemy tanks and infantry.
      var hostiles: [Hostile] { [] }
  ```
  with
  ```swift
      var enemies: [EnemyTank] = []
      /// Everything the player can shoot. Task 12 adds infantry.
      var hostiles: [Hostile] { enemies }
  ```
- In `buildWorld()`, directly after `worldNode.addChild(playerTank)`, add `spawnEnemies()`.
- In `update(_:)`, after `updatePlayerWeapons(dt: dt)`, add `updateEnemies(dt: dt)`.

In `Sources/TanksOfDoom/GameScene+Player.swift`, change `in: map, blockers: [])` to `in: map, blockers: enemies)`.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Run and verify enemy tanks**

Run: `swift run TanksOfDoom`; drive toward the far side of the city. Verify:
- Reddish enemy tanks drive patrol routes along roads, turning smoothly and leaving tracks.
- On spotting you (clear line, ≤560 pt) they turn their turret, wait briefly, then fire shells that damage you ("-12", clank, shake); buildings between you block both sight and shells.
- Breaking line of sight makes them drive to where they last saw you, then resume patrol.
- Two main-gun hits destroy a level-1 enemy (60 armor): big explosion, charred wreck remains; its health bar appears after the first hit.
- A heavily damaged enemy backs off toward its patrol area.

- [ ] **Step 5: Review Focus #3 — unsticking**

Park your tank in a 1-wide street in an enemy's patrol path, and separately watch tanks at tight corners for a couple of minutes. Expected: a blocked enemy reverses briefly and takes another route within ~2 s; no tank grinds against a wall or another tank indefinitely.

- [ ] **Step 6: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): roaming enemy tanks with patrol, attack, search and retreat

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Infantry in buildings

**Files:**
- Create: `Sources/TanksOfDoom/InfantryNode.swift`, `Sources/TanksOfDoom/GameScene+Infantry.swift`
- Modify: `Sources/TanksOfDoom/GameScene.swift`, `Sources/TanksOfDoom/GameScene+Combat.swift`

**Interfaces:**
- Consumes: `InfantryBrain`, `InfantrySpawn`, `InfantryKind.weapon`, `LineOfSight`, `GameScene.fire/fireMortar`, `Hostile`, `Building.worldCenter`
- Produces:
  - `final class InfantryNode: SKSpriteNode, Hostile` — `static hitPoints = 12`, `buildingID`, `brain`, `hp`, `cooldown`, `isExposed`
  - On `GameScene`: stored `infantry: [InfantryNode]`, `buildingWindows: [Int: [GridPoint]]`; `spawnInfantry()`, `updateInfantry(dt:)`, `infantryKilled(_:)`, `killOccupants(of:)`

- [ ] **Step 1: Infantry node**

`Sources/TanksOfDoom/InfantryNode.swift`:
```swift
import SpriteKit
import TanksCore

/// A soldier inside a building. Invisible and unhittable unless exposed at a window.
final class InfantryNode: SKSpriteNode, Hostile {
    static let hitPoints = 12

    let buildingID: Int
    var brain: InfantryBrain
    var hp = InfantryNode.hitPoints
    var cooldown: Double = 0

    var isExposed: Bool { brain.state == .exposed }
    var hitRadius: CGFloat { 16 }
    var targetKind: TargetKind { .infantry }
    var canBeHit: Bool { isExposed && hp > 0 }

    init(spawn: InfantrySpawn, initialDelay: Double) {
        buildingID = spawn.buildingID
        brain = InfantryBrain(kind: spawn.kind, initialDelay: initialDelay)
        let texture = Textures.infantry(spawn.kind)
        super.init(texture: texture, color: .clear, size: texture.size())
        zPosition = Z.infantry
        alpha = 0
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyDamage(_ amount: Int, in scene: GameScene) {
        guard hp > 0 else { return }
        hp -= amount
        if hp <= 0 { scene.infantryKilled(self) }
    }
}
```

- [ ] **Step 2: Scene integration**

`Sources/TanksOfDoom/GameScene+Infantry.swift`:
```swift
import SpriteKit
import TanksCore

extension GameScene {
    func spawnInfantry() {
        var rng = SeededRandom(seed: level.seed ^ 0x5EED)
        for building in level.buildings { buildingWindows[building.id] = windows(of: building) }
        for spawn in level.infantry {
            let soldier = InfantryNode(spawn: spawn, initialDelay: Double.random(in: 0...3, using: &rng))
            soldier.position = level.buildings[spawn.buildingID].worldCenter
            worldNode.addChild(soldier)
            infantry.append(soldier)
        }
    }

    /// Perimeter tiles of a building — where a soldier can appear.
    private func windows(of building: Building) -> [GridPoint] {
        let own = Set(building.tiles)
        return building.tiles.filter { t in
            [GridPoint(t.x + 1, t.y), GridPoint(t.x - 1, t.y), GridPoint(t.x, t.y + 1), GridPoint(t.x, t.y - 1)]
                .contains { !own.contains($0) }
        }
    }

    func updateInfantry(dt: Double) {
        let map = level.map
        let player = playerTank.position
        let playerGrid = map.grid(player)
        for soldier in infantry {
            guard let windows = buildingWindows[soldier.buildingID], !windows.isEmpty else { continue }
            let window = windows.min { map.center($0).distance(to: player) < map.center($1).distance(to: player) }!
            let windowPoint = map.center(window)
            let distance = windowPoint.distance(to: player)
            let inRange = Double(distance) <= soldier.brain.range
            let visible = !playerTank.isDestroyed && inRange
                && LineOfSight.isClear(in: map, from: window, to: playerGrid, ignoringBuilding: soldier.buildingID)

            switch soldier.brain.update(dt: dt, playerVisible: visible, distance: playerTank.isDestroyed ? .infinity : Double(distance)) {
            case .expose:
                soldier.position = windowPoint + CGPoint(angle: windowPoint.angle(to: player), length: tileSize * 0.45)
                soldier.removeAllActions()
                soldier.run(.fadeIn(withDuration: 0.15))
                soldier.cooldown = 0.4   // aim before the first shot
            case .hide:
                soldier.removeAllActions()
                soldier.run(.fadeOut(withDuration: 0.25))
            case nil:
                break
            }

            guard soldier.isExposed, !playerTank.isDestroyed else { continue }
            soldier.zRotation = soldier.position.angle(to: player)
            soldier.cooldown -= dt
            guard soldier.cooldown <= 0 else { continue }
            let weapon = soldier.brain.kind.weapon
            soldier.cooldown = Combat.spec(weapon).reload
            if weapon == .mortar {
                fireMortar(from: soldier.position, at: player + CGPoint(x: .random(in: -50...50), y: .random(in: -50...50)))
            } else if visible {
                fire(weapon, from: soldier.position, angle: soldier.zRotation + .random(in: -0.07...0.07),
                     byPlayer: false, ownerBuilding: soldier.buildingID)
            }
        }
    }

    func infantryKilled(_ soldier: InfantryNode) {
        runStats.infantryKilled += 1
        if soldier.alpha > 0 { effects.dustPuff(at: soldier.position) }
        soldier.removeFromParent()
        infantry.removeAll { $0 === soldier }
    }

    func killOccupants(of buildingID: Int) {
        for soldier in infantry where soldier.buildingID == buildingID {
            infantryKilled(soldier)
        }
    }
}
```

In `Sources/TanksOfDoom/GameScene.swift`:
- Replace
  ```swift
      /// Everything the player can shoot. Task 12 adds infantry.
      var hostiles: [Hostile] { enemies }
  ```
  with
  ```swift
      var infantry: [InfantryNode] = []
      var buildingWindows: [Int: [GridPoint]] = [:]
      /// Everything the player can shoot.
      var hostiles: [Hostile] { (enemies as [Hostile]) + (infantry as [Hostile]) }
  ```
- In `buildWorld()`, after `spawnEnemies()`, add `spawnInfantry()`.
- In `update(_:)`, after `updateEnemies(dt: dt)`, add `updateInfantry(dt: dt)`.

In `Sources/TanksOfDoom/GameScene+Combat.swift`, at the start of `buildingDestroyed(_:)` add:
```swift
        killOccupants(of: id)
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Run and verify infantry**

Run: `swift run TanksOfDoom`; drive out of the base area into the city. Verify:
- Soldiers pop up at the building edge facing you, fire (rifle tracers, MG bursts, slow smoking bazooka rockets you can dodge), then duck back in and vanish.
- Mortar soldiers (level 2+, or force-test by temporarily starting at level 3 from the title closure — revert afterwards) show a pulsing red circle where the shell will land ~1.8 s later.
- Machine gun or a main-gun hit kills an exposed soldier (dust puff); hidden soldiers can't be hit.
- No soldiers fire from buildings near the base.
- **Review Focus #5:** shell a building while one of its soldiers is exposed and firing. On collapse the soldier disappears at once, never fires again, and any rocket already in flight continues and behaves normally.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): infantry popping up in buildings with four weapon types

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: HUD and minimap

**Files:**
- Create: `Sources/TanksOfDoom/HUD.swift`, `Sources/TanksOfDoom/Minimap.swift`, `Sources/TanksOfDoom/GameScene+HUD.swift`
- Modify: `Sources/TanksOfDoom/GameScene.swift`, `Sources/TanksOfDoom/GameScene+Input.swift`, `Sources/TanksOfDoom/GameScene+Combat.swift`

**Interfaces:**
- Consumes: `TankStats`, `TileMap`, `Tile`, `GameScene.enemies`, `hasLineOfSight`
- Produces:
  - `final class Minimap: SKNode` — `init(map:)`, `displaySize`, `toggleSize()`, `refresh(map:)`, `update(player:enemies:)`
  - `final class HUD: SKNode` — `init(level:)`, `minimap`, `layout(size:)`, `update(stats:level:enemiesLeft:inBase:)`, `flash(_:color:duration:)`, `setPaused(_:)`, `toggleMinimap()`
  - On `GameScene`: stored `hud: HUD!`; `setUpHUD()`, `updateHUD()`, `handleKeyPress(_:)`

- [ ] **Step 1: Minimap**

`Sources/TanksOfDoom/Minimap.swift`:
```swift
import AppKit
import SpriteKit
import TanksCore

/// One pixel per tile, scaled up. Shows the player and currently spotted enemy tanks — never caches.
final class Minimap: SKNode {
    private(set) var displaySize: CGFloat = 200
    private let frameNode = SKSpriteNode(color: NSColor(white: 0, alpha: 0.7), size: .zero)
    private let mapSprite: SKSpriteNode
    private let playerDot = SKShapeNode(circleOfRadius: 3.5)
    private var enemyDots: [SKShapeNode] = []
    private let worldSize: CGSize

    init(map: TileMap) {
        worldSize = CGSize(width: CGFloat(map.width) * tileSize, height: CGFloat(map.height) * tileSize)
        mapSprite = SKSpriteNode(texture: Minimap.texture(for: map))
        super.init()
        frameNode.anchorPoint = .zero
        mapSprite.anchorPoint = .zero
        frameNode.zPosition = 0
        mapSprite.zPosition = 1
        playerDot.fillColor = .systemGreen
        playerDot.strokeColor = .white
        playerDot.lineWidth = 1
        playerDot.zPosition = 3
        addChild(frameNode)
        addChild(mapSprite)
        addChild(playerDot)
        resize()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func toggleSize() {
        displaySize = displaySize < 300 ? 400 : 200
        resize()
    }

    func refresh(map: TileMap) {
        mapSprite.texture = Minimap.texture(for: map)
    }

    func update(player: CGPoint, enemies: [CGPoint]) {
        playerDot.position = project(player)
        while enemyDots.count < enemies.count {
            let dot = SKShapeNode(circleOfRadius: 3.5)
            dot.fillColor = .systemRed
            dot.strokeColor = .clear
            dot.zPosition = 2
            addChild(dot)
            enemyDots.append(dot)
        }
        for (index, dot) in enemyDots.enumerated() {
            dot.isHidden = index >= enemies.count
            if index < enemies.count { dot.position = project(enemies[index]) }
        }
    }

    private func resize() {
        frameNode.size = CGSize(width: displaySize + 6, height: displaySize + 6)
        frameNode.position = CGPoint(x: -3, y: -3)
        mapSprite.size = CGSize(width: displaySize, height: displaySize)
    }

    private func project(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / worldSize.width * displaySize, y: p.y / worldSize.height * displaySize)
    }

    static func texture(for map: TileMap) -> SKTexture {
        let ctx = CGContext(data: nil, width: map.width, height: map.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<map.height {
            for x in 0..<map.width {
                ctx.setFillColor(color(for: map[x: x, y: y]))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let texture = SKTexture(cgImage: ctx.makeImage()!)
        texture.filteringMode = .nearest
        return texture
    }

    private static func color(for tile: Tile) -> CGColor {
        switch tile {
        case .road: return Textures.color(0.45, 0.45, 0.45)
        case .building: return Textures.color(0.22, 0.18, 0.15)
        case .rubble: return Textures.color(0.35, 0.3, 0.25)
        case .park: return Textures.color(0.25, 0.35, 0.18)
        case .crater: return Textures.color(0.28, 0.22, 0.15)
        case .base: return Textures.color(0.2, 0.45, 0.9)
        case .wall: return Textures.color(0, 0, 0)
        }
    }
}
```

- [ ] **Step 2: HUD**

`Sources/TanksOfDoom/HUD.swift`:
```swift
import AppKit
import SpriteKit
import TanksCore

extension SKLabelNode {
    static func hud(size: CGFloat) -> SKLabelNode {
        make("", size: size, color: .white, font: "Menlo-Bold")
    }
}

/// A labelled horizontal bar.
final class StatBar: SKNode {
    static let width: CGFloat = 180
    static let height: CGFloat = 14
    private let fill: SKSpriteNode

    init(title: String, color: NSColor) {
        fill = SKSpriteNode(color: color, size: CGSize(width: Self.width, height: Self.height))
        super.init()
        let label = SKLabelNode.hud(size: 14)
        label.text = title
        label.horizontalAlignmentMode = .left
        label.zPosition = 2
        let back = SKSpriteNode(color: NSColor(white: 0, alpha: 0.6), size: CGSize(width: Self.width + 4, height: Self.height + 4))
        back.anchorPoint = CGPoint(x: 0, y: 0.5)
        back.position = CGPoint(x: 68, y: 0)
        back.zPosition = 0
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: 70, y: 0)
        fill.zPosition = 1
        addChild(label)
        addChild(back)
        addChild(fill)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func set(_ fraction: Double) {
        fill.xScale = CGFloat(max(0, min(1, fraction)))
    }
}

/// Screen-space overlay attached to the camera (origin at the screen centre).
final class HUD: SKNode {
    let minimap: Minimap
    private let armorBar = StatBar(title: "ARMOR", color: .systemRed)
    private let fuelBar = StatBar(title: "FUEL", color: .systemOrange)
    private let ammoLabel = SKLabelNode.hud(size: 15)
    private let levelLabel = SKLabelNode.hud(size: 18)
    private let enemiesLabel = SKLabelNode.hud(size: 18)
    private let statusLabel = SKLabelNode.hud(size: 18)
    private let messageLabel = SKLabelNode.make("", size: 34)
    private let pausedLabel = SKLabelNode.make("PAUSED", size: 64)
    private var lastSize = CGSize.zero

    init(level: Level) {
        minimap = Minimap(map: level.map)
        super.init()
        zPosition = Z.hud
        ammoLabel.horizontalAlignmentMode = .left
        levelLabel.horizontalAlignmentMode = .right
        enemiesLabel.horizontalAlignmentMode = .right
        messageLabel.alpha = 0
        pausedLabel.isHidden = true
        for node in [armorBar, fuelBar, ammoLabel, levelLabel, enemiesLabel, statusLabel, messageLabel, pausedLabel, minimap] as [SKNode] {
            addChild(node)
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func layout(size: CGSize) {
        lastSize = size
        let left = -size.width / 2 + 20
        let right = size.width / 2 - 20
        let top = size.height / 2 - 24
        let bottom = -size.height / 2
        armorBar.position = CGPoint(x: left, y: top)
        fuelBar.position = CGPoint(x: left, y: top - 26)
        ammoLabel.position = CGPoint(x: left, y: top - 54)
        levelLabel.position = CGPoint(x: right, y: top)
        enemiesLabel.position = CGPoint(x: right, y: top - 26)
        statusLabel.position = CGPoint(x: 0, y: bottom + 40)
        messageLabel.position = CGPoint(x: 0, y: size.height / 2 - 110)
        pausedLabel.position = .zero
        minimap.position = CGPoint(x: right - minimap.displaySize, y: bottom + 20)
    }

    func update(stats: TankStats, level: Int, enemiesLeft: Int, inBase: Bool) {
        armorBar.set(stats.armor / TankStats.maxArmor)
        fuelBar.set(stats.fuel / TankStats.maxFuel)
        ammoLabel.text = "SHELLS \(stats.shells)/\(TankStats.maxShells)   MG \(stats.rounds)/\(TankStats.maxRounds)"
        levelLabel.text = "LEVEL \(level)"
        enemiesLabel.text = "ENEMY TANKS: \(enemiesLeft)"
        if inBase {
            statusLabel.text = "AT BASE: REPAIRING AND RESUPPLYING"
            statusLabel.fontColor = .systemGreen
        } else if stats.fuel <= 0 && !stats.isDestroyed {
            statusLabel.text = "OUT OF FUEL"
            statusLabel.fontColor = .systemRed
        } else {
            statusLabel.text = ""
        }
    }

    func flash(_ text: String, color: NSColor = .white, duration: Double = 2) {
        messageLabel.text = text
        messageLabel.fontColor = color
        messageLabel.removeAllActions()
        messageLabel.alpha = 1
        messageLabel.run(.sequence([.wait(forDuration: duration), .fadeOut(withDuration: 0.5)]))
    }

    func setPaused(_ paused: Bool) {
        pausedLabel.isHidden = !paused
    }

    func toggleMinimap() {
        minimap.toggleSize()
        layout(size: lastSize)
    }
}
```

- [ ] **Step 3: Scene integration**

`Sources/TanksOfDoom/GameScene+HUD.swift`:
```swift
import SpriteKit
import TanksCore

extension GameScene {
    func setUpHUD() {
        hud = HUD(level: level)
        cameraNode.addChild(hud)
        hud.layout(size: size)
        hud.flash("LEVEL \(levelNumber): DESTROY \(enemies.count) ENEMY TANKS", duration: 3)
    }

    func updateHUD() {
        hud.update(stats: playerTank.stats, level: levelNumber, enemiesLeft: enemies.count, inBase: inBase)
        let spotted = enemies
            .filter { $0.position.distance(to: playerTank.position) <= 900 && hasLineOfSight(from: playerTank.position, to: $0.position) }
            .map(\.position)
        hud.minimap.update(player: playerTank.position, enemies: spotted)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        hud?.layout(size: size)
    }
}
```

In `Sources/TanksOfDoom/GameScene.swift`:
- After `var effects: Effects!` add `var hud: HUD!`.
- At the end of `buildWorld()` (after `cameraNode.addChild(crosshair)`) add `setUpHUD()`.
- In `update(_:)`, after `updateCamera(dt: dt)`, add `updateHUD()`.

In `Sources/TanksOfDoom/GameScene+Input.swift`, replace `keyDown(with:)` with:
```swift
    override func keyDown(with event: NSEvent) {
        setKey(event.keyCode, down: true)
        if !event.isARepeat { handleKeyPress(event.keyCode) }
    }

    func handleKeyPress(_ code: UInt16) {
        switch code {
        case 46: hud.toggleMinimap()   // M
        default: break
        }
    }
```

In `Sources/TanksOfDoom/GameScene+Combat.swift`, at the end of `buildingDestroyed(_:)` add:
```swift
        hud.minimap.refresh(map: level.map)
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Run and verify the HUD**

Run: `swift run TanksOfDoom`. Verify:
- On start, "LEVEL 1: DESTROY 3 ENEMY TANKS" shows for 3 s then fades.
- Top-left armor and fuel bars, shell/MG counts; top-right level and enemy count — all update live (fire a shell, take a hit, burn fuel, collect a cache).
- Parking on the base shows the green "AT BASE…" status and the armor bar refills.
- Bottom-right minimap: roads, buildings, blue base, green player dot moving; red dots only for enemy tanks you can currently see; no cache markers. A destroyed building turns into rubble colour on the minimap. M toggles 200/400 px and the minimap stays anchored to the bottom-right corner.
- **Review Focus #2:** resize the window; all HUD elements re-anchor to the new corners.

- [ ] **Step 6: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): HUD with stat bars, messages and minimap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Game flow — win/lose, level progression, pause, abandon, high score

**Files:**
- Create: `Sources/TanksOfDoom/GameScene+Flow.swift`
- Modify: `Sources/TanksOfDoom/GameScene.swift`, `Sources/TanksOfDoom/GameScene+Input.swift`, `Sources/TanksOfDoom/MenuScene.swift`, `Sources/TanksOfDoom/HUD.swift`

**Interfaces:**
- Consumes: `HighScores.record`, `RunStats`, `MenuScene`, `HUD.flash/setPaused`, `damagePlayer`
- Produces: `MenuScene.levelComplete(size:runStats:level:)`, `MenuScene.gameOver(size:runStats:newBest:)`; on `GameScene`: stored `isGamePaused`, `endTimer`, `victory`, `levelOver`; `togglePause()`, `abandonTank()`, `checkLevelEnd(dt:)`

- [ ] **Step 1: Level complete and game over screens**

Append to `Sources/TanksOfDoom/MenuScene.swift`:
```swift
extension MenuScene {
    static func levelComplete(size: CGSize, runStats: RunStats, level: Int) -> MenuScene {
        let lines = [
            Line(text: "LEVEL \(level) CLEARED", size: 72, color: .systemGreen),
            Line(text: "Enemy tanks destroyed: \(runStats.tanksDestroyed)   Infantry killed: \(runStats.infantryKilled)",
                 size: 20, font: "Menlo-Bold"),
            Line(text: "The next city is more dangerous.", size: 24),
        ]
        return MenuScene(size: size, lines: lines, prompt: "PRESS ENTER FOR LEVEL \(level + 1)") { scene in
            let game = GameScene(size: scene.size, levelNumber: level + 1, runStats: runStats)
            scene.view?.presentScene(game, transition: .fade(withDuration: 0.6))
        }
    }

    static func gameOver(size: CGSize, runStats: RunStats, newBest: Bool) -> MenuScene {
        let mono = "Menlo-Bold"
        let lines = [
            Line(text: "GAME OVER", size: 88, color: .systemRed),
            Line(text: "Levels cleared: \(runStats.levelsCleared)   Kills: \(runStats.kills)", size: 22, font: mono),
            newBest
                ? Line(text: "NEW BEST RUN!", size: 30, color: .systemYellow)
                : Line(text: "Best run: \(HighScores.bestLevels) levels, \(HighScores.bestKills) kills", size: 20, color: .lightGray, font: mono),
        ]
        return MenuScene(size: size, lines: lines, prompt: "PRESS ENTER TO CONTINUE") { scene in
            scene.view?.presentScene(MenuScene.title(size: scene.size), transition: .fade(withDuration: 0.6))
        }
    }
}
```

- [ ] **Step 2: Flow logic**

`Sources/TanksOfDoom/GameScene+Flow.swift`:
```swift
import AppKit
import SpriteKit
import TanksCore

extension GameScene {
    func togglePause() {
        guard endTimer == nil else { return }
        isGamePaused.toggle()
        worldNode.isPaused = isGamePaused
        input = InputState()
        hud.setPaused(isGamePaused)
    }

    /// Lets a player stranded without fuel end the run instead of being soft-locked.
    func abandonTank() {
        guard !isGamePaused, endTimer == nil, !playerTank.isDestroyed, playerTank.stats.fuel <= 0 else { return }
        damagePlayer(Int(playerTank.stats.armor.rounded(.up)))
    }

    func checkLevelEnd(dt: Double) {
        guard !levelOver else { return }
        if let remaining = endTimer {
            endTimer = remaining - dt
            if remaining - dt <= 0 { finishLevel() }
            return
        }
        if playerTank.isDestroyed {
            victory = false
            endTimer = 2.5
            hud.flash("TANK DESTROYED", color: .systemRed, duration: 2.5)
        } else if enemies.isEmpty {
            victory = true
            endTimer = 2.0
            hud.flash("LEVEL CLEAR!", color: .systemGreen, duration: 2)
        }
    }

    private func finishLevel() {
        levelOver = true
        guard let view else { return }
        if victory {
            runStats.levelsCleared += 1
            view.presentScene(MenuScene.levelComplete(size: size, runStats: runStats, level: levelNumber),
                              transition: .fade(withDuration: 0.8))
        } else {
            let newBest = HighScores.record(runStats)
            view.presentScene(MenuScene.gameOver(size: size, runStats: runStats, newBest: newBest),
                              transition: .fade(withDuration: 0.8))
        }
    }
}
```

In `Sources/TanksOfDoom/GameScene.swift`:
- After `var inBase = false` add:
  ```swift
      var isGamePaused = false
      var endTimer: Double?
      var victory = false
      var levelOver = false
  ```
- Replace the body of `update(_:)` with:
  ```swift
          let dt = lastUpdate == 0 ? 1.0 / 60 : min(currentTime - lastUpdate, 1.0 / 30)
          lastUpdate = currentTime
          guard !isGamePaused, !levelOver else { return }
          updatePlayer(dt: dt)
          updatePlayerWeapons(dt: dt)
          updateEnemies(dt: dt)
          updateInfantry(dt: dt)
          updateProjectiles(dt: dt)
          updateMortars(dt: dt)
          updateCamera(dt: dt)
          updateHUD()
          checkLevelEnd(dt: dt)
  ```

In `Sources/TanksOfDoom/GameScene+Input.swift`, replace the `switch` in `handleKeyPress(_:)` with:
```swift
        switch code {
        case 46: hud.toggleMinimap()   // M
        case 53: togglePause()         // Esc
        case 15: abandonTank()         // R
        default: break
        }
```

In `Sources/TanksOfDoom/HUD.swift`, change `statusLabel.text = "OUT OF FUEL"` to:
```swift
            statusLabel.text = "OUT OF FUEL: PRESS R TO ABANDON TANK"
```

- [ ] **Step 3: Build and run the full test suite**

Run: `swift build && swift test`
Expected: `Build complete!` and all core tests pass.

- [ ] **Step 4: Run and verify the full loop**

Run: `swift run TanksOfDoom`. Verify:
- Destroying all enemy tanks: "LEVEL CLEAR!", ~2 s later the Level Complete screen with kill counts; Enter starts level 2 with a different city, 4 enemy tanks, tougher infantry (mortars possible).
- Esc pauses (everything freezes, "PAUSED" shown, mortar markers stop blinking); Esc again resumes with no keys stuck.
- Letting enemies destroy the tank: big explosion, charred hull, "TANK DESTROYED", then Game Over with levels cleared and kills; a better run shows "NEW BEST RUN!" and the title screen then shows the best run.
- **Review Focus #1:** drive far from base until fuel hits 0 (or temporarily set `TankStats.fuelPerSecondMoving` to 20 — revert afterwards). HUD shows "OUT OF FUEL: PRESS R TO ABANDON TANK"; the turret still aims and fires; pressing R ends the run via the Game Over screen. R does nothing while fuel remains.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): level progression, pause, abandon tank and high score

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** Package/targets (T1, T8); seeded RNG (T1); tile rules (T2); A*/LOS (T3); buildings/difficulty (T4); generator steps 1–8 (T5); weapons + stats + base/caches (T6); both AI brains (T7); window/scenes (T8, T14); procedural art + synthesized audio (T9); driving, fuel, turret, pickups, base, camera (T9); projectiles, splash, building damage stages + collapse to rubble (T10); enemy tanks patrol/attack/search/retreat with reaction time and scaling (T11); infantry types, pop-up, mortar markers, collapse kills occupants (T12); HUD bars, counter, minimap with spotted enemies only, floating text (T9–T13); flow, best run in UserDefaults, pause, M, R (T13–T14). Out-of-scope items are not implemented.
- **Type consistency:** `GameScene(size:levelNumber:runStats:)` is used by T9 (title), T14 (level complete); `hostiles` evolves T10 → T11 → T12 by explicit replacement; `update(_:)` body is restated in full in T14.
