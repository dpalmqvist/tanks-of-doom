# Online Multiplayer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A two-player online versus mode: two Macs connect through a relay server by room code and fight with lives and random respawns in a generated city that also contains AI tanks and infantry.

**Architecture:** The host's `GameScene` is the only simulation. It drives two `Player`s (local keys plus the guest's streamed inputs) and sends 20 Hz snapshots carrying batched effect events. The guest's `GameScene` builds the same city from the seed, interpolates everything 100 ms in the past, and predicts its own tank's movement. Pure rules live in `TanksCore` (match state, respawn picking, two-base cities). The wire format lives in a new `TanksNet` library. A SwiftNIO relay (`TanksRelayCore` + `TanksRelay`) pairs players by a 5-letter code and forwards frames.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, SpriteKit, AppKit, Foundation `URLSessionWebSocketTask`, SwiftNIO 2 (relay only), Swift Testing, Docker.

**Spec:** `docs/superpowers/specs/2026-10-09-multiplayer-design.md`

## Global Constraints

- macOS 14+ for the game (`platforms: [.macOS(.v14)]`). The relay must also build on Linux in the `swift:6.0` Docker image, so `TanksCore`, `TanksNet`, `TanksRelayCore`, `TanksRelay` import only Foundation and SwiftNIO.
- `swiftLanguageModes: [.v5]` stays. Don't add language features newer than Swift 6.0.
- The game app (`TanksOfDoom`) gets **no third-party dependency**. SwiftNIO is used only by `TanksRelayCore`/`TanksRelay`.
- **The single-player campaign must behave exactly as before.** The existing tests must keep passing, and `CityGenerator.generate(seed:level:)` must keep producing byte-identical cities (pinned by fingerprints in Task 1).
- Exactly 2 players. Lives 1–9, default 3. AI intensity Light/Normal/Heavy = `Difficulty(level:)` 1/3/6.
- Respawn delay 3 s; invulnerability 3 s, ended early by firing; player respawn ≥ 15 tiles from opponent and ≥ 8 from AI tanks, relaxed down to 0.
- AI tanks respawn after 20 s (≥ 15 tiles from both players); infantry after 30 s if their building stands; pickups 45 s after collection.
- Snapshots 20 Hz, guest inputs 30 Hz, interpolation delay 100 ms, prediction correction: < 2 px ignored, > 64 px snaps, otherwise eased over 100 ms.
- Guest keys released if no guest input for 250 ms. "Connection lost…" after 3 s of silence; the remaining player wins after 10 s or immediately on `peerLeft`/`leave`.
- Relay: `PORT` (default 8080), `ROOM_TTL` (default 600 s), 64 KB max frame, 100 frames/s per connection, 500 rooms. Room codes are 5 letters from `ABCDEFGHJKLMNPQRSTUVWXYZ` (no I or O).
- Relay URL: `RelayConfig.defaultURL`, overridable with the `TANKS_RELAY_URL` environment variable.
- Run everything from the repo root: `swift build`, `swift test`, `swift run TanksOfDoom`, `swift run TanksRelay`.
- Commit after every task on branch `feat/multiplayer`. Commit messages end with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Guest's network stalls while a key is held.** The guest's tank must stop rather than drive off on its own. Pinned by `RemoteInput` staleness tests in Task 8.
2. **Hostile or corrupt bytes reach the relay or the game:** truncated frames, garbage, absurd array counts, NaN floats, oversize strings. Decoders must throw, never trap or allocate unbounded memory, and the relay must close only the offending connection. Pinned by every-prefix truncation and garbage tests in Task 8 and the relay misuse tests in Task 9.
3. **Room code typed in lower case, with spaces, or with the confusable letters I/O.** Must be normalized or rejected before it reaches the relay. Pinned by `TanksNet.normalizeRoomCode` tests in Task 7.
4. **Both players lose their last life in the same frame** (one splash). The match must end once, with exactly one winner (the first death processed decides), and must not underflow lives or flip the winner. Pinned by a `MatchState` test in Task 2.
5. **Snapshots arrive duplicated, out of order, or after a long gap.** Stale ones are dropped and the render clock never runs backwards or past the newest data. Pinned by `SnapshotBuffer` tests in Task 8.

---

## File Structure

```
Package.swift                                  + TanksNet, TanksRelayCore, TanksRelay, swift-nio dependency
Package.resolved                               new (pins swift-nio)
Dockerfile                                     new: relay image
docs/relay.md                                  new: running and deploying the relay
README.md                                      multiplayer section

Sources/TanksCore/
  Level.swift              BaseSite, Level.bases, baseIndex(at:), setBuildingHP(_:to:)
  CityGenerator.swift      generate(seed:level:bases:) with a mirrored second base
  Match.swift              new: PlayerSlot, AIIntensity, MatchSettings, Combatant, KillFeed, MatchState
  Respawn.swift            new: RespawnPicker, RespawnQueue, VersusTimings

Sources/TanksNet/                               new library (Foundation + TanksCore)
  Wire.swift               ByteWriter, ByteReader, WireError, Vec2
  TanksNet.swift           protocol version, room codes
  RelayMessage.swift       relay control frames (types 1–31)
  GameMessage.swift        InputFrame, snapshots, GameEvent, GameMessage (types 32+)
  NetSync.swift            RemoteInput, SnapshotBuffer, InputHistory, lerp helpers

Sources/TanksRelayCore/                         new library (TanksNet + SwiftNIO)
  RoomRegistry.swift       rooms and pairing
  RelayCore.swift          per-frame relay decisions as plain values + FrameRateLimiter
  RelayServer.swift        SwiftNIO WebSocket server around RelayCore
Sources/TanksRelay/main.swift                   new executable

Sources/TanksOfDoom/
  Player.swift             new: Player, PlayerSlot colours
  GameMode.swift           new: GameMode, VersusRole
  GameScene.swift          players/localPlayer, inits for campaign and versus, update loop per role
  GameScene+Player.swift   per-player movement (drive), pickups
  GameScene+Combat.swift   shooter-aware projectiles, splash and damage, FX funnel call sites
  GameScene+Aiming.swift   per-player turret aim and target lock
  GameScene+Enemies.swift  addEnemy, aiTarget, wrecks
  GameScene+Infantry.swift AI targets nearest player, addSoldier
  GameScene+HUD.swift      local-player HUD + versus HUD state
  GameScene+Flow.swift     abandon/pause/level end per mode
  GameScene+Input.swift    local keys, hot-seat keys, guest presses
  GameScene+Versus.swift   new: match rules, respawns, wrecks, match end
  GameScene+FX.swift       new: fx(_:for:) funnel and playLocally(_:)
  GameScene+Host.swift     new: guest input, snapshot building, link upkeep
  GameScene+Guest.swift    new: snapshot mirroring, interpolation, prediction
  GuestWorld.swift         new: guest-side node registry and buffers
  RelayConnection.swift    new: URLSessionWebSocketTask wrapper, RelayConfig
  MatchLink.swift          new: ping/latency/silence on top of a connection
  QuickMatch.swift         new: TANKS_HOST / TANKS_JOIN developer shortcut
  LobbyScene.swift         new: host/join lobby
  VersusResultScene.swift  new: result screen with rematch
  MenuScene.swift          title menu (1 campaign / 2 multiplayer), multiplayer menu
  HUD.swift, Minimap.swift lives, kill feed, respawn countdown, latency, opponent dot
  Tanks.swift              PlayerTank(slot:) is Hostile, respawn(at:heading:)
  Projectile.swift         Hostile gains netID/applyDamage(from:); Projectile.shooter
  EnemyTank.swift          netID, spawn, targets nearest player, showHealth
  InfantryNode.swift       netID, kind
  Pickups.swift            isAvailable instead of removal
  Textures.swift           guest colour scheme
  Audio.swift              Sound = TanksNet.SoundID
  AppDelegate.swift        TANKS_HOTSEAT, QuickMatch

Tests/TanksCoreTests/      MultiBaseTests, MatchTests, RespawnTests (new)
Tests/TanksNetTests/       WireTests, MessageTests, NetSyncTests (new)
Tests/TanksRelayCoreTests/ RoomRegistryTests, RelayCoreTests, RelayServerTests (new)
```

---

## Phase A: Match rules in TanksCore

### Task 1: Two-base cities, base lookup and building HP mirroring

**Files:**
- Modify: `Sources/TanksCore/Level.swift`
- Modify: `Sources/TanksCore/CityGenerator.swift`
- Test: `Tests/TanksCoreTests/MultiBaseTests.swift` (new)

**Interfaces:**
- Consumes: existing `Level`, `TileMap`, `CityGenerator`.
- Produces:
  - `public struct BaseSite: Equatable, Sendable { public let center: GridPoint; public let tiles: [GridPoint] }`
  - `Level.bases: [BaseSite]` (campaign: one entry equal to `baseCenter`/`baseTiles`), new trailing init parameter `bases: [BaseSite]? = nil`
  - `Level.baseIndex(at: GridPoint) -> Int?`
  - `mutating Level.setBuildingHP(_ id: Int, to hp: Int) -> BuildingHitResult`
  - `CityGenerator.generate(seed: UInt64, level: Int, bases: Int = 1) -> Level`. With 2 bases, `bases[0].center == GridPoint(6, 6)` and `bases[1].center == GridPoint(74, 74)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TanksCoreTests/MultiBaseTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MultiBaseTests`
Expected: compile errors: `cannot find 'BaseSite' in scope`, `extra argument 'bases' in call`, `value of type 'Level' has no member 'setBuildingHP'`.

- [ ] **Step 3: Add `BaseSite`, `Level.bases`, `baseIndex(at:)` and `setBuildingHP(_:to:)`**

In `Sources/TanksCore/Level.swift`, add above `public struct Level`:

```swift
/// A home base: where a player starts and repairs.
public struct BaseSite: Equatable, Sendable {
    public let center: GridPoint
    public let tiles: [GridPoint]

    public init(center: GridPoint, tiles: [GridPoint]) {
        self.center = center
        self.tiles = tiles
    }
}
```

In `public struct Level`, add the property after `enemyTanks`:

```swift
    /// Every base; the campaign has one (the same as `baseCenter`/`baseTiles`), versus has one per player.
    public let bases: [BaseSite]
```

Replace the initializer with:

```swift
    public init(number: Int, seed: UInt64, map: TileMap, buildings: [Building], baseTiles: [GridPoint],
                baseCenter: GridPoint, caches: [Cache], infantry: [InfantrySpawn], enemyTanks: [EnemyTankSpawn],
                bases: [BaseSite]? = nil) {
        self.number = number
        self.seed = seed
        self.map = map
        self.buildings = buildings
        self.baseTiles = baseTiles
        self.baseCenter = baseCenter
        self.caches = caches
        self.infantry = infantry
        self.enemyTanks = enemyTanks
        self.bases = bases ?? [BaseSite(center: baseCenter, tiles: baseTiles)]
    }
```

Add after `isBase(_:)`:

```swift
    /// Which base `p` belongs to, if any.
    public func baseIndex(at p: GridPoint) -> Int? {
        guard map[p] == .base else { return nil }
        return bases.firstIndex { $0.tiles.contains(p) }
    }
```

Add after `damageBuilding(_:by:)`:

```swift
    /// Brings a building down to `hp` as reported by the host. Buildings never heal, so a higher value is ignored.
    public mutating func setBuildingHP(_ id: Int, to hp: Int) -> BuildingHitResult {
        guard buildings.indices.contains(id), hp < buildings[id].hp else { return .none }
        return damageBuilding(id, by: buildings[id].hp - hp)
    }
```

- [ ] **Step 4: Teach the generator to place a second base**

In `Sources/TanksCore/CityGenerator.swift`, replace `generate(seed:level:)` and the head of `build` with:

```swift
    public static func generate(seed: UInt64, level: Int, bases: Int = 1) -> Level {
        precondition((1...2).contains(bases), "a city has one base (campaign) or two (versus)")
        for attempt in 0..<100 {
            var rng = SeededRandom(seed: seed &+ UInt64(attempt) &* 0x9E37_79B9_7F4A_7C15)
            if let city = build(seed: seed, level: max(1, level), baseCount: bases, rng: &rng) { return city }
        }
        fatalError("CityGenerator could not build a valid city for seed \(seed)")
    }

    /// Bottom-left for the campaign and the host; the mirror-image top-right corner for the guest.
    static func baseOrigins(count: Int) -> [GridPoint] {
        let far = mapSize - 3 - baseSize
        return Array([baseOrigin, GridPoint(far, far)].prefix(count))
    }

    static func build(seed: UInt64, level number: Int, baseCount: Int, rng: inout SeededRandom) -> Level? {
```

Replace section 3 ("Home base") with:

```swift
        // 3. Home bases. Placing them uses no randomness, so one-base cities stay exactly as before.
        var sites: [BaseSite] = []
        for origin in baseOrigins(count: baseCount) {
            var tiles: [GridPoint] = []
            for y in origin.y..<(origin.y + baseSize) {
                for x in origin.x..<(origin.x + baseSize) {
                    map[x: x, y: y] = .base
                    tiles.append(GridPoint(x, y))
                }
            }
            sites.append(BaseSite(center: GridPoint(origin.x + baseSize / 2, origin.y + baseSize / 2), tiles: tiles))
        }
        let baseCenter = sites[0].center
        let baseCenters = sites.map(\.center)
        func distanceToNearestBase(_ p: GridPoint) -> Double {
            baseCenters.map { $0.distance(to: p) }.min()!
        }
```

Then make these replacements in the rest of `build`:

- After `guard roads.allSatisfy(reachable.contains) else { return nil }` add:
  ```swift
          guard baseCenters.allSatisfy(reachable.contains) else { return nil }
  ```
- In section 5: `roads.filter { $0.distance(to: baseCenter) >= minTankDistanceFromBase }` → `roads.filter { distanceToNearestBase($0) >= minTankDistanceFromBase }`
- In section 6: `guard reachable.contains(p), p.distance(to: baseCenter) >= safeZoneRadius else { return false }` → `guard reachable.contains(p), distanceToNearestBase(p) >= safeZoneRadius else { return false }`
- In section 6: `let weights = candidates.map { $0.distance(to: baseCenter) }` → `let weights = candidates.map(distanceToNearestBase)`
- In section 7: `guard center.distance(to: baseCenter) >= safeZoneRadius + 2, rng.chance(...)` → `guard distanceToNearestBase(center) >= safeZoneRadius + 2, rng.chance(difficulty.infantryChance) else { continue }`
- The final `return Level(...)`:
  ```swift
          return Level(number: number, seed: seed, map: map, buildings: buildings, baseTiles: sites[0].tiles,
                       baseCenter: baseCenter, caches: caches, infantry: infantry, enemyTanks: tanks, bases: sites)
  ```

With one base, `distanceToNearestBase(p) == p.distance(to: baseCenter)`, so the random sequence and every decision are unchanged. The fingerprint test proves it.

- [ ] **Step 5: Run the tests**

Run: `swift test --filter TanksCoreTests`
Expected: all tests pass, including the existing `CityGeneratorTests` and `singleBaseCitiesAreUnchanged`.

- [ ] **Step 6: Commit**

```bash
git add Sources/TanksCore/Level.swift Sources/TanksCore/CityGenerator.swift Tests/TanksCoreTests/MultiBaseTests.swift
git commit -m "feat(core): two-base cities for versus, base lookup and building HP mirroring

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Match settings, kill feed and match state

**Files:**
- Create: `Sources/TanksCore/Match.swift`
- Test: `Tests/TanksCoreTests/MatchTests.swift` (new)

**Interfaces:**
- Consumes: `InfantryKind` (existing).
- Produces:
  - `public enum PlayerSlot: Int, CaseIterable, Sendable { case host = 0, guest = 1; var opponent: PlayerSlot; var baseIndex: Int }`
  - `public enum AIIntensity: Int, CaseIterable, Sendable { case light, normal, heavy; var difficultyLevel: Int; var name: String }`
  - `public struct MatchSettings: Equatable, Sendable { lives: Int; aiIntensity: AIIntensity; seed: UInt64; static let livesRange = 1...9; init(lives:aiIntensity:seed:); mutating changeLives(by:); mutating changeIntensity(by:) }`
  - `public enum Combatant: Equatable, Sendable { case player(PlayerSlot), enemyTank, infantry(InfantryKind) }`
  - `public enum KillFeed { static func name(of:viewer:) -> String; static func line(killer: Combatant?, victim: PlayerSlot, viewer: PlayerSlot) -> String }`
  - `public struct MatchState: Sendable` with `respawnDelay = 3.0`, `invulnerableTime = 3.0`, `settings`, `lives: [PlayerSlot: Int]`, `kills: [PlayerSlot: Int]`, `winner: PlayerSlot?`, `isOver`, `isRespawning(_:)`, `respawnRemaining(_:) -> Double?`, `isInvulnerable(_:)`, `playerDied(_:killer:)`, `tick(dt:) -> [PlayerSlot]`, `playerFired(_:)`, `playerLeft(_:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TanksCoreTests/MatchTests.swift`:

```swift
import Testing
@testable import TanksCore

@Test func slotsKnowTheirOpponentAndBase() {
    #expect(PlayerSlot.host.opponent == .guest)
    #expect(PlayerSlot.guest.opponent == .host)
    #expect(PlayerSlot.host.baseIndex == 0)
    #expect(PlayerSlot.guest.baseIndex == 1)
}

@Test func intensityMapsToCampaignDifficulty() {
    #expect(AIIntensity.allCases.map(\.difficultyLevel) == [1, 3, 6])
    #expect(AIIntensity.allCases.map(\.name) == ["LIGHT", "NORMAL", "HEAVY"])
}

@Test func settingsClampLivesAndWrapIntensity() {
    var s = MatchSettings(lives: 42, seed: 1)
    #expect(s.lives == 9)
    #expect(MatchSettings(lives: 0).lives == 1)
    #expect(MatchSettings().lives == 3)
    #expect(MatchSettings().aiIntensity == .normal)
    s.changeLives(by: 1)
    #expect(s.lives == 9)
    s.changeLives(by: -3)
    #expect(s.lives == 6)
    s.changeIntensity(by: 1)
    #expect(s.aiIntensity == .heavy)
    s.changeIntensity(by: 1)
    #expect(s.aiIntensity == .light)
    s.changeIntensity(by: -1)
    #expect(s.aiIntensity == .heavy)
}

@Test func killFeedNamesAreFromTheViewersPointOfView() {
    #expect(KillFeed.line(killer: .player(.host), victim: .guest, viewer: .host) == "You destroyed Opponent")
    #expect(KillFeed.line(killer: .player(.host), victim: .guest, viewer: .guest) == "Opponent destroyed You")
    #expect(KillFeed.line(killer: .infantry(.bazooka), victim: .host, viewer: .host) == "Bazooka destroyed You")
    #expect(KillFeed.line(killer: .enemyTank, victim: .host, viewer: .guest) == "Rust Brigade tank destroyed Opponent")
    #expect(KillFeed.line(killer: nil, victim: .guest, viewer: .guest) == "You abandoned your tank")
}

@Test func deathCostsALifeAndStartsARespawn() {
    var m = MatchState(settings: MatchSettings(lives: 3))
    m.playerDied(.host, killer: .enemyTank)
    #expect(m.lives[.host] == 2)
    #expect(m.kills[.guest] == 0)            // AI kills credit nobody
    #expect(m.isRespawning(.host))
    #expect(m.respawnRemaining(.host) == MatchState.respawnDelay)
    m.playerDied(.host, killer: .enemyTank)  // already dead: ignored
    #expect(m.lives[.host] == 2)
}

@Test func opponentKillsAreCredited() {
    var m = MatchState(settings: MatchSettings(lives: 3))
    m.playerDied(.guest, killer: .player(.host))
    #expect(m.kills[.host] == 1)
}

@Test func respawnHappensAfterTheDelayWithInvulnerability() {
    var m = MatchState(settings: MatchSettings(lives: 3))
    m.playerDied(.guest, killer: nil)
    #expect(m.tick(dt: 2.9).isEmpty)
    #expect(m.tick(dt: 0.2) == [.guest])
    #expect(!m.isRespawning(.guest))
    #expect(m.isInvulnerable(.guest))
    #expect(m.tick(dt: 2.9).isEmpty)
    #expect(m.isInvulnerable(.guest))
    _ = m.tick(dt: 0.2)
    #expect(!m.isInvulnerable(.guest))
}

@Test func firingEndsInvulnerability() {
    var m = MatchState(settings: MatchSettings(lives: 3))
    m.playerDied(.host, killer: nil)
    _ = m.tick(dt: 3.1)
    #expect(m.isInvulnerable(.host))
    m.playerFired(.host)
    #expect(!m.isInvulnerable(.host))
}

@Test func losingTheLastLifeEndsTheMatch() {
    var m = MatchState(settings: MatchSettings(lives: 1))
    m.playerDied(.host, killer: .player(.guest))
    #expect(m.isOver)
    #expect(m.winner == .guest)
    #expect(m.lives[.host] == 0)
    #expect(!m.isRespawning(.host))
    #expect(m.tick(dt: 10).isEmpty)
}

@Test func simultaneousLastLifeDeathsKeepTheFirstWinner() {
    var m = MatchState(settings: MatchSettings(lives: 1))
    m.playerDied(.host, killer: .infantry(.mortar))
    m.playerDied(.guest, killer: .infantry(.mortar))
    #expect(m.winner == .guest)
    #expect(m.lives[.guest] == 1)
    #expect(m.lives[.host] == 0)
}

@Test func leavingHandsTheWinToTheOpponent() {
    var m = MatchState(settings: MatchSettings(lives: 3))
    m.playerLeft(.guest)
    #expect(m.winner == .host)
    m.playerLeft(.host)
    #expect(m.winner == .host)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MatchTests`
Expected: compile errors: `cannot find 'PlayerSlot' in scope` and similar.

- [ ] **Step 3: Implement `Match.swift`**

Create `Sources/TanksCore/Match.swift`:

```swift
import Foundation

/// The two sides of a versus match. The host runs the simulation; the guest joined with a room code.
public enum PlayerSlot: Int, CaseIterable, Sendable {
    case host = 0
    case guest = 1

    public var opponent: PlayerSlot { self == .host ? .guest : .host }
    /// Index into `Level.bases`.
    public var baseIndex: Int { rawValue }
}

/// How much AI joins a versus match, borrowed from a campaign level's tuning.
public enum AIIntensity: Int, CaseIterable, Sendable {
    case light = 0
    case normal = 1
    case heavy = 2

    public var difficultyLevel: Int {
        switch self {
        case .light: return 1
        case .normal: return 3
        case .heavy: return 6
        }
    }

    public var name: String {
        switch self {
        case .light: return "LIGHT"
        case .normal: return "NORMAL"
        case .heavy: return "HEAVY"
        }
    }
}

/// What the host picks in the lobby, plus the seed both Macs build the city from.
public struct MatchSettings: Equatable, Sendable {
    public static let livesRange = 1...9

    public private(set) var lives: Int
    public var aiIntensity: AIIntensity
    public var seed: UInt64

    public init(lives: Int = 3, aiIntensity: AIIntensity = .normal, seed: UInt64 = 0) {
        self.lives = Self.clamp(lives)
        self.aiIntensity = aiIntensity
        self.seed = seed
    }

    public mutating func changeLives(by delta: Int) {
        lives = Self.clamp(lives + delta)
    }

    /// Steps through the intensities, wrapping around.
    public mutating func changeIntensity(by delta: Int) {
        let count = AIIntensity.allCases.count
        aiIntensity = AIIntensity(rawValue: ((aiIntensity.rawValue + delta) % count + count) % count)!
    }

    private static func clamp(_ lives: Int) -> Int {
        min(max(lives, livesRange.lowerBound), livesRange.upperBound)
    }
}

/// Who fired a shot: a human player or one of the AI hazards.
public enum Combatant: Equatable, Sendable {
    case player(PlayerSlot)
    case enemyTank
    case infantry(InfantryKind)
}

/// Kill-feed lines, worded for the player reading them.
public enum KillFeed {
    public static func name(of combatant: Combatant, viewer: PlayerSlot) -> String {
        switch combatant {
        case .player(let slot): return slot == viewer ? "You" : "Opponent"
        case .enemyTank: return "Rust Brigade tank"
        case .infantry(.rifleman): return "Rifleman"
        case .infantry(.machineGunner): return "Machine gunner"
        case .infantry(.bazooka): return "Bazooka"
        case .infantry(.mortar): return "Mortar"
        }
    }

    /// `killer` is nil when the victim abandoned their tank.
    public static func line(killer: Combatant?, victim: PlayerSlot, viewer: PlayerSlot) -> String {
        guard let killer else {
            return victim == viewer ? "You abandoned your tank" : "Opponent abandoned their tank"
        }
        return "\(name(of: killer, viewer: viewer)) destroyed \(name(of: .player(victim), viewer: viewer))"
    }
}

/// Lives, kills, respawn countdowns, spawn protection and the winner of a versus match.
public struct MatchState: Sendable {
    public static let respawnDelay = 3.0
    public static let invulnerableTime = 3.0

    public let settings: MatchSettings
    public private(set) var lives: [PlayerSlot: Int]
    public private(set) var kills: [PlayerSlot: Int] = [.host: 0, .guest: 0]
    public private(set) var winner: PlayerSlot?
    private var respawnTimers: [PlayerSlot: Double] = [:]
    private var invulnerableTimers: [PlayerSlot: Double] = [:]

    public init(settings: MatchSettings) {
        self.settings = settings
        lives = [.host: settings.lives, .guest: settings.lives]
    }

    public var isOver: Bool { winner != nil }
    public func isRespawning(_ slot: PlayerSlot) -> Bool { respawnTimers[slot] != nil }
    public func respawnRemaining(_ slot: PlayerSlot) -> Double? { respawnTimers[slot] }
    public func isInvulnerable(_ slot: PlayerSlot) -> Bool { invulnerableTimers[slot] != nil }

    /// A tank was destroyed. Any death costs a life; only the opponent's kills are credited.
    public mutating func playerDied(_ slot: PlayerSlot, killer: Combatant?) {
        guard !isOver, !isRespawning(slot) else { return }
        lives[slot, default: 0] -= 1
        invulnerableTimers[slot] = nil
        if killer == .player(slot.opponent) { kills[slot.opponent, default: 0] += 1 }
        if lives[slot, default: 0] <= 0 {
            winner = slot.opponent
        } else {
            respawnTimers[slot] = Self.respawnDelay
        }
    }

    /// Advances the countdowns. Returns the slots whose respawn delay ran out (they are now invulnerable).
    public mutating func tick(dt: Double) -> [PlayerSlot] {
        guard !isOver else { return [] }
        for slot in PlayerSlot.allCases {
            guard let remaining = invulnerableTimers[slot] else { continue }
            invulnerableTimers[slot] = remaining - dt > 0 ? remaining - dt : nil
        }
        var respawned: [PlayerSlot] = []
        for slot in PlayerSlot.allCases {
            guard let remaining = respawnTimers[slot] else { continue }
            if remaining - dt > 0 {
                respawnTimers[slot] = remaining - dt
            } else {
                respawnTimers[slot] = nil
                invulnerableTimers[slot] = Self.invulnerableTime
                respawned.append(slot)
            }
        }
        return respawned
    }

    /// Shooting gives up spawn protection.
    public mutating func playerFired(_ slot: PlayerSlot) {
        invulnerableTimers[slot] = nil
    }

    /// The player quit or their connection timed out: the opponent wins.
    public mutating func playerLeft(_ slot: PlayerSlot) {
        guard !isOver else { return }
        winner = slot.opponent
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter MatchTests`
Expected: all 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksCore/Match.swift Tests/TanksCoreTests/MatchTests.swift
git commit -m "feat(core): versus match settings, lives, respawn timers and kill feed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Respawn locations and respawn queues

**Files:**
- Create: `Sources/TanksCore/Respawn.swift`
- Test: `Tests/TanksCoreTests/RespawnTests.swift` (new)

**Interfaces:**
- Consumes: `TileMap.reachable(from:)`, `GridPoint.distance(to:)`, `SeededRandom`.
- Produces:
  - `RespawnPicker.playerSpawn(in: TileMap, reachableFrom: GridPoint, opponent: GridPoint?, aiTanks: [GridPoint], using: inout some RandomNumberGenerator) -> GridPoint`
  - `RespawnPicker.aiTankSpawn(in: TileMap, reachableFrom: GridPoint, players: [GridPoint], using: inout some RandomNumberGenerator) -> GridPoint`
  - constants `RespawnPicker.minOpponentDistance = 15`, `minAITankDistance = 8`, `aiMinPlayerDistance = 15`
  - `public struct RespawnQueue<Item: Sendable>: Sendable { init(); var count: Int; mutating schedule(_:after:); mutating tick(dt:) -> [Item] }`
  - `public enum VersusTimings { static let aiTankRespawn = 20.0, infantryRespawn = 30.0, pickupRespawn = 45.0 }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TanksCoreTests/RespawnTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RespawnTests`
Expected: compile errors: `cannot find 'RespawnPicker' in scope`.

- [ ] **Step 3: Implement `Respawn.swift`**

Create `Sources/TanksCore/Respawn.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter TanksCoreTests`
Expected: all TanksCore tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksCore/Respawn.swift Tests/TanksCoreTests/RespawnTests.swift
git commit -m "feat(core): respawn location picking and respawn queues

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
## Phase B: The game holds more than one player

These tasks change only the app target. `swift test` keeps guarding `TanksCore`. The app has no unit tests, so each task ends with a scripted build plus a short manual play check. If you can't play the game yourself (for example, you are an agent), run the launch check and report the manual checks as **not done** so your human partner can do them.

**Launch check** (used by several tasks): start the game in the background on a campaign level, let it run for 8 seconds, and confirm it neither crashed nor logged errors:

```bash
swift build 2>&1 | tail -3
( TANKS_START_LEVEL=1 .build/debug/TanksOfDoom & PID=$!; sleep 8; kill $PID 2>/dev/null && echo "still running after 8 s: OK" )
```

Expected: `Build complete!` and `still running after 8 s: OK`.

### Task 4: Players, shooter-aware combat and per-player aiming (campaign unchanged)

**Files:**
- Create: `Sources/TanksOfDoom/Player.swift`
- Modify (full replacements below): `Sources/TanksOfDoom/GameScene.swift`, `GameScene+Player.swift`, `GameScene+Combat.swift`, `GameScene+Aiming.swift`, `GameScene+Enemies.swift`, `GameScene+Infantry.swift`, `GameScene+HUD.swift`, `GameScene+Flow.swift`, `GameScene+Input.swift`
- Modify (edits below): `Sources/TanksOfDoom/Tanks.swift`, `Projectile.swift`, `EnemyTank.swift`, `InfantryNode.swift`, `Textures.swift`

**Interfaces:**
- Consumes: `PlayerSlot`, `Combatant` (Task 2); `Level.bases`, `Level.baseIndex(at:)` (Task 1).
- Produces (later tasks rely on these exact names):
  - `final class Player { let slot: PlayerSlot; let tank: PlayerTank; var input: InputState; var turretAim: TurretAim; var lockedTargetID: Int?; var inBase: Bool }`, `PlayerSlot.color: NSColor`
  - `PlayerTank(slot:)`, which is now `Hostile`: `netID` (host 1, guest 2), `isInvulnerable`, `canBeHit`, `respawn(at:heading:)`
  - `protocol Hostile: SKNode { var netID: UInt32; var hitRadius: CGFloat; var targetKind: TargetKind; var canBeHit: Bool; func applyDamage(_:from:in:) }`
  - `Projectile(weapon:angle:shooter:ownerBuilding:)`, `Projectile.shooter: Combatant`, `Projectile.netID`, `MortarShell.netID`
  - `EnemyTank.spawn`, `EnemyTank.netID`; `InfantryNode.netID`, `InfantryNode.kind`
  - `GameScene.players: [Player]`, `GameScene.localPlayer: Player`, `makeNetID() -> UInt32`, `placeAtBase(_:)`
  - `drive(_ tank: PlayerTank, with: InputState, dt: Double, blockers: [TankNode]) -> (distance: CGFloat, moving: Bool)`
  - `updatePlayers(dt:)`, `updatePlayer(_:dt:)`, `updateWeapons(for:dt:)`, `collectPickups(for:)`, `leaveTracks(_:moved:)`
  - `fire(_:from:angle:shooter:ownerBuilding:)`, `targets(of: Combatant) -> [Hostile]`, `applySplash(_:at:from:excluding:)`, `damagePlayer(_ tank: PlayerTank, _ amount: Int, from: Combatant?)`
  - `hostiles(for: Player) -> [Hostile]`, `lockedTarget(of: Player) -> Hostile?`, `cycleTarget(for:)`, `updateTurret(for:dt:)`, `updateTargetMarker()`
  - `allTanks: [TankNode]`, `addEnemy(_:at:) -> EnemyTank`, `aiTarget(from: CGPoint, sightRange: Double) -> PlayerTank?`, `addWreck(_ texture: SKTexture, at: CGPoint, heading: CGFloat)`
  - `addSoldier(_:initialDelay:)`, `abandonTank(_ player: Player)`
  - `Textures.guestHull`, `Textures.guestTurret`, `Textures.hull(for: PlayerSlot)`, `Textures.turret(for: PlayerSlot)`

- [ ] **Step 1: Add `Player` and the guest colour scheme**

Create `Sources/TanksOfDoom/Player.swift`:

```swift
import AppKit
import TanksCore

/// A human-driven tank and everything its driver controls: held keys, turret aim mode and target lock.
final class Player {
    let slot: PlayerSlot
    let tank: PlayerTank
    var input = InputState()
    var turretAim = TurretAim()
    var lockedTargetID: Int?
    var inBase = false

    init(slot: PlayerSlot) {
        self.slot = slot
        tank = PlayerTank(slot: slot)
    }
}

extension PlayerSlot {
    /// Matches the tank paint: olive for the host, steel blue for the guest.
    var color: NSColor {
        switch self {
        case .host: return NSColor(calibratedRed: 0.6, green: 0.75, blue: 0.3, alpha: 1)
        case .guest: return NSColor(calibratedRed: 0.45, green: 0.65, blue: 0.95, alpha: 1)
        }
    }
}
```

In `Sources/TanksOfDoom/Textures.swift`, below `enemyTurret`, add:

```swift
    static let guestHull = tankHull(body: color(0.3, 0.42, 0.55), dark: color(0.15, 0.21, 0.3))
    static let guestTurret = tankTurret(body: color(0.36, 0.5, 0.64), dark: color(0.15, 0.21, 0.3))

    static func hull(for slot: PlayerSlot) -> SKTexture { slot == .host ? playerHull : guestHull }
    static func turret(for slot: PlayerSlot) -> SKTexture { slot == .host ? playerTurret : guestTurret }
```

- [ ] **Step 2: Make every tank and soldier a networkable, shooter-aware target**

In `Sources/TanksOfDoom/Projectile.swift`, replace the `Hostile` protocol and the `Projectile` class with:

```swift
/// Something a weapon can hit: enemy tanks, exposed infantry and, in versus, the other player's tank.
protocol Hostile: SKNode {
    /// Stable id shared with the guest's mirror of the world.
    var netID: UInt32 { get }
    var hitRadius: CGFloat { get }
    var targetKind: TargetKind { get }
    var canBeHit: Bool { get }
    func applyDamage(_ amount: Int, from shooter: Combatant, in scene: GameScene)
}

/// A straight-flying shot.
final class Projectile: SKSpriteNode {
    let weapon: WeaponKind
    let shooter: Combatant
    /// Infantry shots start inside their own building, so that building never stops them.
    let ownerBuilding: Int?
    let velocity: CGVector
    var remainingRange: CGFloat
    var smokeTimer: Double = 0
    var netID: UInt32 = 0

    init(weapon: WeaponKind, angle: CGFloat, shooter: Combatant, ownerBuilding: Int?) {
        let spec = Combat.spec(weapon)
        self.weapon = weapon
        self.shooter = shooter
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
```

In `MortarShell`, add a property below `let marker: SKShapeNode`:

```swift
    var netID: UInt32 = 0
```

In `Sources/TanksOfDoom/Tanks.swift`, replace `final class PlayerTank` with:

```swift
final class PlayerTank: TankNode, Hostile {
    static let forwardSpeed: CGFloat = 170
    static let reverseSpeed: CGFloat = 100
    static let turnRate: CGFloat = 2.2
    static let turretTurnRate: CGFloat = 4.0

    let slot: PlayerSlot
    var stats = TankStats()
    var mainCooldown: Double = 0
    var machineGunCooldown: Double = 0
    /// Spawn protection in versus: takes no damage and the AI looks elsewhere.
    var isInvulnerable = false
    var isDestroyed: Bool { stats.isDestroyed }

    var netID: UInt32 { UInt32(slot.rawValue + 1) }
    var hitRadius: CGFloat { TankNode.radius }
    var targetKind: TargetKind { .tank }
    /// Hidden tanks are waiting to respawn in versus.
    var canBeHit: Bool { !isDestroyed && !isInvulnerable && !isHidden }

    init(slot: PlayerSlot) {
        self.slot = slot
        super.init(hullTexture: Textures.hull(for: slot), turretTexture: Textures.turret(for: slot))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyDamage(_ amount: Int, from shooter: Combatant, in scene: GameScene) {
        scene.damagePlayer(self, amount, from: shooter)
    }

    func showWreck() {
        for part in [hull, turret] {
            part.color = .black
            part.colorBlendFactor = 0.75
        }
    }

    /// Back in factory condition at `point` (versus respawn).
    func respawn(at point: CGPoint, heading: CGFloat) {
        stats = TankStats()
        mainCooldown = 0
        machineGunCooldown = 0
        position = point
        self.heading = heading
        turretAngle = heading
        for part in [hull, turret] { part.colorBlendFactor = 0 }
        isHidden = false
    }
}
```

In `Sources/TanksOfDoom/InfantryNode.swift`, add below `var post: GridPoint?`:

```swift
    var netID: UInt32 = 0
    var kind: InfantryKind { brain.kind }
```

and change the damage method's signature to:

```swift
    func applyDamage(_ amount: Int, from shooter: Combatant, in scene: GameScene) {
```

- [ ] **Step 3: Point enemy tanks at the nearest player**

In `Sources/TanksOfDoom/EnemyTank.swift`:

Add below `let patrol: [GridPoint]`:

```swift
    let spawn: EnemyTankSpawn
    var netID: UInt32 = 0
```

In `init(spawn:difficulty:)`, add `self.spawn = spawn` before `super.init(...)`.

Change the damage method's signature to `func applyDamage(_ amount: Int, from shooter: Combatant, in scene: GameScene) {`. The body is unchanged.

Replace `update(dt:scene:)` and `engage(_:scene:dt:)` with:

```swift
    func update(dt: Double, scene: GameScene) {
        let map = scene.level.map
        let target = scene.aiTarget(from: position, sightRange: EnemyTankBrain.sightRange)
        let toTarget = target.map { position.distance(to: $0.position) } ?? .greatestFiniteMagnitude
        let sees = target.map { Double(toTarget) <= EnemyTankBrain.sightRange && scene.hasLineOfSight(from: position, to: $0.position) } ?? false
        if sees, let target { lastKnownPlayer = target.position }
        let reachedSearchPoint = lastKnownPlayer.map { position.distance(to: $0) < tileSize } ?? true

        let previous = brain.state
        let perception = EnemyPerception(canSeePlayer: sees, distanceToPlayer: Double(toTarget),
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
            guard let target else { break }
            if toTarget > CGFloat(Combat.spec(.enemyShell).range) * 0.7 {
                if repathTimer <= 0 {
                    setPath(to: target.position, map: map)
                    repathTimer = 1.5
                }
            } else {
                path = []
            }
            engage(target, scene: scene, dt: dt)
        case .search:
            if path.isEmpty && repathTimer <= 0, let lastSeen = lastKnownPlayer {
                setPath(to: lastSeen, map: map)
                repathTimer = 2
            }
            aimTurret(at: heading, dt: dt)
        case .retreat:
            if path.isEmpty && repathTimer <= 0 {
                let threat = target?.position ?? position
                let refuge = patrol.max { map.center($0).distance(to: threat) < map.center($1).distance(to: threat) } ?? patrol[0]
                setPath(to: map.center(refuge), map: map)
                repathTimer = 2
            }
            if sees, let target { engage(target, scene: scene, dt: dt) } else { aimTurret(at: heading, dt: dt) }
        }
        followPath(dt: dt, scene: scene)
    }

    private func engage(_ target: PlayerTank, scene: GameScene, dt: Double) {
        let angle = position.angle(to: target.position)
        aimTurret(at: angle, dt: dt)
        let aligned = abs(normalizeAngle(turretAngle - angle)) < 0.08
        let ready = brain.timeInState >= reactionTime || brain.state == .retreat
        guard aligned, ready, fireCooldown <= 0, scene.hasLineOfSight(from: position, to: target.position) else { return }
        scene.fire(.enemyShell, from: muzzlePosition, angle: turretAngle + .random(in: -0.06...0.06), shooter: .enemyTank)
        fireCooldown = Combat.spec(.enemyShell).reload
    }
```

- [ ] **Step 4: Replace `GameScene.swift`**

Replace `Sources/TanksOfDoom/GameScene.swift` with:

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
    var renderer: WorldRenderer!
    var effects: Effects!
    var hud: HUD!
    /// Every human-driven tank. The campaign has one.
    let players: [Player]
    /// The player at this keyboard: the camera, HUD and sound follow them.
    let localPlayer: Player
    var pickups: [PickupNode] = []
    var projectiles: [Projectile] = []
    var mortars: [MortarShell] = []
    var enemies: [EnemyTank] = []
    var infantry: [InfantryNode] = []
    var buildingWindows: [Int: [GridPoint]] = [:]
    /// Ids 1–16 are reserved for player tanks; every other networked thing counts up from here.
    private var lastNetID: UInt32 = 16

    var lastUpdate: TimeInterval = 0
    var cameraBase = CGPoint.zero
    var shakeTime: Double = 0
    var shakeMagnitude: CGFloat = 0
    let targetMarker = TargetMarker()
    var isGamePaused = false
    var endTimer: Double?
    var victory = false
    var levelOver = false
    private var isSetUp = false
    private var resignObserver: NSObjectProtocol?

    init(size: CGSize, levelNumber: Int, runStats: RunStats) {
        self.levelNumber = levelNumber
        self.runStats = runStats
        self.level = CityGenerator.generate(seed: .random(in: 0...UInt64.max), level: levelNumber)
        let player = Player(slot: .host)
        players = [player]
        localPlayer = player
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
            self?.localPlayer.input = InputState()
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

        for player in players {
            placeAtBase(player)
            worldNode.addChild(player.tank)
        }
        spawnEnemies()
        spawnInfantry()

        addChild(cameraNode)
        camera = cameraNode
        cameraBase = localPlayer.tank.position
        cameraNode.position = cameraBase
        worldNode.addChild(targetMarker)
        setUpHUD()
    }

    /// Starts a player at their own base, facing the middle of the city.
    func placeAtBase(_ player: Player) {
        let tank = player.tank
        tank.position = level.map.center(level.bases[player.slot.baseIndex].center)
        let middle = CGPoint(x: CGFloat(level.map.width) * tileSize / 2, y: CGFloat(level.map.height) * tileSize / 2)
        tank.heading = tank.position.angle(to: middle)
        tank.turretAngle = tank.heading
    }

    /// A fresh id for a networked thing (AI tank, soldier, projectile, mortar).
    func makeNetID() -> UInt32 {
        lastNetID += 1
        return lastNetID
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(currentTime - lastUpdate, 1.0 / 30)
        lastUpdate = currentTime
        guard !isGamePaused, !levelOver else { return }
        updatePlayers(dt: dt)
        updateEnemies(dt: dt)
        updateInfantry(dt: dt)
        updateProjectiles(dt: dt)
        updateMortars(dt: dt)
        updateTargetMarker()
        updateCamera(dt: dt)
        updateHUD()
        checkLevelEnd(dt: dt)
    }

    func shake(_ magnitude: CGFloat, duration: Double) {
        guard magnitude >= shakeMagnitude || shakeTime <= 0 else { return }
        shakeMagnitude = magnitude
        shakeTime = duration
    }

    func updateCamera(dt: Double) {
        let follow = CGFloat(min(1, 6 * dt))
        var p = cameraBase + (localPlayer.tank.position - cameraBase) * follow
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
    }

    /// Keeps the view inside the map; centres the map when the view is larger than it.
    private func clampCamera(_ value: CGFloat, half: CGFloat, extent: CGFloat) -> CGFloat {
        if extent <= half * 2 { return extent / 2 }
        return min(max(value, half), extent - half)
    }

    func playSound(_ sound: Audio.Sound, at point: CGPoint, volume: Float = 1) {
        let distance = Float(point.distance(to: localPlayer.tank.position))
        Audio.shared.play(sound, volume: volume * max(0, 1 - distance / 1400))
    }
}
```

The campaign base sits at tile (6, 6), so "facing the middle" works out to exactly π/4, the old hard-coded start heading.

- [ ] **Step 5: Replace `GameScene+Player.swift`**

```swift
import SpriteKit
import TanksCore

extension GameScene {
    func updatePlayers(dt: Double) {
        for player in players {
            updatePlayer(player, dt: dt)
            updateWeapons(for: player, dt: dt)
        }
    }

    func updatePlayer(_ player: Player, dt: Double) {
        let tank = player.tank
        guard !tank.isDestroyed, !tank.isHidden else { return }
        let drove = drive(tank, with: player.input, dt: dt, blockers: allTanks)
        if drove.distance > 0 { leaveTracks(tank, moved: drove.distance) }
        let hadFuel = tank.stats.fuel > 0
        tank.stats.burnFuel(seconds: dt, moving: drove.moving)
        if hadFuel && tank.stats.fuel <= 0 {
            effects.floatingText("OUT OF FUEL!", at: tank.position + CGPoint(x: 0, y: 44), color: .systemOrange)
        }

        updateTurret(for: player, dt: dt)

        player.inBase = level.baseIndex(at: level.map.grid(tank.position)) == player.slot.baseIndex
        if player.inBase { tank.stats.applyBase(seconds: dt) }
        collectPickups(for: player)
    }

    /// Turns and drives `tank` as `input` asks. Shared by the simulation and the guest's own-tank prediction,
    /// so it touches nothing but the tank.
    func drive(_ tank: PlayerTank, with input: InputState, dt: Double, blockers: [TankNode]) -> (distance: CGFloat, moving: Bool) {
        guard tank.stats.canMove else { return (0, false) }
        var turn: CGFloat = 0
        if input.left { turn += 1 }
        if input.right { turn -= 1 }
        var throttle: CGFloat = 0
        if input.forward { throttle += 1 }
        if input.backward { throttle -= 1 }

        var moving = false
        if turn != 0 {
            tank.heading += turn * PlayerTank.turnRate * CGFloat(dt)
            moving = true
        }
        var distance: CGFloat = 0
        if throttle != 0 {
            let speed = (throttle > 0 ? PlayerTank.forwardSpeed : PlayerTank.reverseSpeed)
                * CGFloat(level.map.speedMultiplier(at: tank.position.world))
            distance = tank.move(by: CGPoint(angle: tank.heading, length: throttle * speed * CGFloat(dt)),
                                 in: level.map, blockers: blockers)
            if distance > 0 { moving = true }
        }
        return (distance, moving)
    }

    func leaveTracks(_ tank: TankNode, moved: CGFloat) {
        tank.distanceSinceTrack += moved
        guard tank.distanceSinceTrack >= 12 else { return }
        tank.distanceSinceTrack = 0
        effects.trackMark(at: tank.position, angle: tank.heading)
    }

    func collectPickups(for player: Player) {
        let tank = player.tank
        for pickup in pickups where pickup.position.distance(to: tank.position) < 40 {
            tank.stats.collect(pickup.kind)
            effects.floatingText(pickup.kind == .gas ? "+GAS" : "+AMMO", at: pickup.position, color: .systemGreen)
            if player === localPlayer { Audio.shared.play(.pickup) }
            pickup.removeFromParent()
            pickups.removeAll { $0 === pickup }
        }
    }
}
```

- [ ] **Step 6: Replace `GameScene+Combat.swift`**

```swift
import AppKit
import SpriteKit
import TanksCore

extension GameScene {
    enum Impact {
        case target(Hostile)
        case building(Int)
        case solid
    }

    func fire(_ weapon: WeaponKind, from origin: CGPoint, angle: CGFloat, shooter: Combatant, ownerBuilding: Int? = nil) {
        let projectile = Projectile(weapon: weapon, angle: angle, shooter: shooter, ownerBuilding: ownerBuilding)
        projectile.netID = makeNetID()
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
        shell.netID = makeNetID()
        worldNode.addChild(shell.marker)
        worldNode.addChild(shell)
        mortars.append(shell)
        playSound(.cannon, at: origin, volume: 0.4)
    }

    func updateWeapons(for player: Player, dt: Double) {
        let tank = player.tank
        guard !tank.isDestroyed, !tank.isHidden else { return }
        let isLocal = player === localPlayer
        tank.mainCooldown -= dt
        tank.machineGunCooldown -= dt

        if player.input.firePrimary && tank.mainCooldown <= 0 {
            if tank.stats.consumeShell() {
                fire(.mainGun, from: tank.muzzlePosition, angle: tank.turretAngle, shooter: .player(player.slot))
                tank.mainCooldown = Combat.spec(.mainGun).reload
                if isLocal { shake(4, duration: 0.15) }
            } else {
                tank.mainCooldown = 0.5
                if isLocal {
                    Audio.shared.play(.empty)
                    effects.floatingText("NO SHELLS", at: tank.position + CGPoint(x: 0, y: 40), color: .systemYellow)
                }
            }
        }

        if player.input.fireSecondary && tank.machineGunCooldown <= 0 {
            if tank.stats.consumeRound() {
                let side = CGPoint(angle: tank.turretAngle - .pi / 2, length: 7)
                let origin = tank.position + CGPoint(angle: tank.turretAngle, length: 30) + side
                fire(.machineGun, from: origin, angle: tank.turretAngle + .random(in: -0.04...0.04), shooter: .player(player.slot))
                tank.machineGunCooldown = Combat.spec(.machineGun).reload
            } else {
                tank.machineGunCooldown = 0.5
                if isLocal {
                    Audio.shared.play(.empty)
                    effects.floatingText("NO MG AMMO", at: tank.position + CGPoint(x: 0, y: 40), color: .systemYellow)
                }
            }
        }
    }

    /// What a shot can hurt: players hit the AI and each other; the AI hits players only.
    func targets(of shooter: Combatant) -> [Hostile] {
        switch shooter {
        case .player(let slot):
            return (enemies as [Hostile]) + (infantry as [Hostile]) + players.filter { $0.slot != slot }.map(\.tank)
        case .enemyTank, .infantry:
            return players.map(\.tank)
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
        if let target = targets(of: projectile.shooter).first(where: { $0.canBeHit && $0.position.distance(to: point) < $0.hitRadius }) {
            return .target(target)
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
        case .target(let target):
            direct = target
            let damage = Combat.damage(projectile.weapon, to: target.targetKind, distance: 0)
            if damage > 0 { target.applyDamage(damage, from: projectile.shooter, in: self) }
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
        applySplash(projectile.weapon, at: point, from: projectile.shooter, excluding: direct)
        let heavy = projectile.weapon == .mainGun || projectile.weapon == .enemyShell
        effects.explosion(at: point, scale: heavy ? 1.0 : 0.7)
        playSound(.explosion, at: point, volume: 0.7)
        removeProjectile(projectile)
    }

    /// Splash damage around an impact; `excluding` already took the direct hit.
    func applySplash(_ weapon: WeaponKind, at point: CGPoint, from shooter: Combatant, excluding: AnyObject?) {
        for target in targets(of: shooter) where target.canBeHit && target !== excluding {
            let damage = Combat.damage(weapon, to: target.targetKind, distance: Double(target.position.distance(to: point)))
            if damage > 0 { target.applyDamage(damage, from: shooter, in: self) }
        }
    }

    private func removeProjectile(_ projectile: Projectile) {
        projectile.removeFromParent()
        projectiles.removeAll { $0 === projectile }
    }

    func updateMortars(dt: Double) {
        for shell in mortars {
            guard shell.advance(dt: dt) else { continue }
            applySplash(.mortar, at: shell.target, from: .infantry(.mortar), excluding: nil)
            effects.explosion(at: shell.target, scale: 0.9)
            playSound(.explosion, at: shell.target, volume: 0.8)
            shell.marker.removeFromParent()
            shell.removeFromParent()
            mortars.removeAll { $0 === shell }
        }
    }

    /// `shooter` is nil when the player abandons their own tank.
    func damagePlayer(_ tank: PlayerTank, _ amount: Int, from shooter: Combatant?) {
        guard amount > 0, !tank.isDestroyed, !tank.isInvulnerable else { return }
        tank.stats.takeDamage(amount)
        effects.floatingText("-\(amount)", at: tank.position + CGPoint(x: 0, y: 36), color: .systemRed)
        let isLocal = tank === localPlayer.tank
        if isLocal {
            Audio.shared.play(.hit, volume: 0.8)
            shake(min(14, 3 + CGFloat(amount) * 0.5), duration: 0.25)
        }
        guard tank.isDestroyed else { return }
        effects.explosion(at: tank.position, scale: 2.2)
        playSound(.bigExplosion, at: tank.position)
        tank.showWreck()
        if isLocal { shake(20, duration: 0.6) }
    }

    func damageBuilding(_ id: Int, amount: Int) {
        let result = level.damageBuilding(id, by: amount)
        guard result != .none else { return }
        renderer.update(level.buildings[id])
        if result == .destroyed { buildingDestroyed(id) }
    }

    func buildingDestroyed(_ id: Int) {
        killOccupants(of: id)
        let center = level.buildings[id].worldCenter
        effects.explosion(at: center, scale: 2.0)
        effects.dustPuff(at: center)
        playSound(.bigExplosion, at: center)
        shake(10, duration: 0.4)
        hud.minimap.refresh(map: level.map)
    }
}
```

- [ ] **Step 7: Replace `GameScene+Aiming.swift`**

Keep the `TargetMarker` class at the top of the file exactly as it is. Replace the `extension GameScene { ... }` below it with:

```swift
extension GameScene {
    static let autoAimRange: CGFloat = 750
    static let manualTurretRate: CGFloat = 2.5

    /// Everything `player` may shoot at: the AI and any other player's tank.
    func hostiles(for player: Player) -> [Hostile] {
        targets(of: .player(player.slot))
    }

    /// Hittable hostiles within main-gun range and in clear line of sight of the player.
    private func targetCandidates(for player: Player) -> [TargetCandidate] {
        let origin = player.tank.position
        return hostiles(for: player).compactMap { hostile in
            guard hostile.canBeHit,
                  hostile.position.distance(to: origin) <= Self.autoAimRange,
                  hasLineOfSight(from: origin, to: hostile.position) else { return nil }
            return TargetCandidate(id: Int(hostile.netID), position: hostile.position.world, isTank: hostile.targetKind == .tank)
        }
    }

    func lockedTarget(of player: Player) -> Hostile? {
        guard player.turretAim.mode == .auto, let id = player.lockedTargetID else { return nil }
        return hostiles(for: player).first { Int($0.netID) == id }
    }

    /// Tab: switch to the next visible target (and back to auto-aim).
    func cycleTarget(for player: Player) {
        player.turretAim.cycleTarget()
        player.lockedTargetID = TargetSelector.next(after: player.lockedTargetID, candidates: targetCandidates(for: player),
                                                    from: player.tank.position.world)?.id
    }

    func updateTurret(for player: Player, dt: Double) {
        let tank = player.tank
        player.turretAim.update(dt: dt, manualHeld: player.input.turretManualHeld)
        let maxStep = PlayerTank.turretTurnRate * CGFloat(dt)
        switch player.turretAim.mode {
        case .manual:
            var direction: CGFloat = 0
            if player.input.turretLeft { direction += 1 }
            if player.input.turretRight { direction -= 1 }
            tank.turretAngle += direction * Self.manualTurretRate * CGFloat(dt)
        case .auto:
            player.lockedTargetID = TargetSelector.autoTarget(current: player.lockedTargetID, candidates: targetCandidates(for: player),
                                                              from: tank.position.world)?.id
            // With nothing to track, the turret settles back over the hull's nose.
            let aim = lockedTarget(of: player).map { tank.position.angle(to: $0.position) } ?? tank.heading
            tank.turretAngle = rotateAngle(tank.turretAngle, toward: aim, maxStep: maxStep)
        }
    }

    /// Corner brackets around whatever the local player's turret is locked onto.
    func updateTargetMarker() {
        if let target = lockedTarget(of: localPlayer) {
            targetMarker.isHidden = false
            targetMarker.position = target.position
        } else {
            targetMarker.isHidden = true
        }
    }
}
```

- [ ] **Step 8: Replace `GameScene+Enemies.swift`**

```swift
import SpriteKit
import TanksCore

extension GameScene {
    /// Every tank that blocks movement: players still in play and the AI.
    var allTanks: [TankNode] {
        (players.map(\.tank).filter { !$0.isHidden } as [TankNode]) + (enemies as [TankNode])
    }

    func spawnEnemies() {
        for spawn in level.enemyTanks { addEnemy(spawn, at: level.map.center(spawn.position)) }
    }

    @discardableResult
    func addEnemy(_ spawn: EnemyTankSpawn, at point: CGPoint) -> EnemyTank {
        let tank = EnemyTank(spawn: spawn, difficulty: Difficulty(level: levelNumber))
        tank.netID = makeNetID()
        tank.position = point
        tank.heading = .random(in: -.pi ... .pi)
        tank.turretAngle = tank.heading
        worldNode.addChild(tank)
        enemies.append(tank)
        return tank
    }

    func updateEnemies(dt: Double) {
        for tank in enemies { tank.update(dt: dt, scene: self) }
    }

    func hasLineOfSight(from a: CGPoint, to b: CGPoint, ignoringBuilding: Int? = nil) -> Bool {
        LineOfSight.isClear(in: level.map, from: level.map.grid(a), to: level.map.grid(b), ignoringBuilding: ignoringBuilding)
    }

    /// The player tank an AI unit at `point` should go after: the nearest one it can see, else the nearest one.
    /// Destroyed, respawning and spawn-protected tanks are ignored.
    func aiTarget(from point: CGPoint, sightRange: Double) -> PlayerTank? {
        let candidates = players.map(\.tank)
            .filter { !$0.isDestroyed && !$0.isHidden && !$0.isInvulnerable }
            .sorted { $0.position.distance(to: point) < $1.position.distance(to: point) }
        return candidates.first { Double($0.position.distance(to: point)) <= sightRange && hasLineOfSight(from: point, to: $0.position) }
            ?? candidates.first
    }

    func enemyDestroyed(_ tank: EnemyTank) {
        runStats.tanksDestroyed += 1
        effects.explosion(at: tank.position, scale: 1.8)
        playSound(.bigExplosion, at: tank.position)
        shake(8, duration: 0.3)
        addWreck(Textures.enemyHull, at: tank.position, heading: tank.heading)
        tank.removeFromParent()
        enemies.removeAll { $0 === tank }
    }

    /// A blackened hull left on the ground where a tank died.
    func addWreck(_ texture: SKTexture, at point: CGPoint, heading: CGFloat) {
        let wreck = SKSpriteNode(texture: texture)
        wreck.color = .black
        wreck.colorBlendFactor = 0.75
        wreck.position = point
        wreck.zRotation = heading
        wreck.zPosition = Z.tracks + 0.5
        worldNode.addChild(wreck)
    }
}
```

- [ ] **Step 9: Replace `GameScene+Infantry.swift`**

```swift
import SpriteKit
import TanksCore

extension GameScene {
    func spawnInfantry() {
        var rng = SeededRandom(seed: level.seed ^ 0x5EED)
        for building in level.buildings { buildingWindows[building.id] = windows(of: building) }
        for spawn in level.infantry {
            addSoldier(spawn, initialDelay: Double.random(in: 0...3, using: &rng))
        }
    }

    func addSoldier(_ spawn: InfantrySpawn, initialDelay: Double) {
        let soldier = InfantryNode(spawn: spawn, initialDelay: initialDelay)
        soldier.netID = makeNetID()
        soldier.position = level.buildings[spawn.buildingID].worldCenter
        worldNode.addChild(soldier)
        infantry.append(soldier)
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
        for soldier in infantry {
            guard let windows = buildingWindows[soldier.buildingID], !windows.isEmpty else { continue }
            let aim = aiTarget(from: level.buildings[soldier.buildingID].worldCenter, sightRange: soldier.brain.range)?.position
            let window = aim.map { p in
                windows.min { map.center($0).distance(to: p) < map.center($1).distance(to: p) }!
            } ?? windows[0]
            let windowPoint = map.center(window)
            let distance = aim.map { Double(windowPoint.distance(to: $0)) } ?? .infinity
            let visible = aim.map { distance <= soldier.brain.range
                && LineOfSight.isClear(in: map, from: window, to: map.grid($0), ignoringBuilding: soldier.buildingID) } ?? false

            switch soldier.brain.update(dt: dt, playerVisible: visible, distance: distance) {
            case .expose:
                soldier.position = windowPoint + CGPoint(angle: windowPoint.angle(to: aim ?? windowPoint), length: tileSize * 0.45)
                soldier.post = window
                soldier.removeAllActions()
                soldier.run(.fadeIn(withDuration: 0.15))
                soldier.cooldown = 0.4   // aim before the first shot
            case .hide:
                soldier.removeAllActions()
                soldier.run(.fadeOut(withDuration: 0.25))
            case nil:
                break
            }

            guard soldier.isExposed, let aim else { continue }
            soldier.zRotation = soldier.position.angle(to: aim)
            soldier.cooldown -= dt
            guard soldier.cooldown <= 0 else { continue }
            let weapon = soldier.kind.weapon
            soldier.cooldown = Combat.spec(weapon).reload
            if weapon == .mortar {
                fireMortar(from: soldier.position, at: aim + CGPoint(x: .random(in: -50...50), y: .random(in: -50...50)))
            } else if let post = soldier.post,
                      LineOfSight.isClear(in: map, from: post, to: map.grid(aim)) {
                // Fire only along a clear line from where the soldier actually stands; their own
                // building blocks too (the post tile itself is an endpoint and never blocks).
                fire(weapon, from: soldier.position, angle: soldier.zRotation + .random(in: -0.07...0.07),
                     shooter: .infantry(soldier.kind), ownerBuilding: soldier.buildingID)
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

- [ ] **Step 10: Replace `GameScene+HUD.swift`, `GameScene+Flow.swift` and `GameScene+Input.swift`**

`GameScene+HUD.swift`:

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
        let tank = localPlayer.tank
        hud.update(stats: tank.stats, level: levelNumber, enemiesLeft: enemies.count, inBase: localPlayer.inBase)
        let spotted = enemies.filter { canSpot($0.position) }.map(\.position)
        hud.minimap.update(player: tank.position, enemies: spotted, target: lockedTarget(of: localPlayer)?.position)
    }

    /// The minimap shows a tank only while the local player has eyes on it.
    func canSpot(_ point: CGPoint) -> Bool {
        let eye = localPlayer.tank.position
        return point.distance(to: eye) <= 900 && hasLineOfSight(from: eye, to: point)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        hud?.layout(size: size)
    }
}
```

`GameScene+Flow.swift`:

```swift
import AppKit
import SpriteKit
import TanksCore

extension GameScene {
    func togglePause() {
        guard endTimer == nil else { return }
        isGamePaused.toggle()
        worldNode.isPaused = isGamePaused
        localPlayer.input = InputState()
        hud.setPaused(isGamePaused)
    }

    /// Lets a player stranded without fuel give up the tank instead of being soft-locked.
    func abandonTank(_ player: Player) {
        let tank = player.tank
        guard !isGamePaused, endTimer == nil, !tank.isDestroyed, !tank.isHidden, tank.stats.fuel <= 0 else { return }
        damagePlayer(tank, Int(tank.stats.armor.rounded(.up)), from: nil)
    }

    func checkLevelEnd(dt: Double) {
        guard !levelOver else { return }
        if let remaining = endTimer {
            endTimer = remaining - dt
            if remaining - dt <= 0 { finishLevel() }
            return
        }
        if localPlayer.tank.isDestroyed {
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

`GameScene+Input.swift`:

```swift
import AppKit
import SpriteKit

extension GameScene {
    override func keyDown(with event: NSEvent) {
        setKey(event.keyCode, down: true)
        if !event.isARepeat { handleKeyPress(event.keyCode) }
    }

    func handleKeyPress(_ code: UInt16) {
        switch code {
        case 46: hud.toggleMinimap()                   // M
        case 53: togglePause()                         // Esc
        case 15: abandonTank(localPlayer)              // R
        case 48: cycleTarget(for: localPlayer)         // Tab
        case 12, 14: localPlayer.turretAim.manualInput()   // Q, E
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        setKey(event.keyCode, down: false)
    }

    func setKey(_ code: UInt16, down: Bool) {
        switch code {
        case 13, 126: localPlayer.input.forward = down    // W, up arrow
        case 1, 125: localPlayer.input.backward = down    // S, down arrow
        case 0, 123: localPlayer.input.left = down        // A, left arrow
        case 2, 124: localPlayer.input.right = down       // D, right arrow
        case 49: localPlayer.input.space = down
        case 3: localPlayer.input.fKey = down             // F
        case 12: localPlayer.input.turretLeft = down      // Q
        case 14: localPlayer.input.turretRight = down     // E
        default: break
        }
    }
}
```

- [ ] **Step 11: Build and run the tests**

Run: `swift build 2>&1 | grep -E "error|warning: unused|Compiling|Build complete" | tail -20 && swift test 2>&1 | tail -3`
Expected: `Build complete!` and all tests passing. If the compiler reports any remaining use of `playerTank`, `input`, `turretAim`, `lockedTargetID`, `inBase`, `hostiles` (the old property) or `byPlayer`, change it to the per-player form above. Those names no longer exist on `GameScene`.

- [ ] **Step 12: Launch check and manual campaign check**

Run the **Launch check** from the top of Phase B. Then play `swift run TanksOfDoom` for a couple of minutes and confirm all of these behave exactly as before this task:
- The tank starts at BASE facing up-right. Driving, turning, fuel use and tracks all work.
- Auto-aim locks onto enemy tanks first. Tab cycles targets, Q/E manual aim hands back after 3 s, and the red brackets follow the lock.
- The main gun hurts tanks, infantry and buildings. The MG hurts infantry only. Enemy shells, infantry fire and mortars hurt you, with screen shake and the hit sound.
- Gas and ammo pickups work. BASE repairs and refuels.
- Clearing the level shows LEVEL CLEAR. Dying shows TANK DESTROYED and then GAME OVER. With 0 fuel, R abandons the tank.

- [ ] **Step 13: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "refactor(app): players array, shooter-aware combat and per-player aiming

The campaign has one Player; behaviour is unchanged. Projectiles now record who fired them, so
player tanks can be hit by each other, and the AI targets the nearest player.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Versus rules on one Mac (hot-seat debug mode)

**Files:**
- Create: `Sources/TanksOfDoom/GameMode.swift`, `Sources/TanksOfDoom/GameScene+Versus.swift`
- Modify: `Sources/TanksOfDoom/GameScene.swift`, `GameScene+Player.swift`, `GameScene+Combat.swift`, `GameScene+Enemies.swift`, `GameScene+Infantry.swift`, `GameScene+Flow.swift`, `GameScene+Input.swift`, `Pickups.swift`, `MenuScene.swift`, `AppDelegate.swift`

**Interfaces:**
- Consumes: Task 4's `Player`/`GameScene` API; `MatchState`, `MatchSettings`, `KillFeed` (Task 2); `RespawnPicker`, `RespawnQueue`, `VersusTimings` (Task 3); `CityGenerator.generate(seed:level:bases:)` (Task 1).
- Produces:
  - `enum VersusRole { case hotSeat; var localSlot: PlayerSlot; var isHost: Bool; var isGuest: Bool }`, `enum GameMode { case campaign, versus(VersusRole) }`
  - `GameScene.init(size:versus:role:)` (alongside the unchanged campaign init), `GameScene.mode`, `GameScene.match: MatchState?`
  - `GameScene.isVersus`, `player(_ slot: PlayerSlot) -> Player`, `updateVersus(dt:)`, `playerDestroyed(_:by:)`, `respawn(_:)`, `matchEnded(winner:)`, `versusResult() -> VersusResult`
  - `struct VersusResult { winner: PlayerSlot; localSlot: PlayerSlot; lives: [PlayerSlot: Int]; kills: [PlayerSlot: Int] }`
  - `MenuScene.versusResult(size:result:) -> MenuScene`
  - `PickupNode.isAvailable`
  - Environment variable `TANKS_HOTSEAT=1`. The second player uses I/K/J/L to drive, U/O for the turret, N for the main gun, B for the MG and H for the next target.

- [ ] **Step 1: Add the game mode**

Create `Sources/TanksOfDoom/GameMode.swift`:

```swift
import TanksCore

/// How this Mac takes part in a versus match.
enum VersusRole {
    /// Debug only: both players on this keyboard (TANKS_HOTSEAT=1).
    case hotSeat

    /// The player at this keyboard.
    var localSlot: PlayerSlot {
        switch self {
        case .hotSeat: return .host
        }
    }

    /// This Mac runs the simulation and streams it to another Mac.
    var isHost: Bool {
        switch self {
        case .hotSeat: return false
        }
    }

    /// This Mac only mirrors what the host sends.
    var isGuest: Bool {
        switch self {
        case .hotSeat: return false
        }
    }
}

enum GameMode {
    case campaign
    case versus(VersusRole)
}
```

- [ ] **Step 2: Give `GameScene` a mode, a match and the respawn queues**

In `Sources/TanksOfDoom/GameScene.swift`:

Add these stored properties below `let localPlayer: Player`:

```swift
    let mode: GameMode
    /// Lives, respawns and the winner. Nil in the campaign, and on a networked guest (the host keeps score).
    var match: MatchState?
    var aiTankQueue = RespawnQueue<EnemyTankSpawn>()
    var infantryQueue = RespawnQueue<InfantrySpawn>()
    var pickupQueue = RespawnQueue<Int>()
```

Replace `init(size:levelNumber:runStats:)` with these three initializers:

```swift
    convenience init(size: CGSize, levelNumber: Int, runStats: RunStats) {
        let level = CityGenerator.generate(seed: .random(in: 0...UInt64.max), level: levelNumber)
        self.init(size: size, mode: .campaign, level: level, levelNumber: levelNumber, runStats: runStats,
                  players: [Player(slot: .host)], localSlot: .host)
    }

    convenience init(size: CGSize, versus settings: MatchSettings, role: VersusRole) {
        let difficulty = settings.aiIntensity.difficultyLevel
        let level = CityGenerator.generate(seed: settings.seed, level: difficulty, bases: 2)
        self.init(size: size, mode: .versus(role), level: level, levelNumber: difficulty, runStats: RunStats(),
                  players: PlayerSlot.allCases.map(Player.init(slot:)), localSlot: role.localSlot)
        if !role.isGuest { match = MatchState(settings: settings) }
    }

    private init(size: CGSize, mode: GameMode, level: Level, levelNumber: Int, runStats: RunStats,
                 players: [Player], localSlot: PlayerSlot) {
        self.mode = mode
        self.level = level
        self.levelNumber = levelNumber
        self.runStats = runStats
        self.players = players
        localPlayer = players.first { $0.slot == localSlot }!
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
    }
```

In `buildWorld()`, replace the three `baseLabel` lines with:

```swift
        for (index, base) in level.bases.enumerated() {
            addBaseMarker(base, owner: isVersus ? PlayerSlot(rawValue: index) : nil)
        }
```

and add this method after `buildWorld()`:

```swift
    /// "BASE" painted on the ground; in versus, tinted in the owner's colour.
    private func addBaseMarker(_ base: BaseSite, owner: PlayerSlot?) {
        let label = SKLabelNode.make("BASE", size: 40, color: owner.map { $0.color.withAlphaComponent(0.7) } ?? NSColor(white: 1, alpha: 0.35))
        label.position = level.map.center(base.center) - CGPoint(x: tileSize / 2, y: tileSize / 2)
        label.zPosition = Z.tracks
        worldNode.addChild(label)
        guard let owner else { return }
        let xs = base.tiles.map(\.x)
        let ys = base.tiles.map(\.y)
        let tint = SKSpriteNode(color: owner.color.withAlphaComponent(0.18),
                                size: CGSize(width: CGFloat(xs.max()! - xs.min()! + 1) * tileSize,
                                             height: CGFloat(ys.max()! - ys.min()! + 1) * tileSize))
        tint.anchorPoint = .zero
        tint.position = CGPoint(x: CGFloat(xs.min()!) * tileSize, y: CGFloat(ys.min()!) * tileSize)
        tint.zPosition = Z.ground + 0.5
        worldNode.addChild(tint)
    }
```

In `update(_:)`, add `updateVersus(dt: dt)` on the line after `updateMortars(dt: dt)`.

- [ ] **Step 3: Make pickups hide instead of disappearing**

Replace `Sources/TanksOfDoom/Pickups.swift` with:

```swift
import SpriteKit
import TanksCore

final class PickupNode: SKSpriteNode {
    let kind: CacheKind
    /// Collected pickups stay in the scene, hidden, so versus can bring them back (and indices stay stable for the guest).
    var isAvailable = true {
        didSet { isHidden = !isAvailable }
    }

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

In `GameScene+Player.swift`, replace `collectPickups(for:)` with:

```swift
    func collectPickups(for player: Player) {
        let tank = player.tank
        for (index, pickup) in pickups.enumerated() where pickup.isAvailable && pickup.position.distance(to: tank.position) < 40 {
            tank.stats.collect(pickup.kind)
            effects.floatingText(pickup.kind == .gas ? "+GAS" : "+AMMO", at: pickup.position, color: .systemGreen)
            if player === localPlayer { Audio.shared.play(.pickup) }
            pickup.isAvailable = false
            if isVersus { pickupQueue.schedule(index, after: VersusTimings.pickupRespawn) }
        }
    }
```

- [ ] **Step 4: Write the versus rules**

Create `Sources/TanksOfDoom/GameScene+Versus.swift`:

```swift
import AppKit
import SpriteKit
import TanksCore

/// What the result screen shows.
struct VersusResult {
    let winner: PlayerSlot
    let localSlot: PlayerSlot
    let lives: [PlayerSlot: Int]
    let kills: [PlayerSlot: Int]
}

extension GameScene {
    var isVersus: Bool {
        if case .versus = mode { return true }
        return false
    }

    var versusRole: VersusRole? {
        if case .versus(let role) = mode { return role }
        return nil
    }

    func player(_ slot: PlayerSlot) -> Player {
        players.first { $0.slot == slot }!
    }

    /// Lives, respawns and AI/pickup replenishment, where the match is simulated (host or hot-seat).
    func updateVersus(dt: Double) {
        guard match != nil else { return }
        for slot in match?.tick(dt: dt) ?? [] { respawn(player(slot)) }
        for player in players {
            let tank = player.tank
            tank.isInvulnerable = match?.isInvulnerable(player.slot) ?? false
            tank.alpha = tank.isInvulnerable && Int(lastUpdate * 8) % 2 == 0 ? 0.35 : 1
        }
        for spawn in aiTankQueue.tick(dt: dt) { respawnEnemy(spawn) }
        for spawn in infantryQueue.tick(dt: dt) where !level.buildings[spawn.buildingID].isDestroyed {
            addSoldier(spawn, initialDelay: 0)
        }
        for index in pickupQueue.tick(dt: dt) { pickups[index].isAvailable = true }
        if let winner = match?.winner { matchEnded(winner: winner) }
    }

    /// A player tank just blew up: score it, leave a wreck and take the tank off the field until it respawns.
    func playerDestroyed(_ tank: PlayerTank, by killer: Combatant?) {
        guard match != nil, let victim = players.first(where: { $0.tank === tank }) else { return }
        match?.playerDied(victim.slot, killer: killer)
        hud.addKillFeed(KillFeed.line(killer: killer, victim: victim.slot, viewer: localPlayer.slot))
        addWreck(Textures.hull(for: victim.slot), at: tank.position, heading: tank.heading)
        tank.isHidden = true
    }

    func respawn(_ player: Player) {
        var rng = SystemRandomNumberGenerator()
        let opponent = players.first { $0 !== player && !$0.tank.isHidden }.map { level.map.grid($0.tank.position) }
        let spot = RespawnPicker.playerSpawn(in: level.map, reachableFrom: level.bases[player.slot.baseIndex].center,
                                             opponent: opponent, aiTanks: enemies.map { level.map.grid($0.position) },
                                             using: &rng)
        player.tank.respawn(at: level.map.center(spot), heading: .random(in: -.pi ... .pi))
        player.turretAim = TurretAim()
        player.lockedTargetID = nil
        effects.dustPuff(at: player.tank.position)
        if player === localPlayer { cameraBase = player.tank.position }
    }

    func respawnEnemy(_ spawn: EnemyTankSpawn) {
        var rng = SystemRandomNumberGenerator()
        let spot = RespawnPicker.aiTankSpawn(in: level.map, reachableFrom: level.bases[0].center,
                                             players: players.map { level.map.grid($0.tank.position) }, using: &rng)
        addEnemy(spawn, at: level.map.center(spot))
    }

    func matchEnded(winner: PlayerSlot) {
        guard endTimer == nil else { return }
        let won = winner == localPlayer.slot
        endTimer = 3
        hud.flash(won ? "VICTORY!" : "DEFEAT", color: won ? .systemGreen : .systemRed, duration: 3)
    }

    func versusResult() -> VersusResult {
        let state = match ?? MatchState(settings: MatchSettings())
        return VersusResult(winner: state.winner ?? localPlayer.slot, localSlot: localPlayer.slot,
                            lives: state.lives, kills: state.kills)
    }
}
```

- [ ] **Step 5: Hook the rules into combat, enemies, infantry and the level flow**

In `GameScene+Combat.swift`:
- In `updateWeapons(for:dt:)`, add `match?.playerFired(player.slot)` immediately after **each** of the two successful `fire(...)` calls (main gun and MG).
- At the end of `damagePlayer(_:_:from:)`, after `if isLocal { shake(20, duration: 0.6) }`, add:
  ```swift
          playerDestroyed(tank, by: shooter)
  ```

In `GameScene+Enemies.swift`, in `enemyDestroyed(_:)`, add after `runStats.tanksDestroyed += 1`:

```swift
        if isVersus { aiTankQueue.schedule(tank.spawn, after: VersusTimings.aiTankRespawn) }
```

In `GameScene+Infantry.swift`, in `infantryKilled(_:)`, add after `runStats.infantryKilled += 1`:

```swift
        if isVersus {
            infantryQueue.schedule(InfantrySpawn(kind: soldier.kind, buildingID: soldier.buildingID),
                                   after: VersusTimings.infantryRespawn)
        }
```

(`updateVersus` skips the respawn if the building has collapsed by then.)

In `GameScene+Flow.swift`:
- In `checkLevelEnd(dt:)`, insert `guard !isVersus else { return }   // versus ends through the match rules` directly after the `if let remaining = endTimer { ... }` block.
- In `finishLevel()`, insert after `guard let view else { return }`:
  ```swift
          if isVersus {
              view.presentScene(MenuScene.versusResult(size: size, result: versusResult()), transition: .fade(withDuration: 0.8))
              return
          }
  ```

- [ ] **Step 6: Hot-seat keys for the second player**

In `GameScene+Input.swift`, replace `keyDown(with:)` and `keyUp(with:)` with:

```swift
    override func keyDown(with event: NSEvent) {
        if setHotSeatKey(event.keyCode, down: true, isRepeat: event.isARepeat) { return }
        setKey(event.keyCode, down: true)
        if !event.isARepeat { handleKeyPress(event.keyCode) }
    }

    override func keyUp(with event: NSEvent) {
        if setHotSeatKey(event.keyCode, down: false, isRepeat: false) { return }
        setKey(event.keyCode, down: false)
    }
```

and add at the end of the extension:

```swift
    /// Debug hot-seat: the second player drives with I/J/K/L, turns the turret with U/O,
    /// fires with N (main gun) and B (MG), and H picks the next target.
    private func setHotSeatKey(_ code: UInt16, down: Bool, isRepeat: Bool) -> Bool {
        guard case .versus(.hotSeat) = mode else { return false }
        let second = player(.guest)
        switch code {
        case 34: second.input.forward = down        // I
        case 40: second.input.backward = down       // K
        case 38: second.input.left = down           // J
        case 37: second.input.right = down          // L
        case 32:                                    // U
            second.input.turretLeft = down
            if down { second.turretAim.manualInput() }
        case 31:                                    // O
            second.input.turretRight = down
            if down { second.turretAim.manualInput() }
        case 45: second.input.space = down          // N
        case 11: second.input.fKey = down           // B
        case 4: if down && !isRepeat { cycleTarget(for: second) }   // H
        default: return false
        }
        return true
    }
```

- [ ] **Step 7: Result screen and the hot-seat launch switch**

In `Sources/TanksOfDoom/MenuScene.swift`, add at the end of the file:

```swift
extension MenuScene {
    static func versusResult(size: CGSize, result: VersusResult) -> MenuScene {
        let mono = "Menlo-Bold"
        let me = result.localSlot
        let them = me.opponent
        let won = result.winner == me
        let lines = [
            Line(text: won ? "VICTORY" : "DEFEAT", size: 88, color: won ? .systemGreen : .systemRed),
            Line(text: "You: \(result.lives[me] ?? 0) lives left, \(result.kills[me] ?? 0) kills", size: 22, color: me.color, font: mono),
            Line(text: "Opponent: \(result.lives[them] ?? 0) lives left, \(result.kills[them] ?? 0) kills", size: 22, color: them.color, font: mono),
        ]
        return MenuScene(size: size, lines: lines, prompt: "PRESS ENTER TO CONTINUE") { scene in
            scene.view?.presentScene(MenuScene.title(size: scene.size), transition: .fade(withDuration: 0.6))
        }
    }
}
```

In `Sources/TanksOfDoom/AppDelegate.swift`, replace the `if let level = ... { ... } else { ... }` block in `applicationDidFinishLaunching` with:

```swift
        let env = ProcessInfo.processInfo.environment
        // Developer shortcut: TANKS_START_LEVEL=<n> skips the title screen and opens the
        // window in the background without taking keyboard focus.
        if let level = env["TANKS_START_LEVEL"].flatMap(Int.init), level > 0 {
            window.orderFront(nil)
            view.presentScene(GameScene(size: frame.size, levelNumber: level, runStats: RunStats()))
        } else if env["TANKS_HOTSEAT"] == "1" {
            // Developer shortcut: a versus match with both players on this keyboard.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            let settings = MatchSettings(lives: 3, aiIntensity: .normal, seed: .random(in: 0...UInt64.max))
            view.presentScene(GameScene(size: frame.size, versus: settings, role: .hotSeat))
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            view.presentScene(MenuScene.title(size: frame.size))
        }
```

and add `import TanksCore` at the top of `AppDelegate.swift`.

- [ ] **Step 8: Build, test, launch check**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`, then the **Launch check**.
Expected: `Build complete!`, all tests pass, `still running after 8 s: OK`.

- [ ] **Step 9: Manual hot-seat check**

Run `TANKS_HOTSEAT=1 swift run TanksOfDoom` and confirm:
- Two bases appear: olive bottom-left (you) and blue top-right (player 2). Both tanks start at their bases facing the middle.
- Driving player 2 (I/J/K/L) toward player 1 and pressing N shoots player 1 for 40 damage per direct hit. Auto-aim (H, or just being in range) can lock onto the other tank.
- When a tank dies, a wreck stays behind, the tank vanishes, and after 3 s it reappears somewhere random and blinks for 3 s (or until it fires). It can't be damaged while blinking.
- AI tanks and snipers attack whichever player is nearest, not just player 1. A destroyed AI tank comes back about 20 s later, far from both players.
- A picked-up gas can reappears after 45 s.
- You can only repair at your own base (park player 1 on the blue base: no repair).
- At 0 lives: "VICTORY!" or "DEFEAT" (from player 1's point of view), then the result screen. Enter returns to the title.
- The campaign (`swift run TanksOfDoom`, Enter) still plays exactly as in Task 4.

- [ ] **Step 10: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): versus rules with lives, respawns and AI/pickup replenishment; hot-seat debug mode

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Versus HUD: lives, kill feed, respawn countdown, opponent on the minimap

**Files:**
- Modify: `Sources/TanksOfDoom/HUD.swift`, `Sources/TanksOfDoom/Minimap.swift`, `Sources/TanksOfDoom/GameScene+HUD.swift`, `Sources/TanksOfDoom/GameScene+Versus.swift`

**Interfaces:**
- Consumes: `GameScene.match`, `isVersus`, `localPlayer`, `PlayerSlot.color`.
- Produces:
  - `struct VersusHUDState { var localSlot: PlayerSlot; var lives: [PlayerSlot: Int]; var respawnIn: Double?; var latencyMs: Int?; var notice: String? }`
  - `HUD(level:versus:)`, `HUD.updateVersus(_:)`, `HUD.addKillFeed(_:)`
  - `Minimap.update(player:enemies:target:opponent:)` where `opponent: (position: CGPoint, color: NSColor)?`
  - `GameScene.versusHUDState() -> VersusHUDState?` (Tasks 12 and 13 extend it)

- [ ] **Step 1: HUD additions**

In `Sources/TanksOfDoom/HUD.swift`, add above `final class HUD`:

```swift
/// Everything the versus overlay shows, from whichever side knows it (the host's match or the guest's snapshots).
struct VersusHUDState {
    var localSlot: PlayerSlot
    var lives: [PlayerSlot: Int]
    var respawnIn: Double?
    var latencyMs: Int?
    var notice: String?
}
```

In `final class HUD`, add these properties below `pausedLabel`:

```swift
    private let isVersus: Bool
    private let livesLabel = SKLabelNode.hud(size: 20)
    private let respawnLabel = SKLabelNode.make("", size: 44)
    private let livesLeftLabel = SKLabelNode.make("", size: 24, color: .lightGray)
    private let noticeLabel = SKLabelNode.make("", size: 30, color: .systemOrange)
    private let latencyLabel = SKLabelNode.hud(size: 13)
    private var killFeed: [SKLabelNode] = []
```

Replace `init(level:)` with:

```swift
    init(level: Level, versus: Bool = false) {
        minimap = Minimap(map: level.map)
        isVersus = versus
        super.init()
        zPosition = Z.hud
        ammoLabel.horizontalAlignmentMode = .left
        levelLabel.horizontalAlignmentMode = .right
        enemiesLabel.horizontalAlignmentMode = .right
        latencyLabel.horizontalAlignmentMode = .left
        latencyLabel.fontColor = .lightGray
        messageLabel.alpha = 0
        // Text stays readable on top of the (enlarged) minimap.
        statusLabel.zPosition = 5
        messageLabel.zPosition = 5
        pausedLabel.zPosition = 6
        pausedLabel.isHidden = true
        for label in [respawnLabel, livesLeftLabel, noticeLabel] {
            label.zPosition = 6
            label.isHidden = true
        }
        levelLabel.isHidden = versus
        enemiesLabel.isHidden = versus
        livesLabel.isHidden = !versus
        for node in [armorBar, fuelBar, ammoLabel, levelLabel, enemiesLabel, statusLabel, messageLabel, pausedLabel, minimap,
                     livesLabel, respawnLabel, livesLeftLabel, noticeLabel, latencyLabel] as [SKNode] {
            addChild(node)
        }
    }
```

At the end of `layout(size:)`, add:

```swift
        livesLabel.position = CGPoint(x: 0, y: top)
        respawnLabel.position = CGPoint(x: 0, y: 40)
        livesLeftLabel.position = CGPoint(x: 0, y: -10)
        noticeLabel.position = CGPoint(x: 0, y: size.height / 2 - 160)
        latencyLabel.position = CGPoint(x: left, y: bottom + 16)
        layoutKillFeed()
```

Add these methods to `HUD`:

```swift
    func updateVersus(_ state: VersusHUDState) {
        let me = state.localSlot
        let font = NSFont(name: "Menlo-Bold", size: 20) ?? .boldSystemFont(ofSize: 20)
        let text = NSMutableAttributedString()
        func add(_ string: String, _ color: NSColor) {
            text.append(NSAttributedString(string: string, attributes: [.foregroundColor: color, .font: font]))
        }
        add("YOU \(Self.hearts(state.lives[me] ?? 0))", me.color)
        add("     ", .white)
        add("OPPONENT \(Self.hearts(state.lives[me.opponent] ?? 0))", me.opponent.color)
        livesLabel.attributedText = text

        if let seconds = state.respawnIn {
            respawnLabel.isHidden = false
            livesLeftLabel.isHidden = false
            respawnLabel.text = "RESPAWNING IN \(Int(seconds.rounded(.up)))…"
            livesLeftLabel.text = "LIVES LEFT: \(state.lives[me] ?? 0)"
        } else {
            respawnLabel.isHidden = true
            livesLeftLabel.isHidden = true
        }
        noticeLabel.isHidden = state.notice == nil
        noticeLabel.text = state.notice
        latencyLabel.text = state.latencyMs.map { "\($0) ms" } ?? ""
    }

    /// Newest line on top; at most three, each fading after six seconds.
    func addKillFeed(_ line: String) {
        let label = SKLabelNode.hud(size: 15)
        label.text = line
        label.horizontalAlignmentMode = .right
        label.zPosition = 5
        addChild(label)
        label.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
        killFeed.removeAll { $0.parent == nil }
        killFeed.insert(label, at: 0)
        while killFeed.count > 3 { killFeed.removeLast().removeFromParent() }
        layoutKillFeed()
    }

    private func layoutKillFeed() {
        let right = lastSize.width / 2 - 20
        let top = lastSize.height / 2 - 24
        for (index, label) in killFeed.enumerated() {
            label.position = CGPoint(x: right, y: top - CGFloat(index) * 22)
        }
    }

    private static func hearts(_ count: Int) -> String {
        count <= 0 ? "–" : String(repeating: "♥", count: count)
    }
```

- [ ] **Step 2: Opponent dot on the minimap**

In `Sources/TanksOfDoom/Minimap.swift`, add a property below `targetRing`:

```swift
    private let opponentDot = SKShapeNode(circleOfRadius: 4)
```

In `init(map:)`, before `resize()`, add:

```swift
        opponentDot.strokeColor = .white
        opponentDot.lineWidth = 1
        opponentDot.zPosition = 3
        opponentDot.isHidden = true
        addChild(opponentDot)
```

Replace `update(player:enemies:target:)` with:

```swift
    func update(player: CGPoint, enemies: [CGPoint], target: CGPoint? = nil, opponent: (position: CGPoint, color: NSColor)? = nil) {
        playerDot.position = project(player)
        targetRing.isHidden = target == nil
        if let target { targetRing.position = project(target) }
        opponentDot.isHidden = opponent == nil
        if let opponent {
            opponentDot.position = project(opponent.position)
            opponentDot.fillColor = opponent.color
        }
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
```

- [ ] **Step 3: Feed the HUD from the scene**

Replace `setUpHUD()` and `updateHUD()` in `GameScene+HUD.swift` with:

```swift
    func setUpHUD() {
        hud = HUD(level: level, versus: isVersus)
        cameraNode.addChild(hud)
        hud.layout(size: size)
        if let match {
            hud.flash("FIRST TO TAKE ALL \(match.settings.lives) OF THE OTHER'S LIVES WINS", duration: 3)
        } else if !isVersus {
            hud.flash("LEVEL \(levelNumber): DESTROY \(enemies.count) ENEMY TANKS", duration: 3)
        }
    }

    func updateHUD() {
        let tank = localPlayer.tank
        hud.update(stats: tank.stats, level: levelNumber, enemiesLeft: enemies.count, inBase: localPlayer.inBase)
        let spotted = enemies.filter { canSpot($0.position) }.map(\.position)
        let opponent = players.first { $0 !== localPlayer && !$0.tank.isHidden && canSpot($0.tank.position) }
        hud.minimap.update(player: tank.position, enemies: spotted, target: lockedTarget(of: localPlayer)?.position,
                           opponent: opponent.map { (position: $0.tank.position, color: $0.slot.color) })
        if let state = versusHUDState() { hud.updateVersus(state) }
    }
```

In `GameScene+Versus.swift`, add to the extension:

```swift
    /// What the versus overlay should show right now; nil in the campaign.
    func versusHUDState() -> VersusHUDState? {
        guard let match else { return nil }
        return VersusHUDState(localSlot: localPlayer.slot, lives: match.lives,
                              respawnIn: match.respawnRemaining(localPlayer.slot), latencyMs: nil, notice: nil)
    }
```

In `playerDestroyed(_:by:)`, the existing `hud.addKillFeed(...)` call now draws the feed.

- [ ] **Step 4: Build, test, launch check, manual check**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`, then the **Launch check**. Then run `TANKS_HOTSEAT=1 swift run TanksOfDoom` and confirm:
- The top centre reads `YOU ♥♥♥     OPPONENT ♥♥♥` in olive and blue. The LEVEL and ENEMY TANKS labels are gone in versus but still present in the campaign.
- Killing player 2 adds "You destroyed Opponent" top-right. Three or more kills keep only the newest three, and each fades after 6 s.
- Getting killed shows "RESPAWNING IN 3…" counting down and "LIVES LEFT: 2".
- Player 2 shows on the minimap as a blue dot only while in line of sight.
- The window can be resized and everything re-anchors.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): versus HUD with lives, kill feed, respawn countdown and opponent on the minimap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
## Phase C: The wire protocol (TanksNet)

### Task 7: TanksNet target, byte encoding, room codes and relay control messages

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TanksNet/Wire.swift`, `Sources/TanksNet/TanksNet.swift`, `Sources/TanksNet/RelayMessage.swift`
- Test: `Tests/TanksNetTests/WireTests.swift` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `public enum WireError: Error, Equatable { case truncated, badValue(String), trailingBytes }`
  - `public struct Vec2: Equatable, Sendable { var x, y: Float; init(_:_:) }`
  - `public struct ByteWriter { var bytes: [UInt8]; u8, bool, u16, u32, u64, i16, f32, f64, string, vec }`
  - `public struct ByteReader { static let maxStringLength = 256; init(_ bytes: [UInt8]); u8() … vec() throws; count(max:) throws -> Int; raw(_:) throws; isAtEnd; finish() throws }`
  - `public enum TanksNet { static let protocolVersion: UInt16 = 1; roomCodeLength = 5; roomCodeAlphabet; randomRoomCode(using:); normalizeRoomCode(_:) -> String? }`
  - `public enum RelayErrorCode: UInt8, Error { versionMismatch = 1, roomNotFound, roomFull, serverFull, protocolError; var message: String }`
  - `public enum RelayMessage: Equatable { hello(version:), createRoom, roomCreated(code:), joinRoom(code:), joined, error(RelayErrorCode), peerLeft; static let firstGameType: UInt8 = 32; static func isControlFrame(_:) -> Bool; func encoded() -> [UInt8]; static func decode(_:) throws -> RelayMessage }`

- [ ] **Step 1: Add the target**

Replace `Package.swift` with:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TanksOfDoom",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TanksCore"),
        .target(name: "TanksNet", dependencies: ["TanksCore"]),
        .executableTarget(name: "TanksOfDoom", dependencies: ["TanksCore", "TanksNet"]),
        .testTarget(name: "TanksCoreTests", dependencies: ["TanksCore"]),
        .testTarget(name: "TanksNetTests", dependencies: ["TanksNet", "TanksCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/TanksNetTests/WireTests.swift`:

```swift
import Testing
import TanksCore
@testable import TanksNet

@Test func integersAreLittleEndian() {
    var w = ByteWriter()
    w.u16(0x1234)
    w.u32(0xA1B2_C3D4)
    #expect(w.bytes == [0x34, 0x12, 0xD4, 0xC3, 0xB2, 0xA1])
}

@Test func primitivesRoundTrip() throws {
    var w = ByteWriter()
    w.u8(7)
    w.bool(true)
    w.u16(65535)
    w.u32(.max)
    w.u64(0x0102_0304_0506_0708)
    w.i16(-12345)
    w.f32(-1.5)
    w.f64(.pi)
    w.string("Grimsborough ✓")
    w.vec(Vec2(3, -4))
    var r = ByteReader(w.bytes)
    #expect(try r.u8() == 7)
    #expect(try r.bool() == true)
    #expect(try r.u16() == 65535)
    #expect(try r.u32() == .max)
    #expect(try r.u64() == 0x0102_0304_0506_0708)
    #expect(try r.i16() == -12345)
    #expect(try r.f32() == -1.5)
    #expect(try r.f64() == .pi)
    #expect(try r.string() == "Grimsborough ✓")
    #expect(try r.vec() == Vec2(3, -4))
    #expect(r.isAtEnd)
    try r.finish()
}

@Test func readingPastTheEndThrows() {
    var r = ByteReader([1])
    #expect(throws: WireError.truncated) { try r.u16() }
}

@Test func onlyZeroAndOneAreBools() {
    var r = ByteReader([2])
    #expect(throws: WireError.badValue("bool")) { try r.bool() }
}

@Test func nonFiniteFloatsAreRejected() {
    var w = ByteWriter()
    w.f32(.nan)
    w.f64(.infinity)
    var r = ByteReader(w.bytes)
    #expect(throws: WireError.badValue("float")) { try r.f32() }
    var r2 = ByteReader(Array(w.bytes.dropFirst(4)))
    #expect(throws: WireError.badValue("float")) { try r2.f64() }
}

@Test func longStringsAreCappedWhenWrittenAndRejectedWhenRead() throws {
    var w = ByteWriter()
    w.string(String(repeating: "x", count: 1000))
    var r = ByteReader(w.bytes)
    #expect(try r.string().count == ByteReader.maxStringLength)
    var hostile = ByteReader([0x2C, 0x01] + Array(repeating: 0x41, count: 300))   // claims 300 bytes
    #expect(throws: WireError.badValue("string length")) { try hostile.string() }
}

@Test func countsAboveTheCapAreRejected() {
    var r = ByteReader([10, 0])
    #expect(throws: WireError.badValue("count")) { try r.count(max: 9) }
}

@Test func leftoverBytesAreAnError() {
    let r = ByteReader([1])
    #expect(throws: WireError.trailingBytes) { try r.finish() }
}

@Test func randomRoomCodesAreWellFormed() {
    var rng = SeededRandom(seed: 1)
    for _ in 0..<200 {
        let code = TanksNet.randomRoomCode(using: &rng)
        #expect(code.count == 5)
        #expect(TanksNet.normalizeRoomCode(code) == code)
        #expect(!code.contains("I") && !code.contains("O"))
    }
}

@Test func roomCodesAreNormalizedFromWhatPeopleType() {
    #expect(TanksNet.normalizeRoomCode("kxwpq") == "KXWPQ")
    #expect(TanksNet.normalizeRoomCode(" kx-wp q ") == "KXWPQ")
    #expect(TanksNet.normalizeRoomCode("KXWP") == nil)        // too short
    #expect(TanksNet.normalizeRoomCode("KXWPQA") == nil)      // too long
    #expect(TanksNet.normalizeRoomCode("KXWPO") == nil)       // O is never used
    #expect(TanksNet.normalizeRoomCode("KX1PQ") == nil)       // digits are never used
}

@Test func relayMessagesRoundTrip() throws {
    let messages: [RelayMessage] = [
        .hello(version: TanksNet.protocolVersion), .createRoom, .roomCreated(code: "KXWPQ"), .joinRoom(code: "kxwpq"),
        .joined, .error(.roomFull), .error(.versionMismatch), .peerLeft,
    ]
    for message in messages {
        let bytes = message.encoded()
        #expect(RelayMessage.isControlFrame(bytes))
        #expect(try RelayMessage.decode(bytes) == message)
    }
}

@Test func relayDecodingRejectsUnknownTypesBadCodesAndLeftovers() {
    #expect(throws: (any Error).self) { try RelayMessage.decode([]) }
    #expect(throws: (any Error).self) { try RelayMessage.decode([9]) }
    #expect(throws: (any Error).self) { try RelayMessage.decode([6, 99]) }       // unknown error code
    #expect(throws: (any Error).self) { try RelayMessage.decode([2, 0]) }        // trailing byte
}

@Test func controlFramesAreThoseBelowTheFirstGameType() {
    #expect(RelayMessage.isControlFrame([5]))
    #expect(!RelayMessage.isControlFrame([RelayMessage.firstGameType]))
    #expect(!RelayMessage.isControlFrame([]))
}

@Test func errorCodesHaveMessagesForPlayers() {
    #expect(RelayErrorCode.roomNotFound.message == "Room not found")
    #expect(RelayErrorCode.versionMismatch.message == "Version mismatch — update the game")
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter TanksNetTests`
Expected: compile errors: `cannot find 'ByteWriter' in scope` and similar.

- [ ] **Step 4: Implement `Wire.swift`**

Create `Sources/TanksNet/Wire.swift`:

```swift
import Foundation

public enum WireError: Error, Equatable {
    case truncated
    case badValue(String)
    case trailingBytes
}

/// A world position or direction on the wire (Float is plenty for a 5120 pt map).
public struct Vec2: Equatable, Sendable {
    public var x: Float
    public var y: Float

    public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }
}

/// Appends little-endian values to a byte array.
public struct ByteWriter {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func u8(_ v: UInt8) { bytes.append(v) }
    public mutating func bool(_ v: Bool) { u8(v ? 1 : 0) }
    public mutating func u16(_ v: UInt16) { append(v) }
    public mutating func u32(_ v: UInt32) { append(v) }
    public mutating func u64(_ v: UInt64) { append(v) }
    public mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    public mutating func f32(_ v: Float) { u32(v.bitPattern) }
    public mutating func f64(_ v: Double) { u64(v.bitPattern) }

    /// UTF-8 with a 16-bit length, cut to `ByteReader.maxStringLength` bytes.
    public mutating func string(_ s: String) {
        let utf8 = Array(s.utf8.prefix(ByteReader.maxStringLength))
        u16(UInt16(utf8.count))
        bytes.append(contentsOf: utf8)
    }

    public mutating func vec(_ v: Vec2) {
        f32(v.x)
        f32(v.y)
    }

    private mutating func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }
}

/// Reads what `ByteWriter` wrote. Every read checks bounds and throws instead of trapping, because
/// the bytes come from the network.
public struct ByteReader {
    public static let maxStringLength = 256

    private let bytes: [UInt8]
    private var offset = 0

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    public var isAtEnd: Bool { offset == bytes.count }

    public mutating func u8() throws -> UInt8 { try take(1)[0] }
    public mutating func u16() throws -> UInt16 { try little() }
    public mutating func u32() throws -> UInt32 { try little() }
    public mutating func u64() throws -> UInt64 { try little() }
    public mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }

    public mutating func bool() throws -> Bool {
        switch try u8() {
        case 0: return false
        case 1: return true
        default: throw WireError.badValue("bool")
        }
    }

    public mutating func f32() throws -> Float {
        let value = Float(bitPattern: try u32())
        guard value.isFinite else { throw WireError.badValue("float") }
        return value
    }

    public mutating func f64() throws -> Double {
        let value = Double(bitPattern: try u64())
        guard value.isFinite else { throw WireError.badValue("float") }
        return value
    }

    public mutating func string() throws -> String {
        let length = Int(try u16())
        guard length <= Self.maxStringLength else { throw WireError.badValue("string length") }
        return String(decoding: try take(length), as: UTF8.self)
    }

    public mutating func vec() throws -> Vec2 {
        Vec2(try f32(), try f32())
    }

    /// An array length, capped so a hostile length can't make us allocate a huge buffer.
    public mutating func count(max: Int) throws -> Int {
        let n = Int(try u16())
        guard n <= max else { throw WireError.badValue("count") }
        return n
    }

    public mutating func raw<E: RawRepresentable>(_ type: E.Type) throws -> E where E.RawValue == UInt8 {
        guard let value = E(rawValue: try u8()) else { throw WireError.badValue("\(E.self)") }
        return value
    }

    /// Call after reading a whole message: leftovers mean the sender and receiver disagree about the format.
    public func finish() throws {
        guard isAtEnd else { throw WireError.trailingBytes }
    }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard bytes.count - offset >= n else { throw WireError.truncated }
        defer { offset += n }
        return bytes[offset..<(offset + n)]
    }

    private mutating func little<T: FixedWidthInteger>() throws -> T {
        var value: T = 0
        for (index, byte) in try take(MemoryLayout<T>.size).enumerated() {
            value |= T(byte) << (8 * index)
        }
        return value
    }
}
```

- [ ] **Step 5: Implement `TanksNet.swift` and `RelayMessage.swift`**

Create `Sources/TanksNet/TanksNet.swift`:

```swift
import Foundation

public enum TanksNet {
    /// Bump on any change to the bytes on the wire; the relay turns away games that disagree.
    public static let protocolVersion: UInt16 = 1
    public static let roomCodeLength = 5
    /// No I or O, so a code read aloud can't be mistaken for 1 or 0.
    public static let roomCodeAlphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")

    public static func randomRoomCode(using rng: inout some RandomNumberGenerator) -> String {
        String((0..<roomCodeLength).map { _ in roomCodeAlphabet.randomElement(using: &rng)! })
    }

    /// Upper-cases and drops spaces and dashes; nil unless what's left is a well-formed code.
    public static func normalizeRoomCode(_ input: String) -> String? {
        let code = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard code.count == roomCodeLength, code.allSatisfy(roomCodeAlphabet.contains) else { return nil }
        return code
    }
}
```

Create `Sources/TanksNet/RelayMessage.swift`:

```swift
import Foundation

public enum RelayErrorCode: UInt8, Error, Sendable {
    case versionMismatch = 1
    case roomNotFound = 2
    case roomFull = 3
    case serverFull = 4
    case protocolError = 5

    /// What the player sees.
    public var message: String {
        switch self {
        case .versionMismatch: return "Version mismatch — update the game"
        case .roomNotFound: return "Room not found"
        case .roomFull: return "Room full"
        case .serverFull: return "Server full — try again later"
        case .protocolError: return "Connection error"
        }
    }
}

/// Frames between a game and the relay itself. Their type bytes are 1–31; game frames (32 and up)
/// pass through the relay untouched once two players are paired.
public enum RelayMessage: Equatable, Sendable {
    case hello(version: UInt16)
    case createRoom
    case roomCreated(code: String)
    case joinRoom(code: String)
    case joined
    case error(RelayErrorCode)
    case peerLeft

    public static let firstGameType: UInt8 = 32

    public static func isControlFrame(_ bytes: [UInt8]) -> Bool {
        guard let type = bytes.first else { return false }
        return type < firstGameType
    }

    public func encoded() -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case .hello(let version):
            w.u8(1)
            w.u16(version)
        case .createRoom:
            w.u8(2)
        case .roomCreated(let code):
            w.u8(3)
            w.string(code)
        case .joinRoom(let code):
            w.u8(4)
            w.string(code)
        case .joined:
            w.u8(5)
        case .error(let code):
            w.u8(6)
            w.u8(code.rawValue)
        case .peerLeft:
            w.u8(7)
        }
        return w.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> RelayMessage {
        var r = ByteReader(bytes)
        let message: RelayMessage
        switch try r.u8() {
        case 1: message = .hello(version: try r.u16())
        case 2: message = .createRoom
        case 3: message = .roomCreated(code: try r.string())
        case 4: message = .joinRoom(code: try r.string())
        case 5: message = .joined
        case 6: message = .error(try r.raw(RelayErrorCode.self))
        case 7: message = .peerLeft
        case let type: throw WireError.badValue("relay message type \(type)")
        }
        try r.finish()
        return message
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter TanksNetTests && swift build 2>&1 | tail -1`
Expected: all TanksNet tests pass; `Build complete!`.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/TanksNet Tests/TanksNetTests
git commit -m "feat(net): TanksNet library with byte encoding, room codes and relay control messages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Game messages, snapshots, events and the sync helpers

**Files:**
- Create: `Sources/TanksNet/GameMessage.swift`, `Sources/TanksNet/NetSync.swift`
- Test: `Tests/TanksNetTests/MessageTests.swift`, `Tests/TanksNetTests/NetSyncTests.swift` (new)

**Interfaces:**
- Consumes: Task 7's `ByteWriter`/`ByteReader`/`Vec2`/`WireError`; `PlayerSlot`, `MatchSettings`, `AIIntensity`, `Combatant` (Task 2); `WeaponKind`, `InfantryKind` (existing).
- Produces:
  - `public enum FXColor: UInt8 { white, red, yellow, green, orange }`
  - `public enum SoundID: UInt8, CaseIterable { cannon, machineGun, explosion, bigExplosion, hit, rocket, pickup, empty }`. The case names must match the existing `Audio.Sound` exactly, because Task 11 makes `Audio.Sound` a typealias for `SoundID`.
  - `public struct InputFrame { seq: UInt32; held: UInt8; presses: UInt8 }` with held-bit constants `forward, backward, left, right, turretLeft, turretRight, fireMain, fireMG` and press bits `cycleTarget, manualTurret, abandon`
  - `public struct PlayerSnapshot { slot, position: Vec2, heading, turret, armor, fuel: Float, shells, rounds: UInt16, lives: UInt8, kills: UInt16, flags: UInt8, respawnIn: Float, lockedTarget: UInt32; flag constants destroyed, invulnerable, respawning, inBase; func has(_:) -> Bool }`
  - `public struct EnemyTankSnapshot { id: UInt32, position: Vec2, heading, turret, health: Float }`
  - `public struct SoldierSnapshot { id: UInt32, kind: InfantryKind, position: Vec2, facing: Float }`
  - `public struct ShotSnapshot { id: UInt32, weapon: WeaponKind, position: Vec2, angle: Float }`
  - `public struct MortarSnapshot { id: UInt32, start: Vec2, target: Vec2, progress: Float }`
  - `public struct Snapshot { tick: UInt32, time: Double, ackInputSeq: UInt32, players, tanks, soldiers, shots, mortars, pickups: [Bool], events: [GameEvent] }`. The array parameters of `init` default to `[]`.
  - `public enum GameEvent { explosion(at:scale:), spark(at:), dust(at:), muzzleFlash(at:angle:big:), text(_:at:color:), sound(_:at:volume:), uiSound(_:volume:), shake(magnitude:duration:), buildingHP(id: UInt16, hp: Int16), kill(killer: Combatant?, victim: PlayerSlot), flash(_:color:duration:), matchOver(winner:) }`
  - `public enum GameMessage { lobby(MatchSettings), guestReady(Bool), matchStart(MatchSettings), input(InputFrame), snapshot(Snapshot), ping(Double), pong(Double), leave, rematch; func encoded() -> [UInt8]; static func decode(_:) throws -> GameMessage }`
  - `public struct RemoteInput { static let staleAfter = 0.25; lastSeq; receive(_:at:); heldKeys(at:) -> UInt8; takePresses() -> UInt8 }`
  - `public struct SnapshotBuffer { static let delay = 0.1, capacity = 30; latest: Snapshot?; insert(_:receivedAt:) -> Bool; frame(at:) -> Frame?; struct Frame { from, to: Snapshot; t: Double } }`
  - `public struct InputHistory<Input> { struct Entry { seq: UInt32; input: Input; dt: Double }; entries; record(seq:input:dt:); acknowledge(through:) }`
  - `Vec2.lerp(to:_:) -> Vec2`, `public func lerpAngle(_ a: Float, _ b: Float, _ t: Double) -> Float`

- [ ] **Step 1: Write the failing message tests**

Create `Tests/TanksNetTests/MessageTests.swift`:

```swift
import Testing
import TanksCore
@testable import TanksNet

let allEvents: [GameEvent] = [
    .explosion(at: Vec2(1, 2), scale: 1.5),
    .spark(at: Vec2(3, 4)),
    .dust(at: Vec2(5, 6)),
    .muzzleFlash(at: Vec2(7, 8), angle: -0.75, big: true),
    .text("-12", at: Vec2(9, 10), color: .red),
    .sound(.cannon, at: Vec2(11, 12), volume: 0.7),
    .uiSound(.hit, volume: 0.8),
    .shake(magnitude: 4, duration: 0.15),
    .buildingHP(id: 12, hp: 0),
    .kill(killer: .player(.host), victim: .guest),
    .kill(killer: nil, victim: .host),
    .kill(killer: .infantry(.mortar), victim: .guest),
    .kill(killer: .enemyTank, victim: .host),
    .flash("GO!", color: .green, duration: 0.8),
    .matchOver(winner: .guest),
]

func sampleSnapshot() -> Snapshot {
    Snapshot(
        tick: 42, time: 1234.5, ackInputSeq: 7,
        players: [
            PlayerSnapshot(slot: .host, position: Vec2(100, 200), heading: 0.5, turret: -1, armor: 80, fuel: 55.5,
                           shells: 12, rounds: 250, lives: 3, kills: 1, flags: PlayerSnapshot.inBase, respawnIn: 0, lockedTarget: 2),
            PlayerSnapshot(slot: .guest, position: Vec2(4000, 4100), heading: 3, turret: 3, armor: 0, fuel: 10,
                           shells: 0, rounds: 0, lives: 2, kills: 0, flags: PlayerSnapshot.respawning | PlayerSnapshot.destroyed,
                           respawnIn: 2.5, lockedTarget: 0),
        ],
        tanks: [EnemyTankSnapshot(id: 17, position: Vec2(1000, 900), heading: 3, turret: 2, health: 0.4)],
        soldiers: [SoldierSnapshot(id: 30, kind: .bazooka, position: Vec2(5, 6), facing: 1.25)],
        shots: [ShotSnapshot(id: 99, weapon: .machineGun, position: Vec2(7, 8), angle: 0.1)],
        mortars: [MortarSnapshot(id: 120, start: Vec2(1, 2), target: Vec2(3, 4), progress: 0.5)],
        pickups: [true, false, true, true, false, false, false, true, true],
        events: allEvents)
}

let allMessages: [GameMessage] = [
    .lobby(MatchSettings(lives: 5, aiIntensity: .heavy, seed: 77)),
    .guestReady(true),
    .matchStart(MatchSettings(lives: 1, aiIntensity: .light, seed: .max)),
    .input(InputFrame(seq: 9, held: InputFrame.forward | InputFrame.fireMG, presses: InputFrame.cycleTarget)),
    .snapshot(sampleSnapshot()),
    .snapshot(Snapshot(tick: 1, time: 0, ackInputSeq: 0)),
    .ping(12.25),
    .pong(12.25),
    .leave,
    .rematch,
]

@Test func everyGameMessageRoundTrips() throws {
    for message in allMessages {
        #expect(try GameMessage.decode(message.encoded()) == message)
    }
}

@Test func gameMessagesAreNeverRelayControlFrames() {
    for message in allMessages {
        #expect(!RelayMessage.isControlFrame(message.encoded()))
    }
}

@Test func everyTruncationThrowsInsteadOfCrashing() {
    for message in allMessages {
        let bytes = message.encoded()
        for length in 0..<bytes.count {
            #expect(throws: (any Error).self) { try GameMessage.decode(Array(bytes.prefix(length))) }
        }
    }
}

@Test func trailingBytesAreRejected() {
    #expect(throws: WireError.trailingBytes) { try GameMessage.decode(GameMessage.leave.encoded() + [0]) }
}

@Test func randomGarbageNeverCrashes() {
    var rng = SeededRandom(seed: 1)
    for _ in 0..<5000 {
        let bytes = (0..<Int.random(in: 0...80, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
        _ = try? GameMessage.decode(bytes)
    }
}

@Test func hugeArrayCountsAreRejected() {
    var w = ByteWriter()
    w.u8(36)          // snapshot
    w.u32(1)          // tick
    w.f64(0)          // time
    w.u32(0)          // ack
    w.u16(60000)      // "players"
    #expect(throws: WireError.badValue("count")) { try GameMessage.decode(w.bytes) }
}

@Test func outOfRangeSettingsAreRejected() {
    for (lives, intensity) in [(0, 1), (10, 1), (3, 7)] as [(UInt8, UInt8)] {
        var w = ByteWriter()
        w.u8(34)      // matchStart
        w.u8(lives)
        w.u8(intensity)
        w.u64(1)
        #expect(throws: (any Error).self) { try GameMessage.decode(w.bytes) }
    }
}

@Test func unknownCombatantsAndSlotsAreRejected() {
    var w = ByteWriter()
    w.u8(36)
    w.u32(1); w.f64(0); w.u32(0)
    for _ in 0..<5 { w.u16(0) }   // no players, tanks, soldiers, shots, mortars
    w.u16(0)                      // no pickups
    w.u16(1)                      // one event…
    w.u8(10)                      // …a kill…
    w.u8(9)                       // …by nobody we know
    w.u8(0)
    #expect(throws: WireError.badValue("combatant")) { try GameMessage.decode(w.bytes) }
}

@Test func playerFlagsAreQueryable() {
    let p = sampleSnapshot().players[1]
    #expect(p.has(PlayerSnapshot.respawning))
    #expect(p.has(PlayerSnapshot.destroyed))
    #expect(!p.has(PlayerSnapshot.invulnerable))
}
```

- [ ] **Step 2: Write the failing sync tests**

Create `Tests/TanksNetTests/NetSyncTests.swift`:

```swift
import Testing
@testable import TanksNet

private func snap(_ tick: UInt32, at time: Double) -> Snapshot {
    Snapshot(tick: tick, time: time, ackInputSeq: 0)
}

@Test func remoteInputKeepsOnlyTheNewestFrame() {
    var input = RemoteInput()
    input.receive(InputFrame(seq: 2, held: InputFrame.forward, presses: 0), at: 1.0)
    input.receive(InputFrame(seq: 1, held: InputFrame.backward, presses: InputFrame.abandon), at: 1.01)
    #expect(input.heldKeys(at: 1.02) == InputFrame.forward)
    #expect(input.lastSeq == 2)
    #expect(input.takePresses() == 0)
}

@Test func remoteInputReleasesKeysWhenTheGuestGoesQuiet() {
    var input = RemoteInput()
    #expect(input.heldKeys(at: 0) == 0)
    input.receive(InputFrame(seq: 1, held: InputFrame.forward | InputFrame.fireMain, presses: 0), at: 10)
    #expect(input.heldKeys(at: 10.25) == InputFrame.forward | InputFrame.fireMain)
    #expect(input.heldKeys(at: 10.26) == 0)
    input.receive(InputFrame(seq: 2, held: InputFrame.left, presses: 0), at: 11)
    #expect(input.heldKeys(at: 11.1) == InputFrame.left)
}

@Test func remotePressesAccumulateUntilTaken() {
    var input = RemoteInput()
    input.receive(InputFrame(seq: 1, held: 0, presses: InputFrame.cycleTarget), at: 0)
    input.receive(InputFrame(seq: 2, held: 0, presses: InputFrame.abandon), at: 0.03)
    #expect(input.takePresses() == InputFrame.cycleTarget | InputFrame.abandon)
    #expect(input.takePresses() == 0)
}

@Test func snapshotBufferDropsStaleAndDuplicateSnapshots() {
    var buffer = SnapshotBuffer()
    #expect(buffer.insert(snap(5, at: 100), receivedAt: 0))
    #expect(!buffer.insert(snap(5, at: 100), receivedAt: 0.01))
    #expect(!buffer.insert(snap(4, at: 99.95), receivedAt: 0.02))
    #expect(buffer.snapshots.map(\.tick) == [5])
    #expect(buffer.latest?.tick == 5)
}

@Test func snapshotBufferRendersADelayBehindTheHostClock() throws {
    var buffer = SnapshotBuffer()
    #expect(buffer.frame(at: 0) == nil)
    for i in 0..<5 {   // host clock runs 100 s ahead of ours
        buffer.insert(snap(UInt32(i + 1), at: 100 + Double(i) * 0.05), receivedAt: Double(i) * 0.05)
    }
    let frame = try #require(buffer.frame(at: 0.175))   // render time 100.075: halfway from tick 2 to tick 3
    #expect(frame.from.tick == 2)
    #expect(frame.to.tick == 3)
    #expect(abs(frame.t - 0.5) < 1e-6)
}

@Test func snapshotBufferHoldsAtTheEndsInsteadOfExtrapolating() throws {
    var buffer = SnapshotBuffer()
    buffer.insert(snap(1, at: 100), receivedAt: 0)
    buffer.insert(snap(2, at: 100.05), receivedAt: 0.05)
    let late = try #require(buffer.frame(at: 5))
    #expect(late.from.tick == 2 && late.to.tick == 2 && late.t == 0)
    let early = try #require(buffer.frame(at: -5))
    #expect(early.from.tick == 1 && early.to.tick == 1 && early.t == 0)
}

@Test func snapshotBufferKeepsABoundedHistory() {
    var buffer = SnapshotBuffer()
    for i in 1...100 { buffer.insert(snap(UInt32(i), at: Double(i) * 0.05), receivedAt: Double(i) * 0.05) }
    #expect(buffer.snapshots.count == SnapshotBuffer.capacity)
    #expect(buffer.snapshots.first?.tick == UInt32(101 - SnapshotBuffer.capacity))
}

@Test func snapshotBufferResynchronisesAfterALongStall() throws {
    var buffer = SnapshotBuffer()
    buffer.insert(snap(1, at: 100), receivedAt: 0)
    buffer.insert(snap(2, at: 200), receivedAt: 0.05)   // host clock jumped 100 s
    let frame = try #require(buffer.frame(at: 0.15))     // render time 200.0 with the new offset
    #expect(frame.to.tick == 2)
}

@Test func inputHistoryForgetsAcknowledgedInputs() {
    var history = InputHistory<String>()
    history.record(seq: 1, input: "a", dt: 0.016)
    history.record(seq: 1, input: "b", dt: 0.016)
    history.record(seq: 2, input: "c", dt: 0.016)
    history.record(seq: 3, input: "d", dt: 0.016)
    history.acknowledge(through: 2)
    #expect(history.entries.map(\.input) == ["d"])
    #expect(history.entries.map(\.seq) == [3])
}

@Test func lerpingPositionsAndAngles() {
    #expect(Vec2(0, 10).lerp(to: Vec2(10, 20), 0.25) == Vec2(2.5, 12.5))
    #expect(abs(lerpAngle(0.1, 0.3, 0.5) - 0.2) < 1e-6)
    // The short way round across ±π.
    let mid = lerpAngle(3.0, -3.0, 0.5)
    #expect(abs(abs(mid) - .pi) < 0.01)
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter TanksNetTests`
Expected: compile errors: `cannot find 'GameMessage' in scope`, `cannot find 'SnapshotBuffer' in scope`, and similar.

- [ ] **Step 4: Implement `GameMessage.swift`**

Create `Sources/TanksNet/GameMessage.swift`:

```swift
import Foundation
import TanksCore

/// Colours a floating text or banner can use.
public enum FXColor: UInt8, CaseIterable, Sendable {
    case white = 0, red, yellow, green, orange
}

/// The game's sound effects. Names match the synthesizer's (`Audio.Sound` is this type).
public enum SoundID: UInt8, CaseIterable, Sendable {
    case cannon = 0, machineGun, explosion, bigExplosion, hit, rocket, pickup, empty
}

/// The guest's keys, sent 30 times a second. `held` is the current key state; `presses` are
/// one-shot keys pressed since the previous frame.
public struct InputFrame: Equatable, Sendable {
    public static let forward: UInt8 = 1 << 0
    public static let backward: UInt8 = 1 << 1
    public static let left: UInt8 = 1 << 2
    public static let right: UInt8 = 1 << 3
    public static let turretLeft: UInt8 = 1 << 4
    public static let turretRight: UInt8 = 1 << 5
    public static let fireMain: UInt8 = 1 << 6
    public static let fireMG: UInt8 = 1 << 7

    public static let cycleTarget: UInt8 = 1 << 0
    public static let manualTurret: UInt8 = 1 << 1
    public static let abandon: UInt8 = 1 << 2

    public var seq: UInt32
    public var held: UInt8
    public var presses: UInt8

    public init(seq: UInt32, held: UInt8, presses: UInt8) {
        self.seq = seq
        self.held = held
        self.presses = presses
    }
}

public struct PlayerSnapshot: Equatable, Sendable {
    public static let destroyed: UInt8 = 1 << 0
    public static let invulnerable: UInt8 = 1 << 1
    public static let respawning: UInt8 = 1 << 2
    public static let inBase: UInt8 = 1 << 3

    public var slot: PlayerSlot
    public var position: Vec2
    public var heading: Float
    public var turret: Float
    public var armor: Float
    public var fuel: Float
    public var shells: UInt16
    public var rounds: UInt16
    public var lives: UInt8
    public var kills: UInt16
    public var flags: UInt8
    public var respawnIn: Float
    /// Net id of the turret's locked target; 0 for none.
    public var lockedTarget: UInt32

    public init(slot: PlayerSlot, position: Vec2, heading: Float, turret: Float, armor: Float, fuel: Float,
                shells: UInt16, rounds: UInt16, lives: UInt8, kills: UInt16, flags: UInt8, respawnIn: Float, lockedTarget: UInt32) {
        self.slot = slot
        self.position = position
        self.heading = heading
        self.turret = turret
        self.armor = armor
        self.fuel = fuel
        self.shells = shells
        self.rounds = rounds
        self.lives = lives
        self.kills = kills
        self.flags = flags
        self.respawnIn = respawnIn
        self.lockedTarget = lockedTarget
    }

    public func has(_ flag: UInt8) -> Bool { flags & flag != 0 }
}

public struct EnemyTankSnapshot: Equatable, Sendable {
    public var id: UInt32
    public var position: Vec2
    public var heading: Float
    public var turret: Float
    /// Armor left, 0...1.
    public var health: Float

    public init(id: UInt32, position: Vec2, heading: Float, turret: Float, health: Float) {
        self.id = id
        self.position = position
        self.heading = heading
        self.turret = turret
        self.health = health
    }
}

/// Only soldiers standing at a window are sent; hidden ones are invisible anyway.
public struct SoldierSnapshot: Equatable, Sendable {
    public var id: UInt32
    public var kind: InfantryKind
    public var position: Vec2
    public var facing: Float

    public init(id: UInt32, kind: InfantryKind, position: Vec2, facing: Float) {
        self.id = id
        self.kind = kind
        self.position = position
        self.facing = facing
    }
}

public struct ShotSnapshot: Equatable, Sendable {
    public var id: UInt32
    public var weapon: WeaponKind
    public var position: Vec2
    public var angle: Float

    public init(id: UInt32, weapon: WeaponKind, position: Vec2, angle: Float) {
        self.id = id
        self.weapon = weapon
        self.position = position
        self.angle = angle
    }
}

public struct MortarSnapshot: Equatable, Sendable {
    public var id: UInt32
    public var start: Vec2
    public var target: Vec2
    /// 0 at launch, 1 on landing.
    public var progress: Float

    public init(id: UInt32, start: Vec2, target: Vec2, progress: Float) {
        self.id = id
        self.start = start
        self.target = target
        self.progress = progress
    }
}

/// One-off happenings the guest must see or hear, batched into the next snapshot.
public enum GameEvent: Equatable, Sendable {
    case explosion(at: Vec2, scale: Float)
    case spark(at: Vec2)
    case dust(at: Vec2)
    case muzzleFlash(at: Vec2, angle: Float, big: Bool)
    case text(String, at: Vec2, color: FXColor)
    case sound(SoundID, at: Vec2, volume: Float)
    case uiSound(SoundID, volume: Float)
    case shake(magnitude: Float, duration: Float)
    case buildingHP(id: UInt16, hp: Int16)
    case kill(killer: Combatant?, victim: PlayerSlot)
    case flash(String, color: FXColor, duration: Float)
    case matchOver(winner: PlayerSlot)
}

/// Everything the guest needs to draw one moment of the host's world.
public struct Snapshot: Equatable, Sendable {
    static let maxPlayers = 2
    static let maxTanks = 64
    static let maxSoldiers = 256
    static let maxShots = 1024
    static let maxMortars = 128
    static let maxPickups = 256
    static let maxEvents = 1024

    public var tick: UInt32
    /// Host clock, seconds.
    public var time: Double
    /// The newest guest input the host had applied when it took this snapshot.
    public var ackInputSeq: UInt32
    public var players: [PlayerSnapshot]
    public var tanks: [EnemyTankSnapshot]
    public var soldiers: [SoldierSnapshot]
    public var shots: [ShotSnapshot]
    public var mortars: [MortarSnapshot]
    /// Indexed like `Level.caches`: true while that pickup is on the ground.
    public var pickups: [Bool]
    public var events: [GameEvent]

    public init(tick: UInt32, time: Double, ackInputSeq: UInt32, players: [PlayerSnapshot] = [], tanks: [EnemyTankSnapshot] = [],
                soldiers: [SoldierSnapshot] = [], shots: [ShotSnapshot] = [], mortars: [MortarSnapshot] = [],
                pickups: [Bool] = [], events: [GameEvent] = []) {
        self.tick = tick
        self.time = time
        self.ackInputSeq = ackInputSeq
        self.players = players
        self.tanks = tanks
        self.soldiers = soldiers
        self.shots = shots
        self.mortars = mortars
        self.pickups = pickups
        self.events = events
    }
}

/// Frames between the two games, forwarded untouched by the relay. Type bytes start at 32.
public enum GameMessage: Equatable, Sendable {
    case lobby(MatchSettings)
    case guestReady(Bool)
    case matchStart(MatchSettings)
    case input(InputFrame)
    case snapshot(Snapshot)
    case ping(Double)
    case pong(Double)
    case leave
    case rematch

    public func encoded() -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case .lobby(let settings):
            w.u8(32)
            w.settings(settings)
        case .guestReady(let ready):
            w.u8(33)
            w.bool(ready)
        case .matchStart(let settings):
            w.u8(34)
            w.settings(settings)
        case .input(let frame):
            w.u8(35)
            w.u32(frame.seq)
            w.u8(frame.held)
            w.u8(frame.presses)
        case .snapshot(let snapshot):
            w.u8(36)
            snapshot.write(to: &w)
        case .ping(let time):
            w.u8(37)
            w.f64(time)
        case .pong(let time):
            w.u8(38)
            w.f64(time)
        case .leave:
            w.u8(39)
        case .rematch:
            w.u8(40)
        }
        return w.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> GameMessage {
        var r = ByteReader(bytes)
        let message: GameMessage
        switch try r.u8() {
        case 32: message = .lobby(try r.settings())
        case 33: message = .guestReady(try r.bool())
        case 34: message = .matchStart(try r.settings())
        case 35: message = .input(InputFrame(seq: try r.u32(), held: try r.u8(), presses: try r.u8()))
        case 36: message = .snapshot(try Snapshot(from: &r))
        case 37: message = .ping(try r.f64())
        case 38: message = .pong(try r.f64())
        case 39: message = .leave
        case 40: message = .rematch
        case let type: throw WireError.badValue("game message type \(type)")
        }
        try r.finish()
        return message
    }
}

// MARK: - Encoding details

extension ByteWriter {
    mutating func slot(_ slot: PlayerSlot) { u8(UInt8(slot.rawValue)) }

    mutating func caseIndex<E: CaseIterable & Equatable>(_ value: E) {
        u8(UInt8(Array(E.allCases).firstIndex(of: value)!))
    }

    mutating func settings(_ s: MatchSettings) {
        u8(UInt8(s.lives))
        u8(UInt8(s.aiIntensity.rawValue))
        u64(s.seed)
    }

    /// 0 none, 1 host, 2 guest, 3 AI tank, 16 + kind for infantry.
    mutating func combatant(_ c: Combatant?) {
        switch c {
        case nil: u8(0)
        case .player(let slot)?: u8(1 + UInt8(slot.rawValue))
        case .enemyTank?: u8(3)
        case .infantry(let kind)?: u8(16 + UInt8(Array(InfantryKind.allCases).firstIndex(of: kind)!))
        }
    }

    mutating func array<T>(_ items: [T], _ write: (T, inout ByteWriter) -> Void) {
        u16(UInt16(items.count))
        for item in items { write(item, &self) }
    }

    mutating func bits(_ flags: [Bool]) {
        u16(UInt16(flags.count))
        var byte: UInt8 = 0
        for (index, flag) in flags.enumerated() {
            if flag { byte |= 1 << UInt8(index % 8) }
            if index % 8 == 7 {
                u8(byte)
                byte = 0
            }
        }
        if flags.count % 8 != 0 { u8(byte) }
    }
}

extension ByteReader {
    mutating func slot() throws -> PlayerSlot {
        guard let slot = PlayerSlot(rawValue: Int(try u8())) else { throw WireError.badValue("player slot") }
        return slot
    }

    mutating func caseIndex<E: CaseIterable>(_ type: E.Type) throws -> E {
        let all = Array(E.allCases)
        let index = Int(try u8())
        guard index < all.count else { throw WireError.badValue("\(E.self)") }
        return all[index]
    }

    mutating func settings() throws -> MatchSettings {
        let lives = Int(try u8())
        guard MatchSettings.livesRange.contains(lives) else { throw WireError.badValue("lives") }
        guard let intensity = AIIntensity(rawValue: Int(try u8())) else { throw WireError.badValue("ai intensity") }
        return MatchSettings(lives: lives, aiIntensity: intensity, seed: try u64())
    }

    mutating func combatant() throws -> Combatant? {
        let code = Int(try u8())
        let kinds = Array(InfantryKind.allCases)
        switch code {
        case 0: return nil
        case 1, 2: return .player(PlayerSlot(rawValue: code - 1)!)
        case 3: return .enemyTank
        case 16..<(16 + kinds.count): return .infantry(kinds[code - 16])
        default: throw WireError.badValue("combatant")
        }
    }

    mutating func array<T>(max: Int, _ read: (inout ByteReader) throws -> T) throws -> [T] {
        let n = try count(max: max)
        var items: [T] = []
        items.reserveCapacity(n)
        for _ in 0..<n { items.append(try read(&self)) }
        return items
    }

    mutating func bits(max: Int) throws -> [Bool] {
        let n = try count(max: max)
        var flags: [Bool] = []
        var byte: UInt8 = 0
        for index in 0..<n {
            if index % 8 == 0 { byte = try u8() }
            flags.append(byte & (1 << UInt8(index % 8)) != 0)
        }
        return flags
    }
}

extension Snapshot {
    func write(to w: inout ByteWriter) {
        w.u32(tick)
        w.f64(time)
        w.u32(ackInputSeq)
        w.array(players) { p, w in
            w.slot(p.slot); w.vec(p.position); w.f32(p.heading); w.f32(p.turret); w.f32(p.armor); w.f32(p.fuel)
            w.u16(p.shells); w.u16(p.rounds); w.u8(p.lives); w.u16(p.kills); w.u8(p.flags); w.f32(p.respawnIn); w.u32(p.lockedTarget)
        }
        w.array(tanks) { t, w in
            w.u32(t.id); w.vec(t.position); w.f32(t.heading); w.f32(t.turret); w.f32(t.health)
        }
        w.array(soldiers) { s, w in
            w.u32(s.id); w.caseIndex(s.kind); w.vec(s.position); w.f32(s.facing)
        }
        w.array(shots) { s, w in
            w.u32(s.id); w.caseIndex(s.weapon); w.vec(s.position); w.f32(s.angle)
        }
        w.array(mortars) { m, w in
            w.u32(m.id); w.vec(m.start); w.vec(m.target); w.f32(m.progress)
        }
        w.bits(pickups)
        w.array(events) { e, w in e.write(to: &w) }
    }

    init(from r: inout ByteReader) throws {
        self.init(
            tick: try r.u32(), time: try r.f64(), ackInputSeq: try r.u32(),
            players: try r.array(max: Self.maxPlayers) { r in
                PlayerSnapshot(slot: try r.slot(), position: try r.vec(), heading: try r.f32(), turret: try r.f32(),
                               armor: try r.f32(), fuel: try r.f32(), shells: try r.u16(), rounds: try r.u16(),
                               lives: try r.u8(), kills: try r.u16(), flags: try r.u8(), respawnIn: try r.f32(),
                               lockedTarget: try r.u32())
            },
            tanks: try r.array(max: Self.maxTanks) { r in
                EnemyTankSnapshot(id: try r.u32(), position: try r.vec(), heading: try r.f32(), turret: try r.f32(), health: try r.f32())
            },
            soldiers: try r.array(max: Self.maxSoldiers) { r in
                SoldierSnapshot(id: try r.u32(), kind: try r.caseIndex(InfantryKind.self), position: try r.vec(), facing: try r.f32())
            },
            shots: try r.array(max: Self.maxShots) { r in
                ShotSnapshot(id: try r.u32(), weapon: try r.caseIndex(WeaponKind.self), position: try r.vec(), angle: try r.f32())
            },
            mortars: try r.array(max: Self.maxMortars) { r in
                MortarSnapshot(id: try r.u32(), start: try r.vec(), target: try r.vec(), progress: try r.f32())
            },
            pickups: try r.bits(max: Self.maxPickups),
            events: try r.array(max: Self.maxEvents) { r in try GameEvent(from: &r) })
    }
}

extension GameEvent {
    func write(to w: inout ByteWriter) {
        switch self {
        case let .explosion(at, scale):
            w.u8(1); w.vec(at); w.f32(scale)
        case let .spark(at):
            w.u8(2); w.vec(at)
        case let .dust(at):
            w.u8(3); w.vec(at)
        case let .muzzleFlash(at, angle, big):
            w.u8(4); w.vec(at); w.f32(angle); w.bool(big)
        case let .text(text, at, color):
            w.u8(5); w.string(text); w.vec(at); w.u8(color.rawValue)
        case let .sound(sound, at, volume):
            w.u8(6); w.u8(sound.rawValue); w.vec(at); w.f32(volume)
        case let .uiSound(sound, volume):
            w.u8(7); w.u8(sound.rawValue); w.f32(volume)
        case let .shake(magnitude, duration):
            w.u8(8); w.f32(magnitude); w.f32(duration)
        case let .buildingHP(id, hp):
            w.u8(9); w.u16(id); w.i16(hp)
        case let .kill(killer, victim):
            w.u8(10); w.combatant(killer); w.slot(victim)
        case let .flash(text, color, duration):
            w.u8(11); w.string(text); w.u8(color.rawValue); w.f32(duration)
        case let .matchOver(winner):
            w.u8(12); w.slot(winner)
        }
    }

    init(from r: inout ByteReader) throws {
        switch try r.u8() {
        case 1: self = .explosion(at: try r.vec(), scale: try r.f32())
        case 2: self = .spark(at: try r.vec())
        case 3: self = .dust(at: try r.vec())
        case 4: self = .muzzleFlash(at: try r.vec(), angle: try r.f32(), big: try r.bool())
        case 5: self = .text(try r.string(), at: try r.vec(), color: try r.raw(FXColor.self))
        case 6: self = .sound(try r.raw(SoundID.self), at: try r.vec(), volume: try r.f32())
        case 7: self = .uiSound(try r.raw(SoundID.self), volume: try r.f32())
        case 8: self = .shake(magnitude: try r.f32(), duration: try r.f32())
        case 9: self = .buildingHP(id: try r.u16(), hp: try r.i16())
        case 10: self = .kill(killer: try r.combatant(), victim: try r.slot())
        case 11: self = .flash(try r.string(), color: try r.raw(FXColor.self), duration: try r.f32())
        case 12: self = .matchOver(winner: try r.slot())
        case let type: throw WireError.badValue("event type \(type)")
        }
    }
}
```

- [ ] **Step 5: Implement `NetSync.swift`**

Create `Sources/TanksNet/NetSync.swift`:

```swift
import Foundation

/// The host's view of the guest's keys: the newest frame wins, one-shot presses pile up until
/// they're used, and held keys count as released once the guest has been quiet for a moment.
public struct RemoteInput: Sendable {
    public static let staleAfter = 0.25

    public private(set) var lastSeq: UInt32 = 0
    private var held: UInt8 = 0
    private var presses: UInt8 = 0
    private var lastHeard: Double?

    public init() {}

    public mutating func receive(_ frame: InputFrame, at time: Double) {
        guard frame.seq > lastSeq else { return }
        lastSeq = frame.seq
        held = frame.held
        presses |= frame.presses
        lastHeard = time
    }

    /// The guest's held keys at `time`, or none if they've gone quiet (so their tank stops).
    public func heldKeys(at time: Double) -> UInt8 {
        guard let lastHeard, time - lastHeard <= Self.staleAfter else { return 0 }
        return held
    }

    public mutating func takePresses() -> UInt8 {
        defer { presses = 0 }
        return presses
    }
}

/// Guest side: recent snapshots plus a render clock that trails the host's by `delay`,
/// so there are always two snapshots to interpolate between.
public struct SnapshotBuffer: Sendable {
    public static let delay = 0.1
    public static let capacity = 30

    public struct Frame: Sendable {
        public let from: Snapshot
        public let to: Snapshot
        /// 0 at `from`, 1 at `to`.
        public let t: Double
    }

    public private(set) var snapshots: [Snapshot] = []
    /// Host clock minus local clock, smoothed.
    private var clockOffset: Double?

    public init() {}

    public var latest: Snapshot? { snapshots.last }

    /// Keeps `snapshot` unless it's no newer than one already held. Returns whether it was kept.
    @discardableResult
    public mutating func insert(_ snapshot: Snapshot, receivedAt localTime: Double) -> Bool {
        if let last = snapshots.last, snapshot.tick <= last.tick { return false }
        let sample = snapshot.time - localTime
        if let offset = clockOffset, abs(sample - offset) < 1 {
            clockOffset = offset + (sample - offset) * 0.1
        } else {
            clockOffset = sample   // first snapshot, or the clocks jumped (long stall): resync
        }
        snapshots.append(snapshot)
        if snapshots.count > Self.capacity { snapshots.removeFirst(snapshots.count - Self.capacity) }
        return true
    }

    /// The snapshots either side of the render time. Holds at the oldest/newest rather than guessing beyond them.
    public func frame(at localTime: Double) -> Frame? {
        guard let offset = clockOffset, let first = snapshots.first, let last = snapshots.last else { return nil }
        let renderTime = localTime + offset - Self.delay
        if renderTime <= first.time { return Frame(from: first, to: first, t: 0) }
        if renderTime >= last.time { return Frame(from: last, to: last, t: 0) }
        let index = snapshots.lastIndex { $0.time <= renderTime }!
        let a = snapshots[index]
        let b = snapshots[index + 1]
        let span = b.time - a.time
        return Frame(from: a, to: b, t: span > 0 ? (renderTime - a.time) / span : 1)
    }
}

/// Guest side: inputs applied locally that the host hasn't confirmed yet, replayed after each snapshot.
public struct InputHistory<Input> {
    public struct Entry {
        public let seq: UInt32
        public let input: Input
        public let dt: Double
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public mutating func record(seq: UInt32, input: Input, dt: Double) {
        entries.append(Entry(seq: seq, input: input, dt: dt))
        if entries.count > 600 { entries.removeFirst(entries.count - 600) }   // ~10 s at 60 fps
    }

    public mutating func acknowledge(through seq: UInt32) {
        entries.removeAll { $0.seq <= seq }
    }
}

extension Vec2 {
    public func lerp(to other: Vec2, _ t: Double) -> Vec2 {
        Vec2(x + (other.x - x) * Float(t), y + (other.y - y) * Float(t))
    }
}

/// Interpolates between two angles the short way round.
public func lerpAngle(_ a: Float, _ b: Float, _ t: Double) -> Float {
    var delta = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
    if delta > .pi { delta -= 2 * .pi }
    if delta < -.pi { delta += 2 * .pi }
    return a + delta * Float(t)
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter TanksNetTests`
Expected: all TanksNet tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/TanksNet Tests/TanksNetTests
git commit -m "feat(net): game messages, snapshots, events and interpolation/prediction helpers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
## Phase D: The relay server

### Task 9: Relay logic: rooms, pairing, forwarding and limits as plain values

**Files:**
- Modify: `Package.swift` (adds swift-nio, `TanksRelayCore`, `TanksRelayCoreTests`)
- Create: `Package.resolved` (generated), `Sources/TanksRelayCore/RoomRegistry.swift`, `Sources/TanksRelayCore/RelayCore.swift`
- Test: `Tests/TanksRelayCoreTests/RoomRegistryTests.swift`, `Tests/TanksRelayCoreTests/RelayCoreTests.swift` (new)

**Interfaces:**
- Consumes: `TanksNet.randomRoomCode(using:)`, `normalizeRoomCode(_:)`, `protocolVersion`, `RelayMessage`, `RelayErrorCode` (Task 7).
- Produces:
  - `public struct RoomRegistry<Connection: Hashable> { init(maxRooms: Int = 500); roomCount; create(host:now:using:) -> Result<String, RelayErrorCode>; join(code:guest:) -> Result<Connection, RelayErrorCode>; peer(of:) -> Connection?; remove(_:) -> Connection?; expireUnpaired(now:ttl:) -> [Connection] }`
  - `public enum RelayLimits { maxFrameBytes = 65536, framesPerSecond = 100.0, maxRooms = 500, defaultRoomTTL = 600.0 }`
  - `public struct FrameRateLimiter { init(perSecond:); mutating allow(now:) -> Bool }`
  - `public enum RelayAction<Connection: Hashable>: Equatable { case send([UInt8], to: Connection), close(Connection) }`
  - `public struct RelayCore<Connection: Hashable> { init(maxRooms:framesPerSecond:); roomCount; received(_:from:now:using:) -> [RelayAction]; disconnected(_:) -> [RelayAction]; expire(now:ttl:) -> [RelayAction] }`

- [ ] **Step 1: Add the package targets and resolve SwiftNIO**

Replace `Package.swift` with:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TanksOfDoom",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Used only by the relay server; the game itself has no third-party dependencies.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(name: "TanksCore"),
        .target(name: "TanksNet", dependencies: ["TanksCore"]),
        .executableTarget(name: "TanksOfDoom", dependencies: ["TanksCore", "TanksNet"]),
        .target(name: "TanksRelayCore", dependencies: [
            "TanksNet",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOWebSocket", package: "swift-nio"),
        ]),
        .testTarget(name: "TanksCoreTests", dependencies: ["TanksCore"]),
        .testTarget(name: "TanksNetTests", dependencies: ["TanksNet", "TanksCore"]),
        .testTarget(name: "TanksRelayCoreTests", dependencies: ["TanksRelayCore", "TanksNet", "TanksCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

(The `TanksRelay` executable target arrives in Task 10, together with the server it runs.)

Run: `swift package resolve`
Expected: SwiftPM fetches swift-nio and writes `Package.resolved`.

- [ ] **Step 2: Write the failing tests**

Create `Tests/TanksRelayCoreTests/RoomRegistryTests.swift`:

```swift
import Testing
import TanksCore
import TanksNet
@testable import TanksRelayCore

@Test func hostsGetAFreshValidCode() throws {
    var rooms = RoomRegistry<Int>()
    var rng = SeededRandom(seed: 1)
    let code = try rooms.create(host: 1, now: 0, using: &rng).get()
    #expect(TanksNet.normalizeRoomCode(code) == code)
    #expect(rooms.roomCount == 1)
    #expect(rooms.peer(of: 1) == nil)
}

@Test func aGuestPairsWithTheHostCaseInsensitively() throws {
    var rooms = RoomRegistry<Int>()
    var rng = SeededRandom(seed: 2)
    let code = try rooms.create(host: 1, now: 0, using: &rng).get()
    #expect(try rooms.join(code: code.lowercased(), guest: 2).get() == 1)
    #expect(rooms.peer(of: 1) == 2)
    #expect(rooms.peer(of: 2) == 1)
}

@Test func joiningFailsForUnknownOrFullRooms() throws {
    var rooms = RoomRegistry<Int>()
    var rng = SeededRandom(seed: 3)
    let code = try rooms.create(host: 1, now: 0, using: &rng).get()
    #expect(rooms.join(code: "ZZZZZ", guest: 2) == .failure(.roomNotFound))
    #expect(rooms.join(code: "nonsense!", guest: 2) == .failure(.roomNotFound))
    _ = rooms.join(code: code, guest: 2)
    #expect(rooms.join(code: code, guest: 3) == .failure(.roomFull))
}

@Test func aConnectionCanBeInOnlyOneRoom() throws {
    var rooms = RoomRegistry<Int>()
    var rng = SeededRandom(seed: 4)
    let code = try rooms.create(host: 1, now: 0, using: &rng).get()
    #expect(rooms.create(host: 1, now: 0, using: &rng) == .failure(.protocolError))
    #expect(rooms.join(code: code, guest: 1) == .failure(.protocolError))
}

@Test func theServerHasARoomLimit() {
    var rooms = RoomRegistry<Int>(maxRooms: 1)
    var rng = SeededRandom(seed: 5)
    _ = rooms.create(host: 1, now: 0, using: &rng)
    #expect(rooms.create(host: 2, now: 0, using: &rng) == .failure(.serverFull))
}

@Test func removingEitherMemberClosesTheRoomAndNamesThePeer() throws {
    var rooms = RoomRegistry<Int>()
    var rng = SeededRandom(seed: 6)
    let code = try rooms.create(host: 1, now: 0, using: &rng).get()
    _ = rooms.join(code: code, guest: 2)
    #expect(rooms.remove(2) == 1)
    #expect(rooms.roomCount == 0)
    #expect(rooms.peer(of: 1) == nil)
    #expect(rooms.remove(1) == nil)
}

@Test func unpairedRoomsExpire() throws {
    var rooms = RoomRegistry<Int>()
    var rng = SeededRandom(seed: 7)
    _ = try rooms.create(host: 1, now: 0, using: &rng).get()
    let paired = try rooms.create(host: 2, now: 0, using: &rng).get()
    _ = rooms.join(code: paired, guest: 3)
    #expect(rooms.expireUnpaired(now: 599, ttl: 600).isEmpty)
    #expect(rooms.expireUnpaired(now: 601, ttl: 600) == [1])
    #expect(rooms.roomCount == 1)
}
```

Create `Tests/TanksRelayCoreTests/RelayCoreTests.swift`:

```swift
import Testing
import TanksCore
import TanksNet
@testable import TanksRelayCore

private let hello = RelayMessage.hello(version: TanksNet.protocolVersion).encoded()

private func error(_ code: RelayErrorCode) -> [UInt8] { RelayMessage.error(code).encoded() }

/// A relay with a host (1) and guest (2) already paired; returns the room code too.
private func pairedRelay() -> (RelayCore<Int>, String) {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 1)
    _ = relay.received(hello, from: 1, now: 0, using: &rng)
    let created = relay.received(RelayMessage.createRoom.encoded(), from: 1, now: 0, using: &rng)
    guard case .send(let bytes, to: 1) = created.first, case .roomCreated(let code) = try? RelayMessage.decode(bytes) else {
        fatalError("expected roomCreated, got \(created)")
    }
    _ = relay.received(hello, from: 2, now: 0, using: &rng)
    _ = relay.received(RelayMessage.joinRoom(code: code).encoded(), from: 2, now: 0, using: &rng)
    return (relay, code)
}

@Test func helloMustComeFirst() {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 1)
    #expect(relay.received(RelayMessage.createRoom.encoded(), from: 1, now: 0, using: &rng)
        == [.send(error(.protocolError), to: 1), .close(1)])
}

@Test func mismatchedVersionsAreTurnedAway() {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 1)
    let oldHello = RelayMessage.hello(version: TanksNet.protocolVersion + 1).encoded()
    #expect(relay.received(oldHello, from: 1, now: 0, using: &rng) == [.send(error(.versionMismatch), to: 1), .close(1)])
}

@Test func joiningTellsBothSides() {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 2)
    _ = relay.received(hello, from: 1, now: 0, using: &rng)
    let created = relay.received(RelayMessage.createRoom.encoded(), from: 1, now: 0, using: &rng)
    guard case .send(let bytes, to: 1) = created.first, case .roomCreated(let code) = try? RelayMessage.decode(bytes) else {
        Issue.record("expected roomCreated, got \(created)")
        return
    }
    _ = relay.received(hello, from: 2, now: 0, using: &rng)
    let joined = RelayMessage.joined.encoded()
    #expect(relay.received(RelayMessage.joinRoom(code: code.lowercased()).encoded(), from: 2, now: 0, using: &rng)
        == [.send(joined, to: 1), .send(joined, to: 2)])
}

@Test func pairedPlayersExchangeGameFramesBothWays() {
    var (relay, _) = pairedRelay()
    var rng = SeededRandom(seed: 3)
    let frame: [UInt8] = [36, 1, 2, 3]
    #expect(relay.received(frame, from: 2, now: 1, using: &rng) == [.send(frame, to: 1)])
    #expect(relay.received(frame, from: 1, now: 1, using: &rng) == [.send(frame, to: 2)])
}

@Test func wrongCodesAndFullRoomsAreReportedWithoutHangingUp() {
    var (relay, code) = pairedRelay()
    var rng = SeededRandom(seed: 4)
    _ = relay.received(hello, from: 3, now: 0, using: &rng)
    #expect(relay.received(RelayMessage.joinRoom(code: "ZZZZZ").encoded(), from: 3, now: 0, using: &rng)
        == [.send(error(.roomNotFound), to: 3)])
    #expect(relay.received(RelayMessage.joinRoom(code: code).encoded(), from: 3, now: 0, using: &rng)
        == [.send(error(.roomFull), to: 3)])
}

@Test func whenOneSideLeavesTheOtherHearsAboutIt() {
    var (relay, _) = pairedRelay()
    var rng = SeededRandom(seed: 5)
    #expect(relay.disconnected(1) == [.send(RelayMessage.peerLeft.encoded(), to: 2)])
    #expect(relay.roomCount == 0)
    #expect(relay.received([36, 9], from: 2, now: 1, using: &rng).isEmpty)   // nobody left to forward to
    #expect(relay.disconnected(2).isEmpty)
}

@Test func gameFramesBeforePairingGoNowhere() {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 6)
    _ = relay.received(hello, from: 1, now: 0, using: &rng)
    #expect(relay.received([36, 1], from: 1, now: 0, using: &rng).isEmpty)
}

@Test func garbageAndRepliesFromClientsAreProtocolErrors() {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 7)
    _ = relay.received(hello, from: 1, now: 0, using: &rng)
    #expect(relay.received([9, 9, 9], from: 1, now: 0, using: &rng) == [.send(error(.protocolError), to: 1), .close(1)])
    _ = relay.received(hello, from: 2, now: 0, using: &rng)
    #expect(relay.received(RelayMessage.joined.encoded(), from: 2, now: 0, using: &rng) == [.send(error(.protocolError), to: 2), .close(2)])
}

@Test func floodingAndOversizeFramesGetTheSenderDisconnected() {
    var (relay, _) = pairedRelay()
    var rng = SeededRandom(seed: 8)
    var last: [RelayAction<Int>] = []
    for _ in 0...Int(RelayLimits.framesPerSecond) {
        last = relay.received([36], from: 2, now: 5, using: &rng)
    }
    #expect(last == [.close(2)])
    let huge = [UInt8](repeating: 36, count: RelayLimits.maxFrameBytes + 1)
    #expect(relay.received(huge, from: 1, now: 5, using: &rng) == [.close(1)])
}

@Test func rateLimitRefillsOverTime() {
    var limiter = FrameRateLimiter(perSecond: 2)
    #expect(limiter.allow(now: 0))
    #expect(limiter.allow(now: 0))
    #expect(!limiter.allow(now: 0))
    #expect(limiter.allow(now: 0.5))
}

@Test func lonelyHostsAreDisconnectedAfterTheTTL() {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 9)
    _ = relay.received(hello, from: 1, now: 0, using: &rng)
    _ = relay.received(RelayMessage.createRoom.encoded(), from: 1, now: 0, using: &rng)
    #expect(relay.expire(now: 100, ttl: 600).isEmpty)
    #expect(relay.expire(now: 700, ttl: 600) == [.close(1)])
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter TanksRelayCoreTests 2>&1 | grep -E "error:" | head -5`
Expected: compile errors: `cannot find 'RoomRegistry' in scope` and similar.

- [ ] **Step 4: Implement `RoomRegistry.swift`**

Create `Sources/TanksRelayCore/RoomRegistry.swift`:

```swift
import Foundation
import TanksNet

/// Rooms keyed by code: a host waiting alone, or a host and a guest paired up.
public struct RoomRegistry<Connection: Hashable> {
    struct Room {
        var host: Connection
        var guest: Connection?
        let createdAt: Double
    }

    public let maxRooms: Int
    private var rooms: [String: Room] = [:]
    private var roomOf: [Connection: String] = [:]

    public init(maxRooms: Int = RelayLimits.maxRooms) {
        self.maxRooms = maxRooms
    }

    public var roomCount: Int { rooms.count }

    public mutating func create(host: Connection, now: Double, using rng: inout some RandomNumberGenerator) -> Result<String, RelayErrorCode> {
        guard roomOf[host] == nil else { return .failure(.protocolError) }
        guard rooms.count < maxRooms else { return .failure(.serverFull) }
        var code = TanksNet.randomRoomCode(using: &rng)
        while rooms[code] != nil { code = TanksNet.randomRoomCode(using: &rng) }
        rooms[code] = Room(host: host, guest: nil, createdAt: now)
        roomOf[host] = code
        return .success(code)
    }

    /// Pairs `guest` with the room's host; returns the host.
    public mutating func join(code input: String, guest: Connection) -> Result<Connection, RelayErrorCode> {
        guard roomOf[guest] == nil else { return .failure(.protocolError) }
        guard let code = TanksNet.normalizeRoomCode(input), var room = rooms[code] else { return .failure(.roomNotFound) }
        guard room.guest == nil else { return .failure(.roomFull) }
        room.guest = guest
        rooms[code] = room
        roomOf[guest] = code
        return .success(room.host)
    }

    /// The other member of a paired room.
    public func peer(of connection: Connection) -> Connection? {
        guard let code = roomOf[connection], let room = rooms[code], let guest = room.guest else { return nil }
        return connection == room.host ? guest : room.host
    }

    /// Closes the connection's room; returns the other member, who should be told.
    @discardableResult
    public mutating func remove(_ connection: Connection) -> Connection? {
        guard let code = roomOf[connection], let room = rooms.removeValue(forKey: code) else { return nil }
        roomOf[room.host] = nil
        if let guest = room.guest { roomOf[guest] = nil }
        return connection == room.host ? room.guest : room.host
    }

    /// Removes rooms that waited longer than `ttl` without a guest; returns their hosts.
    public mutating func expireUnpaired(now: Double, ttl: Double) -> [Connection] {
        let stale = rooms.filter { $0.value.guest == nil && now - $0.value.createdAt > ttl }
        for (code, room) in stale {
            rooms[code] = nil
            roomOf[room.host] = nil
        }
        return stale.map { $0.value.host }
    }
}
```

- [ ] **Step 5: Implement `RelayCore.swift`**

Create `Sources/TanksRelayCore/RelayCore.swift`:

```swift
import Foundation
import TanksNet

public enum RelayLimits {
    public static let maxFrameBytes = 1 << 16
    public static let framesPerSecond = 100.0
    public static let maxRooms = 500
    public static let defaultRoomTTL = 600.0
}

/// Token bucket: `perSecond` frames a second, with up to a second's worth saved up.
public struct FrameRateLimiter: Sendable {
    public let perSecond: Double
    private var tokens: Double
    private var last: Double?

    public init(perSecond: Double) {
        self.perSecond = perSecond
        tokens = perSecond
    }

    public mutating func allow(now: Double) -> Bool {
        if let last { tokens = min(perSecond, tokens + (now - last) * perSecond) }
        last = now
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}

/// What the server should do about something that happened.
public enum RelayAction<Connection: Hashable>: Equatable {
    case send([UInt8], to: Connection)
    case close(Connection)
}

/// Every relay decision, with no sockets involved, so it can be tested directly.
public struct RelayCore<Connection: Hashable> {
    private var registry: RoomRegistry<Connection>
    private var greeted: Set<Connection> = []
    private var limiters: [Connection: FrameRateLimiter] = [:]
    private let framesPerSecond: Double

    public init(maxRooms: Int = RelayLimits.maxRooms, framesPerSecond: Double = RelayLimits.framesPerSecond) {
        registry = RoomRegistry(maxRooms: maxRooms)
        self.framesPerSecond = framesPerSecond
    }

    public var roomCount: Int { registry.roomCount }

    public mutating func received(_ bytes: [UInt8], from connection: Connection, now: Double,
                                  using rng: inout some RandomNumberGenerator) -> [RelayAction<Connection>] {
        var limiter = limiters[connection] ?? FrameRateLimiter(perSecond: framesPerSecond)
        let allowed = limiter.allow(now: now)
        limiters[connection] = limiter
        guard allowed, bytes.count <= RelayLimits.maxFrameBytes else { return [.close(connection)] }

        if let peer = registry.peer(of: connection) { return [.send(bytes, to: peer)] }
        guard RelayMessage.isControlFrame(bytes) else { return [] }   // game frames before pairing go nowhere
        guard let message = try? RelayMessage.decode(bytes) else { return reject(connection, .protocolError) }

        switch message {
        case .hello(let version):
            guard version == TanksNet.protocolVersion else { return reject(connection, .versionMismatch) }
            greeted.insert(connection)
            return []
        case .createRoom:
            guard greeted.contains(connection) else { return reject(connection, .protocolError) }
            switch registry.create(host: connection, now: now, using: &rng) {
            case .success(let code): return [.send(RelayMessage.roomCreated(code: code).encoded(), to: connection)]
            case .failure(let error): return [.send(RelayMessage.error(error).encoded(), to: connection)]
            }
        case .joinRoom(let code):
            guard greeted.contains(connection) else { return reject(connection, .protocolError) }
            switch registry.join(code: code, guest: connection) {
            case .success(let host):
                let joined = RelayMessage.joined.encoded()
                return [.send(joined, to: host), .send(joined, to: connection)]
            case .failure(let error):
                return [.send(RelayMessage.error(error).encoded(), to: connection)]
            }
        case .roomCreated, .joined, .error, .peerLeft:
            return reject(connection, .protocolError)   // only the relay sends these
        }
    }

    public mutating func disconnected(_ connection: Connection) -> [RelayAction<Connection>] {
        greeted.remove(connection)
        limiters[connection] = nil
        guard let peer = registry.remove(connection) else { return [] }
        return [.send(RelayMessage.peerLeft.encoded(), to: peer)]
    }

    public mutating func expire(now: Double, ttl: Double) -> [RelayAction<Connection>] {
        registry.expireUnpaired(now: now, ttl: ttl).map { .close($0) }
    }

    private func reject(_ connection: Connection, _ code: RelayErrorCode) -> [RelayAction<Connection>] {
        [.send(RelayMessage.error(code).encoded(), to: connection), .close(connection)]
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test 2>&1 | tail -3`
Expected: every test target passes, including all `RoomRegistryTests` and `RelayCoreTests`.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Package.resolved Sources/TanksRelayCore Tests/TanksRelayCoreTests
git commit -m "feat(relay): room registry and relay decisions with rate and size limits

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: The WebSocket server, its executable, Docker image and docs

**Files:**
- Modify: `Package.swift` (adds the `TanksRelay` executable target)
- Create: `Sources/TanksRelayCore/RelayServer.swift`, `Sources/TanksRelay/main.swift`, `Dockerfile`, `.dockerignore`, `docs/relay.md`
- Test: `Tests/TanksRelayCoreTests/RelayServerTests.swift` (new)

**Interfaces:**
- Consumes: `RelayCore`, `RelayAction`, `RelayLimits` (Task 9).
- Produces:
  - `public final class RelayServer { init(roomTTL: Double = RelayLimits.defaultRoomTTL); start(host:port:) throws -> Int; waitUntilClosed() throws; shutdown() async throws }`
  - WebSocket endpoint path `/ws`
  - Docker image running `TanksRelay` on `$PORT`

- [ ] **Step 1: Write the failing end-to-end test**

Create `Tests/TanksRelayCoreTests/RelayServerTests.swift`:

```swift
import Foundation
import Testing
import TanksNet
@testable import TanksRelayCore

/// A real WebSocket client, like the game's.
private final class Client {
    let task: URLSessionWebSocketTask

    init(port: Int) {
        task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
        task.resume()
    }

    func send(_ bytes: [UInt8]) async throws {
        try await task.send(.data(Data(bytes)))
    }

    func receive() async throws -> [UInt8] {
        switch try await task.receive() {
        case .data(let data): return [UInt8](data)
        case .string(let text): Issue.record("unexpected text frame \(text)"); return []
        @unknown default: return []
        }
    }

    func relayMessage() async throws -> RelayMessage {
        try RelayMessage.decode(try await receive())
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

@Test func twoClientsPairUpAndTalkThroughTheRelay() async throws {
    let server = RelayServer()
    let port = try server.start(host: "127.0.0.1", port: 0)
    let host = Client(port: port)
    let guest = Client(port: port)
    let hello = RelayMessage.hello(version: TanksNet.protocolVersion).encoded()

    try await host.send(hello)
    try await host.send(RelayMessage.createRoom.encoded())
    guard case .roomCreated(let code) = try await host.relayMessage() else {
        Issue.record("host got no room code")
        return
    }

    try await guest.send(hello)
    try await guest.send(RelayMessage.joinRoom(code: code.lowercased()).encoded())
    #expect(try await guest.relayMessage() == .joined)
    #expect(try await host.relayMessage() == .joined)

    let ping = GameMessage.ping(1.5).encoded()
    try await guest.send(ping)
    #expect(try await host.receive() == ping)
    let pong = GameMessage.pong(1.5).encoded()
    try await host.send(pong)
    #expect(try await guest.receive() == pong)

    host.close()
    #expect(try await guest.relayMessage() == .peerLeft)
    guest.close()
    try await server.shutdown()
}

@Test func outdatedGamesAreTurnedAway() async throws {
    let server = RelayServer()
    let port = try server.start(host: "127.0.0.1", port: 0)
    let client = Client(port: port)
    try await client.send(RelayMessage.hello(version: TanksNet.protocolVersion + 1).encoded())
    #expect(try await client.relayMessage() == .error(.versionMismatch))
    client.close()
    try await server.shutdown()
}

@Test func unknownRoomCodesAreReported() async throws {
    let server = RelayServer()
    let port = try server.start(host: "127.0.0.1", port: 0)
    let client = Client(port: port)
    try await client.send(RelayMessage.hello(version: TanksNet.protocolVersion).encoded())
    try await client.send(RelayMessage.joinRoom(code: "ZZZZZ").encoded())
    #expect(try await client.relayMessage() == .error(.roomNotFound))
    client.close()
    try await server.shutdown()
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RelayServerTests 2>&1 | grep error: | head -3`
Expected: `cannot find 'RelayServer' in scope`.

- [ ] **Step 3: Implement `RelayServer.swift`**

Create `Sources/TanksRelayCore/RelayServer.swift`:

```swift
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import TanksNet

/// The relay's WebSocket server: accepts game connections on `/ws` and lets `RelayCore` decide what
/// happens to every frame. It runs on a single event loop, so its state needs no locks.
public final class RelayServer: @unchecked Sendable {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let roomTTL: Double
    private var core = RelayCore<ObjectIdentifier>()
    private var channels: [ObjectIdentifier: Channel] = [:]
    private var rng = SystemRandomNumberGenerator()
    private var serverChannel: Channel?

    public init(roomTTL: Double = RelayLimits.defaultRoomTTL) {
        self.roomTTL = roomTTL
    }

    /// Starts listening; returns the bound port (handy with port 0 in tests).
    public func start(host: String, port: Int) throws -> Int {
        let upgrader = NIOWebSocketServerUpgrader(
            maxFrameSize: RelayLimits.maxFrameBytes,
            shouldUpgrade: { channel, head in
                channel.eventLoop.makeSucceededFuture(head.uri == "/ws" ? HTTPHeaders() : nil)
            },
            upgradePipelineHandler: { channel, _ in
                channel.pipeline.addHandler(RelayFrameHandler(server: self))
            })
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in }))
            }
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
        let channel = try bootstrap.bind(host: host, port: port).wait()
        serverChannel = channel
        channel.eventLoop.scheduleRepeatedTask(initialDelay: .seconds(30), delay: .seconds(30)) { [weak self] _ in
            self?.expireRooms()
        }
        return channel.localAddress?.port ?? port
    }

    /// Blocks until the server stops (used by the executable).
    public func waitUntilClosed() throws {
        try serverChannel?.closeFuture.wait()
    }

    public func shutdown() async throws {
        try await serverChannel?.close()
        try await group.shutdownGracefully()
    }

    // MARK: Called on the event loop by RelayFrameHandler

    func connected(_ channel: Channel) {
        channels[ObjectIdentifier(channel)] = channel
    }

    func received(_ bytes: [UInt8], from channel: Channel) {
        perform(core.received(bytes, from: ObjectIdentifier(channel), now: Self.now(), using: &rng))
    }

    func disconnected(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        guard channels.removeValue(forKey: id) != nil else { return }
        perform(core.disconnected(id))
    }

    private func expireRooms() {
        perform(core.expire(now: Self.now(), ttl: roomTTL))
    }

    private func perform(_ actions: [RelayAction<ObjectIdentifier>]) {
        for action in actions {
            switch action {
            case .send(let bytes, let id):
                guard let channel = channels[id] else { continue }
                let frame = WebSocketFrame(fin: true, opcode: .binary, data: channel.allocator.buffer(bytes: bytes))
                channel.writeAndFlush(frame, promise: nil)
            case .close(let id):
                guard let channel = channels[id] else { continue }
                let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: channel.allocator.buffer(capacity: 0))
                channel.writeAndFlush(frame).whenComplete { _ in channel.close(promise: nil) }
            }
        }
    }

    private static func now() -> Double {
        Double(NIODeadline.now().uptimeNanoseconds) / 1e9
    }
}

/// Unwraps WebSocket frames for the server. The protocol uses only whole binary frames.
final class RelayFrameHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let server: RelayServer

    init(server: RelayServer) {
        self.server = server
    }

    func handlerAdded(context: ChannelHandlerContext) {
        server.connected(context.channel)
    }

    func channelInactive(context: ChannelHandlerContext) {
        server.disconnected(context.channel)
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .binary where frame.fin:
            server.received(Array(buffer: frame.unmaskedData), from: context.channel)
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .pong:
            break
        default:   // close, text or fragmented frames: none are part of this protocol
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
```

If your SwiftNIO version marks `Channel.writeAndFlush(_:promise:)` or `EventLoopFuture.wait()` as deprecated, the warnings are fine. If it reports a different initializer shape for `NIOWebSocketServerUpgrader`, follow the signature the compiler suggests: keep `maxFrameSize`, `shouldUpgrade` and `upgradePipelineHandler` with the same behaviour.

- [ ] **Step 4: Add the executable**

In `Package.swift`, add this line after the `TanksRelayCore` target:

```swift
        .executableTarget(name: "TanksRelay", dependencies: ["TanksRelayCore", "TanksNet"]),
```

Create `Sources/TanksRelay/main.swift`:

```swift
import Foundation
import TanksNet
import TanksRelayCore

let environment = ProcessInfo.processInfo.environment
let port = environment["PORT"].flatMap(Int.init) ?? 8080
let roomTTL = environment["ROOM_TTL"].flatMap(Double.init) ?? RelayLimits.defaultRoomTTL

let server = RelayServer(roomTTL: roomTTL)
let boundPort = try server.start(host: "0.0.0.0", port: port)
print("TanksRelay listening on ws://0.0.0.0:\(boundPort)/ws (protocol \(TanksNet.protocolVersion))")
try server.waitUntilClosed()
```

- [ ] **Step 5: Run all tests**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`
Expected: `Build complete!`; every test target passes, including the three `RelayServerTests`.

- [ ] **Step 6: Run the relay by hand**

Run:

```bash
( PORT=8099 swift run TanksRelay & PID=$!; sleep 6; curl -s -o /dev/null -w "%{http_code}\n" -m 2 \
    -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" \
    -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" http://127.0.0.1:8099/ws; kill $PID )
```

Expected: `TanksRelay listening on ws://0.0.0.0:8099/ws (protocol 1)` followed by `101` (the WebSocket upgrade succeeded).

- [ ] **Step 7: Docker image and docs**

Create `.dockerignore`:

```
.build
dist
.git
docs
```

Create `Dockerfile`:

```dockerfile
# Tanks of Doom relay server.
#   docker build -t tanks-relay .
#   docker run -p 8080:8080 tanks-relay
FROM swift:6.0-jammy AS build
WORKDIR /src
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY Sources ./Sources
COPY Tests ./Tests
RUN swift build -c release --product TanksRelay --static-swift-stdlib

FROM ubuntu:jammy
RUN useradd --system relay
COPY --from=build /src/.build/release/TanksRelay /usr/local/bin/TanksRelay
USER relay
ENV PORT=8080
EXPOSE 8080
CMD ["TanksRelay"]
```

Create `docs/relay.md`:

````markdown
# Running the relay server

Online matches go through a small relay server: the host and guest both connect to it, it pairs
them by room code and passes their messages along. It never looks inside game messages and keeps
nothing on disk.

## Locally

```bash
swift run TanksRelay                                  # listens on ws://0.0.0.0:8080/ws
TANKS_RELAY_URL=ws://localhost:8080/ws swift run TanksOfDoom
```

Start the game twice (two terminals) to play against yourself. Other Macs on your network can use
`ws://<your-mac's-IP>:8080/ws`.

Settings (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `8080` | TCP port to listen on |
| `ROOM_TTL` | `600` | Seconds a host may wait for a guest before the room is closed |

Fixed limits: 500 rooms, 64 KB per frame, 100 frames per second per connection.

## On a server

Any Linux VPS with Docker works (1 vCPU / 512 MB is plenty). Put TLS in front of it so players
connect with `wss://`.

```bash
git clone https://github.com/dpalmqvist/tanks-of-doom.git && cd tanks-of-doom
docker build -t tanks-relay .
docker run -d --restart unless-stopped --name tanks-relay -p 127.0.0.1:8080:8080 tanks-relay
```

Then point a domain at the server and let [Caddy](https://caddyserver.com) handle certificates.
`/etc/caddy/Caddyfile`:

```
relay.example.com {
    reverse_proxy /ws 127.0.0.1:8080
}
```

`sudo systemctl reload caddy`, and the relay is at `wss://relay.example.com/ws`. Put that URL in
`RelayConfig.defaultURL` (`Sources/TanksOfDoom/RelayConnection.swift`) before building a release.

## Updating

Bump `TanksNet.protocolVersion` whenever the message format changes. The relay refuses games with
a different version, so deploy the new relay together with the new game release.
````

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/TanksRelayCore Sources/TanksRelay Tests/TanksRelayCoreTests Dockerfile .dockerignore docs/relay.md
git commit -m "feat(relay): SwiftNIO WebSocket relay server, executable, Docker image and docs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
## Phase E: Playing over the network

### Task 11: Route every effect through one funnel

The host has to tell the guest about every explosion, sound and floating number. This task sends all of them through `fx(_:for:)`, which plays an effect locally when the local player should get it. From Task 12 on, it also queues the effect for the guest. Behaviour doesn't change in this task.

**Files:**
- Create: `Sources/TanksOfDoom/GameScene+FX.swift`
- Modify: `Sources/TanksOfDoom/Audio.swift`, `GameScene.swift`, `GameScene+Combat.swift`, `GameScene+Player.swift`, `GameScene+Enemies.swift`, `GameScene+Infantry.swift`, `GameScene+Versus.swift`, `EnemyTank.swift`

**Interfaces:**
- Consumes: `GameEvent`, `FXColor`, `SoundID`, `Vec2` (Task 8); `Level.setBuildingHP(_:to:)` (Task 1); `versusRole` (Task 5).
- Produces:
  - `enum Audience { case everyone, only(Player), allBut(Player); func includes(_:) -> Bool }`
  - `GameScene.fx(_ event: GameEvent, for: Audience = .everyone)`, `playLocally(_:)`, `remotePlayer: Player?`, `outgoingEvents: [GameEvent]`, `mirrorBuildingHP(_:_:)`
  - `CGPoint.vec: Vec2`, `Vec2.cgPoint: CGPoint`, `FXColor.nsColor`
  - `Audio.Sound` is now `TanksNet.SoundID`

- [ ] **Step 1: Make the synthesizer's sound list the wire's sound list**

In `Sources/TanksOfDoom/Audio.swift`, add `import TanksNet` and replace

```swift
    enum Sound: CaseIterable {
        case cannon, machineGun, explosion, bigExplosion, hit, rocket, pickup, empty
    }
```

with

```swift
    /// Shared with the network protocol so the host can name sounds for the guest.
    typealias Sound = SoundID
```

- [ ] **Step 2: Add the funnel**

Create `Sources/TanksOfDoom/GameScene+FX.swift`:

```swift
import AppKit
import SpriteKit
import TanksCore
import TanksNet

/// Who should see or hear an effect.
enum Audience {
    case everyone
    case only(Player)
    case allBut(Player)

    func includes(_ player: Player) -> Bool {
        switch self {
        case .everyone: return true
        case .only(let p): return p === player
        case .allBut(let p): return p !== player
        }
    }
}

extension CGPoint {
    var vec: Vec2 { Vec2(Float(x), Float(y)) }
}

extension Vec2 {
    var cgPoint: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
}

extension FXColor {
    var nsColor: NSColor {
        switch self {
        case .white: return .white
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .orange: return .systemOrange
        }
    }
}

extension GameScene {
    /// The player on the other Mac when this one is hosting a networked match.
    var remotePlayer: Player? {
        guard let role = versusRole, role.isHost else { return nil }
        return players.first { $0 !== localPlayer }
    }

    /// Every sight and sound the simulation makes goes through here. It plays on this Mac if the local
    /// player is in the audience, and on a host it's queued for the guest's next snapshot if they are.
    func fx(_ event: GameEvent, for audience: Audience = .everyone) {
        if audience.includes(localPlayer) { playLocally(event) }
        if let remote = remotePlayer, audience.includes(remote) { outgoingEvents.append(event) }
    }

    func playLocally(_ event: GameEvent) {
        switch event {
        case let .explosion(at, scale): effects.explosion(at: at.cgPoint, scale: CGFloat(scale))
        case let .spark(at): effects.spark(at: at.cgPoint)
        case let .dust(at): effects.dustPuff(at: at.cgPoint)
        case let .muzzleFlash(at, angle, big): effects.muzzleFlash(at: at.cgPoint, angle: CGFloat(angle), big: big)
        case let .text(text, at, color): effects.floatingText(text, at: at.cgPoint, color: color.nsColor)
        case let .sound(sound, at, volume): playSound(sound, at: at.cgPoint, volume: volume)
        case let .uiSound(sound, volume): Audio.shared.play(sound, volume: volume)
        case let .shake(magnitude, duration): shake(CGFloat(magnitude), duration: Double(duration))
        case let .buildingHP(id, hp): mirrorBuildingHP(Int(id), Int(hp))
        case let .kill(killer, victim): hud.addKillFeed(KillFeed.line(killer: killer, victim: victim, viewer: localPlayer.slot))
        case let .flash(text, color, duration): hud.flash(text, color: color.nsColor, duration: Double(duration))
        case let .matchOver(winner): matchEnded(winner: winner)
        }
    }

    /// Guest side: the host reported a building's new hit points.
    func mirrorBuildingHP(_ id: Int, _ hp: Int) {
        let result = level.setBuildingHP(id, to: hp)
        guard result != .none else { return }
        renderer.update(level.buildings[id])
        if result == .destroyed { hud.minimap.refresh(map: level.map) }
    }
}
```

In `GameScene.swift`, add `import TanksNet` and this stored property below `var pickupQueue`:

```swift
    /// Effects waiting to ride along with the next snapshot to the guest.
    var outgoingEvents: [GameEvent] = []
```

- [ ] **Step 3: Route the simulation's effects through `fx`**

Add `import TanksNet` to each file below. Then make exactly these replacements. Code not mentioned stays as it is.

`GameScene+Combat.swift`, in `fire(_:from:angle:shooter:ownerBuilding:)`, replace the `switch weapon { ... }` with:

```swift
        switch weapon {
        case .mainGun, .enemyShell:
            fx(.muzzleFlash(at: origin.vec, angle: Float(angle), big: true))
            fx(.sound(.cannon, at: origin.vec, volume: 1))
        case .bazooka:
            fx(.sound(.rocket, at: origin.vec, volume: 1))
        default:
            fx(.muzzleFlash(at: origin.vec, angle: Float(angle), big: false))
            fx(.sound(.machineGun, at: origin.vec, volume: 0.5))
        }
```

In `fireMortar(from:at:)`: `playSound(.cannon, at: origin, volume: 0.4)` → `fx(.sound(.cannon, at: origin.vec, volume: 0.4))`

Replace `updateWeapons(for:dt:)` with:

```swift
    func updateWeapons(for player: Player, dt: Double) {
        let tank = player.tank
        guard !tank.isDestroyed, !tank.isHidden else { return }
        tank.mainCooldown -= dt
        tank.machineGunCooldown -= dt

        if player.input.firePrimary && tank.mainCooldown <= 0 {
            if tank.stats.consumeShell() {
                fire(.mainGun, from: tank.muzzlePosition, angle: tank.turretAngle, shooter: .player(player.slot))
                match?.playerFired(player.slot)
                tank.mainCooldown = Combat.spec(.mainGun).reload
                fx(.shake(magnitude: 4, duration: 0.15), for: .only(player))
            } else {
                tank.mainCooldown = 0.5
                fx(.uiSound(.empty, volume: 1), for: .only(player))
                fx(.text("NO SHELLS", at: (tank.position + CGPoint(x: 0, y: 40)).vec, color: .yellow), for: .only(player))
            }
        }

        if player.input.fireSecondary && tank.machineGunCooldown <= 0 {
            if tank.stats.consumeRound() {
                let side = CGPoint(angle: tank.turretAngle - .pi / 2, length: 7)
                let origin = tank.position + CGPoint(angle: tank.turretAngle, length: 30) + side
                fire(.machineGun, from: origin, angle: tank.turretAngle + .random(in: -0.04...0.04), shooter: .player(player.slot))
                match?.playerFired(player.slot)
                tank.machineGunCooldown = Combat.spec(.machineGun).reload
            } else {
                tank.machineGunCooldown = 0.5
                fx(.uiSound(.empty, volume: 1), for: .only(player))
                fx(.text("NO MG AMMO", at: (tank.position + CGPoint(x: 0, y: 40)).vec, color: .yellow), for: .only(player))
            }
        }
    }
```

In `resolve(_:projectile:at:)`: `effects.spark(at: point)` → `fx(.spark(at: point.vec))`

In `detonate(_:at:direct:)`, replace the two effect lines with:

```swift
        fx(.explosion(at: point.vec, scale: heavy ? 1.0 : 0.7))
        fx(.sound(.explosion, at: point.vec, volume: 0.7))
```

In `updateMortars(dt:)`, replace the two effect lines with:

```swift
            fx(.explosion(at: shell.target.vec, scale: 0.9))
            fx(.sound(.explosion, at: shell.target.vec, volume: 0.8))
```

Replace `damagePlayer(_:_:from:)` with:

```swift
    /// `shooter` is nil when the player abandons their own tank.
    func damagePlayer(_ tank: PlayerTank, _ amount: Int, from shooter: Combatant?) {
        guard amount > 0, !tank.isDestroyed, !tank.isInvulnerable,
              let victim = players.first(where: { $0.tank === tank }) else { return }
        tank.stats.takeDamage(amount)
        fx(.text("-\(amount)", at: (tank.position + CGPoint(x: 0, y: 36)).vec, color: .red))
        fx(.uiSound(.hit, volume: 0.8), for: .only(victim))
        fx(.shake(magnitude: Float(min(14, 3 + CGFloat(amount) * 0.5)), duration: 0.25), for: .only(victim))
        guard tank.isDestroyed else { return }
        fx(.explosion(at: tank.position.vec, scale: 2.2))
        fx(.sound(.bigExplosion, at: tank.position.vec, volume: 1))
        tank.showWreck()
        fx(.shake(magnitude: 20, duration: 0.6), for: .only(victim))
        playerDestroyed(tank, by: shooter)
    }
```

Replace `damageBuilding(_:amount:)` and `buildingDestroyed(_:)` with:

```swift
    func damageBuilding(_ id: Int, amount: Int) {
        let result = level.damageBuilding(id, by: amount)
        guard result != .none else { return }
        renderer.update(level.buildings[id])
        fx(.buildingHP(id: UInt16(id), hp: Int16(clamping: level.buildings[id].hp)), for: .allBut(localPlayer))
        if result == .destroyed { buildingDestroyed(id) }
    }

    func buildingDestroyed(_ id: Int) {
        killOccupants(of: id)
        let center = level.buildings[id].worldCenter
        fx(.explosion(at: center.vec, scale: 2.0))
        fx(.dust(at: center.vec))
        fx(.sound(.bigExplosion, at: center.vec, volume: 1))
        fx(.shake(magnitude: 10, duration: 0.4))
        hud.minimap.refresh(map: level.map)
    }
```

(Bazooka smoke trails in `updateProjectiles` stay as `effects.smokePuff`, because the guest draws its own trails.)

`GameScene+Player.swift`:
- `effects.floatingText("OUT OF FUEL!", at: tank.position + CGPoint(x: 0, y: 44), color: .systemOrange)` → `fx(.text("OUT OF FUEL!", at: (tank.position + CGPoint(x: 0, y: 44)).vec, color: .orange))`
- in `collectPickups(for:)`, replace the text and sound lines with:
  ```swift
              fx(.text(pickup.kind == .gas ? "+GAS" : "+AMMO", at: pickup.position.vec, color: .green))
              fx(.uiSound(.pickup, volume: 1), for: .only(player))
  ```

`GameScene+Enemies.swift`, in `enemyDestroyed(_:)`, replace the three effect lines with:

```swift
        fx(.explosion(at: tank.position.vec, scale: 1.8))
        fx(.sound(.bigExplosion, at: tank.position.vec, volume: 1))
        fx(.shake(magnitude: 8, duration: 0.3))
```

`GameScene+Infantry.swift`, in `infantryKilled(_:)`: `if soldier.alpha > 0 { effects.dustPuff(at: soldier.position) }` → `if soldier.alpha > 0 { fx(.dust(at: soldier.position.vec)) }`

`EnemyTank.swift` (add `import TanksNet`), in `applyDamage`: `scene.effects.floatingText("-\(amount)", at: position + CGPoint(x: 0, y: 40), color: .systemYellow)` → `scene.fx(.text("-\(amount)", at: (position + CGPoint(x: 0, y: 40)).vec, color: .yellow))`

`GameScene+Versus.swift`:
- in `playerDestroyed(_:by:)`: `hud.addKillFeed(KillFeed.line(...))` → `fx(.kill(killer: killer, victim: victim.slot))`
- in `respawn(_:)`: `effects.dustPuff(at: player.tank.position)` → `fx(.dust(at: player.tank.position.vec))`
- in `updateVersus(dt:)`, replace `if let winner = match?.winner { matchEnded(winner: winner) }` with:
  ```swift
          if let winner = match?.winner, endTimer == nil {
              fx(.matchOver(winner: winner), for: .allBut(localPlayer))
              matchEnded(winner: winner)
          }
  ```

Check that nothing else in the simulation still plays effects directly:

```bash
grep -n "effects\.\|playSound(\|Audio.shared" Sources/TanksOfDoom/GameScene*.swift Sources/TanksOfDoom/EnemyTank.swift
```

Expected: only `effects.smokePuff`, `effects.trackMark`, the `playSound` definition, and the calls inside `playLocally`.

- [ ] **Step 4: Build, test, launch check, quick play**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`, then the **Launch check** from Phase B.
Expected: `Build complete!`, all tests pass, `still running after 8 s: OK`.
Manual: play the campaign and a hot-seat match for a minute each. Explosions, sounds, floating numbers, screen shake on your own hits, "NO SHELLS" and the kill feed all behave as before.

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "refactor(app): route simulation effects through one fx funnel with an audience

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Networked match end to end (host simulates, guest mirrors)

**Files:**
- Create: `Sources/TanksOfDoom/RelayConnection.swift`, `MatchLink.swift`, `QuickMatch.swift`, `GuestWorld.swift`, `GameScene+Host.swift`, `GameScene+Guest.swift`
- Modify: `Sources/TanksOfDoom/GameMode.swift`, `GameScene.swift`, `GameScene+Input.swift`, `GameScene+Flow.swift`, `GameScene+Versus.swift`, `InputState.swift`, `EnemyTank.swift`, `Projectile.swift`, `AppDelegate.swift`

**Interfaces:**
- Consumes: everything from Tasks 5, 6, 8 and 11; a running relay (Task 10).
- Produces:
  - `enum RelayConfig { static let defaultURL: String; static var url: URL }` (env `TANKS_RELAY_URL`)
  - `final class RelayConnection { enum Event { relay(RelayMessage), game(GameMessage), closed(String?) }; var onEvent; init(url:); open(); send(relay:); send(_ message: GameMessage); close() }`
  - `final class MatchLink { static let pingInterval = 1.0, lostAfter = 3.0, giveUpAfter = 10.0; let connection; var onMessage: ((GameMessage) -> Void)?; var onClosed: ((String?) -> Void)?; latencyMs: Int?; silence: Double; send(_:); tick(dt:); close() }`
  - `VersusRole.host(MatchLink)`, `VersusRole.guest(MatchLink)`, `VersusRole.link: MatchLink?`
  - `InputState.init(bits:)`, `InputState.bits`
  - `EnemyTank.armorFraction`, `EnemyTank.showHealth(_:)`; `MortarShell.progress`, `MortarShell.show(progress:)`
  - `GameScene.matchWinner: PlayerSlot?`, `isGuest`, `attach(_:)`, `receive(_:)`, `linkClosed(_:)`, `makeSnapshot()`, `receiveSnapshot(_:)`, `updateGuest(dt:)`
  - `final class GuestWorld { buffer: SnapshotBuffer; shots; mortars; inputTimer; inputSeq; presses; takePresses() }`
  - Environment variables `TANKS_HOST=1` and `TANKS_JOIN=<code>` (developer quick match)

- [ ] **Step 1: The connection and the match link**

Create `Sources/TanksOfDoom/RelayConnection.swift`:

```swift
import Foundation
import TanksNet

enum RelayConfig {
    /// The deployed relay (see docs/relay.md). TANKS_RELAY_URL overrides it, e.g. ws://localhost:8080/ws.
    static let defaultURL = "ws://localhost:8080/ws"

    static var url: URL {
        let configured = ProcessInfo.processInfo.environment["TANKS_RELAY_URL"] ?? defaultURL
        return URL(string: configured) ?? URL(string: defaultURL)!
    }
}

/// One WebSocket to the relay. Every callback arrives on the main thread.
final class RelayConnection {
    enum Event {
        case relay(RelayMessage)
        case game(GameMessage)
        /// The connection ended; the reason is for the player.
        case closed(String?)
    }

    var onEvent: ((Event) -> Void)?
    private let task: URLSessionWebSocketTask
    private var isClosed = false

    init(url: URL = RelayConfig.url) {
        task = URLSession.shared.webSocketTask(with: url)
    }

    func open() {
        task.resume()
        send(relay: .hello(version: TanksNet.protocolVersion))
        receiveNext()
    }

    func send(relay message: RelayMessage) {
        send(bytes: message.encoded())
    }

    func send(_ message: GameMessage) {
        send(bytes: message.encoded())
    }

    /// Hangs up quietly (no `.closed` event): we chose to leave.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        task.cancel(with: .goingAway, reason: nil)
    }

    private func send(bytes: [UInt8]) {
        guard !isClosed else { return }
        task.send(.data(Data(bytes))) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async { self?.fail("Can't reach server") }
        }
    }

    private func receiveNext() {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, !self.isClosed else { return }
                switch result {
                case .success(.data(let data)):
                    self.handle([UInt8](data))
                    self.receiveNext()
                case .success:
                    self.fail("Connection error")
                case .failure:
                    self.fail("Can't reach server")
                }
            }
        }
    }

    private func handle(_ bytes: [UInt8]) {
        do {
            if RelayMessage.isControlFrame(bytes) {
                onEvent?(.relay(try RelayMessage.decode(bytes)))
            } else {
                onEvent?(.game(try GameMessage.decode(bytes)))
            }
        } catch {
            fail("Connection error")
        }
    }

    private func fail(_ reason: String) {
        guard !isClosed else { return }
        isClosed = true
        task.cancel(with: .goingAway, reason: nil)
        onEvent?(.closed(reason))
    }
}
```

Create `Sources/TanksOfDoom/MatchLink.swift`:

```swift
import Foundation
import TanksNet

/// The connection between two paired players: game messages in and out, latency pings, and how long
/// the other side has been silent. Scenes take turns owning it (lobby → match → result screen).
final class MatchLink {
    static let pingInterval = 1.0
    static let lostAfter = 3.0
    static let giveUpAfter = 10.0

    let connection: RelayConnection
    var onMessage: ((GameMessage) -> Void)?
    /// The opponent left or the connection died.
    var onClosed: ((String?) -> Void)?
    private(set) var latencyMs: Int?
    private var lastHeard = ProcessInfo.processInfo.systemUptime
    private var pingTimer = 0.0

    init(connection: RelayConnection) {
        self.connection = connection
        connection.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Seconds since the other side last said anything.
    var silence: Double { ProcessInfo.processInfo.systemUptime - lastHeard }

    func send(_ message: GameMessage) {
        connection.send(message)
    }

    func tick(dt: Double) {
        pingTimer -= dt
        guard pingTimer <= 0 else { return }
        pingTimer = Self.pingInterval
        send(.ping(ProcessInfo.processInfo.systemUptime))
    }

    func close() {
        connection.close()
    }

    private func handle(_ event: RelayConnection.Event) {
        switch event {
        case .game(let message):
            lastHeard = ProcessInfo.processInfo.systemUptime
            switch message {
            case .ping(let time):
                send(.pong(time))
            case .pong(let time):
                latencyMs = Int(((ProcessInfo.processInfo.systemUptime - time) * 1000).rounded())
            default:
                onMessage?(message)
            }
        case .relay(.peerLeft):
            onClosed?("Opponent left")
        case .relay:
            break
        case .closed(let reason):
            onClosed?(reason)
        }
    }
}
```

- [ ] **Step 2: Roles that carry the link**

Replace `Sources/TanksOfDoom/GameMode.swift` with:

```swift
import TanksCore

/// How this Mac takes part in a versus match.
enum VersusRole {
    /// Debug only: both players on this keyboard (TANKS_HOTSEAT=1).
    case hotSeat
    /// Runs the simulation and streams it to the guest.
    case host(MatchLink)
    /// Sends its keys and mirrors what the host streams.
    case guest(MatchLink)

    /// The player at this keyboard.
    var localSlot: PlayerSlot {
        if case .guest = self { return .guest }
        return .host
    }

    var isHost: Bool {
        if case .host = self { return true }
        return false
    }

    var isGuest: Bool {
        if case .guest = self { return true }
        return false
    }

    var link: MatchLink? {
        switch self {
        case .hotSeat: return nil
        case .host(let link), .guest(let link): return link
        }
    }
}

enum GameMode {
    case campaign
    case versus(VersusRole)
}
```

- [ ] **Step 3: Input bits, enemy health bars and mortar progress**

Replace `Sources/TanksOfDoom/InputState.swift` with:

```swift
import TanksNet

struct InputState {
    var forward = false
    var backward = false
    var left = false
    var right = false
    var turretLeft = false
    var turretRight = false
    var space = false
    var fKey = false

    var firePrimary: Bool { space }
    var fireSecondary: Bool { fKey }
    var turretManualHeld: Bool { turretLeft || turretRight }
}

extension InputState {
    /// The keys as sent over the network (`InputFrame` held bits).
    init(bits: UInt8) {
        forward = bits & InputFrame.forward != 0
        backward = bits & InputFrame.backward != 0
        left = bits & InputFrame.left != 0
        right = bits & InputFrame.right != 0
        turretLeft = bits & InputFrame.turretLeft != 0
        turretRight = bits & InputFrame.turretRight != 0
        space = bits & InputFrame.fireMain != 0
        fKey = bits & InputFrame.fireMG != 0
    }

    var bits: UInt8 {
        var bits: UInt8 = 0
        if forward { bits |= InputFrame.forward }
        if backward { bits |= InputFrame.backward }
        if left { bits |= InputFrame.left }
        if right { bits |= InputFrame.right }
        if turretLeft { bits |= InputFrame.turretLeft }
        if turretRight { bits |= InputFrame.turretRight }
        if space { bits |= InputFrame.fireMain }
        if fKey { bits |= InputFrame.fireMG }
        return bits
    }
}
```

In `EnemyTank.swift`, add below `var canBeHit`:

```swift
    var armorFraction: Double { max(0, armor / maxArmor) }

    /// Guest side: show the health the host reports.
    func showHealth(_ fraction: Double) {
        guard fraction < 1 else { return }
        healthBack.isHidden = false
        healthBar.isHidden = false
        healthBar.xScale = CGFloat(max(0, fraction))
    }
```

In `Projectile.swift`, replace `MortarShell.advance(dt:)` with:

```swift
    /// 0 at launch, 1 on landing.
    var progress: Double { min(1, elapsed / Self.flightTime) }

    /// Advances along the arc; returns true on landing.
    func advance(dt: Double) -> Bool {
        elapsed += dt
        show(progress: CGFloat(progress))
        return progress >= 1
    }

    /// Puts the shell at `t` along its arc (the guest drives this from snapshots).
    func show(progress t: CGFloat) {
        position = start + (target - start) * t
        setScale(1 + 1.8 * sin(.pi * t))
    }
```

- [ ] **Step 4: Scene plumbing per role**

In `GameScene.swift`, add these stored properties below `var outgoingEvents`:

```swift
    /// Host: the guest's latest keys.
    var remoteInput = RemoteInput()
    var snapshotTimer = 0.0
    var hostTick: UInt32 = 0
    /// Guest: everything mirrored from the host.
    var guestWorld: GuestWorld?
    /// Networked matches open with 3-2-1 so both Macs start together.
    var countdown: Double?
    var matchWinner: PlayerSlot?
    static let countdownLength = 3.0
```

At the end of `convenience init(size:versus:role:)`, add:

```swift
        if role.link != nil { countdown = Self.countdownLength }
        if role.isGuest { guestWorld = GuestWorld() }
```

In `didMove(to:)`, add after `buildWorld()`:

```swift
        if let link = versusRole?.link { attach(link) }
```

In `buildWorld()`, replace

```swift
        spawnEnemies()
        spawnInfantry()
```

with

```swift
        if !isGuest {   // the guest's AI arrives through snapshots
            spawnEnemies()
            spawnInfantry()
        }
```

Replace `update(_:)` with:

```swift
    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(currentTime - lastUpdate, 1.0 / 30)
        lastUpdate = currentTime
        versusRole?.link?.tick(dt: dt)
        guard !isGamePaused, !levelOver else { return }
        if !updateCountdown(dt: dt) {
            if isGuest {
                updateGuest(dt: dt)
            } else {
                if versusRole?.isHost == true { applyRemoteInput() }
                updatePlayers(dt: dt)
                updateEnemies(dt: dt)
                updateInfantry(dt: dt)
                updateProjectiles(dt: dt)
                updateMortars(dt: dt)
                updateVersus(dt: dt)
                if versusRole?.isHost == true { sendSnapshotIfDue(dt: dt) }
            }
            updateTargetMarker()
            watchConnection()
        }
        updateCamera(dt: dt)
        updateHUD()
        checkLevelEnd(dt: dt)
    }

    /// Returns true while the opening 3-2-1 is still running.
    private func updateCountdown(dt: Double) -> Bool {
        guard let remaining = countdown else { return false }
        let next = remaining - dt
        if next <= 0 {
            countdown = nil
            hud.flash("GO!", color: .systemGreen, duration: 0.8)
            return false
        }
        let shownNow = Int(next.rounded(.up))
        if remaining == Self.countdownLength || shownNow != Int(remaining.rounded(.up)) {
            hud.flash("\(shownNow)", duration: 0.9)
        }
        countdown = next
        return true
    }
```

In `GameScene+Versus.swift`:
- add `var isGuest: Bool { versusRole?.isGuest == true }` to the extension
- in `matchEnded(winner:)`, add `matchWinner = winner` after the `guard`
- replace `versusResult()` with:

```swift
    func versusResult() -> VersusResult {
        var lives: [PlayerSlot: Int] = [:]
        var kills: [PlayerSlot: Int] = [:]
        if let match {
            lives = match.lives
            kills = match.kills
        } else {
            for p in guestWorld?.buffer.latest?.players ?? [] {
                lives[p.slot] = Int(p.lives)
                kills[p.slot] = Int(p.kills)
            }
        }
        return VersusResult(winner: matchWinner ?? localPlayer.slot, localSlot: localPlayer.slot, lives: lives, kills: kills)
    }
```

- replace `versusHUDState()` with:

```swift
    func versusHUDState() -> VersusHUDState? {
        guard let role = versusRole else { return nil }
        var state: VersusHUDState
        if let match {
            state = VersusHUDState(localSlot: localPlayer.slot, lives: match.lives,
                                   respawnIn: match.respawnRemaining(localPlayer.slot), latencyMs: nil, notice: nil)
        } else {
            let latest = guestWorld?.buffer.latest
            var lives: [PlayerSlot: Int] = [:]
            for p in latest?.players ?? [] { lives[p.slot] = Int(p.lives) }
            let mine = latest?.players.first { $0.slot == localPlayer.slot }
            let respawnIn = mine.flatMap { $0.has(PlayerSnapshot.respawning) ? Double($0.respawnIn) : nil }
            state = VersusHUDState(localSlot: localPlayer.slot, lives: lives, respawnIn: respawnIn, latencyMs: nil, notice: nil)
        }
        if let link = role.link {
            state.latencyMs = link.latencyMs
            if link.silence > MatchLink.lostAfter && endTimer == nil { state.notice = "CONNECTION LOST…" }
        }
        return state
    }
```

Add `import TanksNet` to `GameScene+Versus.swift`.

In `GameScene+Flow.swift`:
- in `togglePause()`, change the guard to `guard endTimer == nil, versusRole?.link == nil else { return }` (no pausing a networked match; Task 15 adds a leave prompt).
- in `finishLevel()`, replace the `if isVersus { ... }` block with:

```swift
        if isVersus {
            versusRole?.link?.close()
            view.presentScene(MenuScene.versusResult(size: size, result: versusResult()), transition: .fade(withDuration: 0.8))
            return
        }
```

In `GameScene+Input.swift`, replace `handleKeyPress(_:)` with:

```swift
    func handleKeyPress(_ code: UInt16) {
        switch code {
        case 46: hud.toggleMinimap()                   // M
        case 53: togglePause()                         // Esc
        case 15: press(InputFrame.abandon) { abandonTank(localPlayer) }            // R
        case 48: press(InputFrame.cycleTarget) { cycleTarget(for: localPlayer) }   // Tab
        case 12, 14: press(InputFrame.manualTurret) { localPlayer.turretAim.manualInput() }   // Q, E
        default: break
        }
    }

    /// One-shot keys: a guest sends them to the host; everyone else acts on them here.
    private func press(_ bit: UInt8, otherwise act: () -> Void) {
        if let world = guestWorld {
            world.presses |= bit
        } else {
            act()
        }
    }
```

and add `import TanksNet` at the top.

- [ ] **Step 5: The host side**

Create `Sources/TanksOfDoom/GameScene+Host.swift`:

```swift
import SpriteKit
import TanksCore
import TanksNet

extension GameScene {
    static let snapshotInterval = 0.05

    func attach(_ link: MatchLink) {
        link.onMessage = { [weak self] message in self?.receive(message) }
        link.onClosed = { [weak self] reason in self?.linkClosed(reason) }
    }

    func receive(_ message: GameMessage) {
        switch message {
        case .input(let frame): remoteInput.receive(frame, at: lastUpdate)
        case .snapshot(let snapshot): receiveSnapshot(snapshot)
        case .leave: linkClosed("Opponent left")
        default: break
        }
    }

    /// The other side is gone: whoever is still here wins.
    func linkClosed(_ reason: String?) {
        guard isVersus, endTimer == nil else { return }
        hud.flash((reason ?? "Connection lost").uppercased(), color: .systemOrange, duration: 3)
        match?.playerLeft(localPlayer.slot.opponent)
        matchEnded(winner: localPlayer.slot)
    }

    /// Gives up on a silent opponent.
    func watchConnection() {
        guard let link = versusRole?.link, endTimer == nil, link.silence > MatchLink.giveUpAfter else { return }
        linkClosed("Connection lost")
    }

    /// Host: the guest's latest keys drive their Player; one-shot presses act once.
    func applyRemoteInput() {
        guard let guest = remotePlayer else { return }
        guest.input = InputState(bits: remoteInput.heldKeys(at: lastUpdate))
        let presses = remoteInput.takePresses()
        if presses & InputFrame.cycleTarget != 0 { cycleTarget(for: guest) }
        if presses & InputFrame.manualTurret != 0 { guest.turretAim.manualInput() }
        if presses & InputFrame.abandon != 0 { abandonTank(guest) }
    }

    func sendSnapshotIfDue(dt: Double) {
        snapshotTimer -= dt
        guard snapshotTimer <= 0, let link = versusRole?.link else { return }
        snapshotTimer = Self.snapshotInterval
        hostTick += 1
        link.send(.snapshot(makeSnapshot()))
        outgoingEvents.removeAll()
    }

    func makeSnapshot() -> Snapshot {
        Snapshot(
            tick: hostTick, time: lastUpdate, ackInputSeq: remoteInput.lastSeq,
            players: players.map(snapshot(of:)),
            tanks: enemies.map {
                EnemyTankSnapshot(id: $0.netID, position: $0.position.vec, heading: Float($0.heading),
                                  turret: Float($0.turretAngle), health: Float($0.armorFraction))
            },
            soldiers: infantry.filter(\.isExposed).map {
                SoldierSnapshot(id: $0.netID, kind: $0.kind, position: $0.position.vec, facing: Float($0.zRotation))
            },
            shots: projectiles.map {
                ShotSnapshot(id: $0.netID, weapon: $0.weapon, position: $0.position.vec, angle: Float($0.zRotation))
            },
            mortars: mortars.map {
                MortarSnapshot(id: $0.netID, start: $0.start.vec, target: $0.target.vec, progress: Float($0.progress))
            },
            pickups: pickups.map(\.isAvailable),
            events: outgoingEvents)
    }

    private func snapshot(of player: Player) -> PlayerSnapshot {
        let tank = player.tank
        let slot = player.slot
        var flags: UInt8 = 0
        if tank.isDestroyed { flags |= PlayerSnapshot.destroyed }
        if tank.isInvulnerable { flags |= PlayerSnapshot.invulnerable }
        if tank.isHidden { flags |= PlayerSnapshot.respawning }
        if player.inBase { flags |= PlayerSnapshot.inBase }
        return PlayerSnapshot(
            slot: slot, position: tank.position.vec, heading: Float(tank.heading), turret: Float(tank.turretAngle),
            armor: Float(tank.stats.armor), fuel: Float(tank.stats.fuel),
            shells: UInt16(clamping: tank.stats.shells), rounds: UInt16(clamping: tank.stats.rounds),
            lives: UInt8(clamping: match?.lives[slot] ?? 0), kills: UInt16(clamping: match?.kills[slot] ?? 0),
            flags: flags, respawnIn: Float(match?.respawnRemaining(slot) ?? 0),
            lockedTarget: lockedTarget(of: player)?.netID ?? 0)
    }
}
```

- [ ] **Step 6: The guest side**

Create `Sources/TanksOfDoom/GuestWorld.swift`:

```swift
import SpriteKit
import TanksNet

/// Guest-side state: buffered snapshots from the host, the shot and mortar nodes standing in for
/// what they describe, and the keys on their way to the host.
final class GuestWorld {
    var buffer = SnapshotBuffer()
    var shots: [UInt32: Projectile] = [:]
    var mortars: [UInt32: MortarShell] = [:]
    var inputTimer = 0.0
    var inputSeq: UInt32 = 0
    /// One-shot keys (Tab, Q/E, R) waiting for the next input frame.
    var presses: UInt8 = 0

    func takePresses() -> UInt8 {
        defer { presses = 0 }
        return presses
    }
}
```

Create `Sources/TanksOfDoom/GameScene+Guest.swift`:

```swift
import SpriteKit
import TanksCore
import TanksNet

extension GameScene {
    static let inputInterval = 1.0 / 30

    func receiveSnapshot(_ snapshot: Snapshot) {
        guard let world = guestWorld, world.buffer.insert(snapshot, receivedAt: lastUpdate) else { return }
        for event in snapshot.events { playLocally(event) }
        for (index, available) in snapshot.pickups.enumerated() where index < pickups.count {
            pickups[index].isAvailable = available
        }
        if let mine = snapshot.players.first(where: { $0.slot == localPlayer.slot }) { applyOwnState(mine) }
    }

    /// Everything the host decided about the local player apart from where the tank is.
    private func applyOwnState(_ mine: PlayerSnapshot) {
        let tank = localPlayer.tank
        tank.stats.armor = Double(mine.armor)
        tank.stats.fuel = Double(mine.fuel)
        tank.stats.shells = Int(mine.shells)
        tank.stats.rounds = Int(mine.rounds)
        localPlayer.inBase = mine.has(PlayerSnapshot.inBase)
        localPlayer.lockedTargetID = mine.lockedTarget == 0 ? nil : Int(mine.lockedTarget)
    }

    func updateGuest(dt: Double) {
        guard let world = guestWorld else { return }
        sendInput(dt: dt)
        guard let frame = world.buffer.frame(at: lastUpdate) else { return }
        for state in frame.to.players {
            let from = frame.from.players.first { $0.slot == state.slot } ?? state
            mirror(player(state.slot), from: from, to: state, t: frame.t)
        }
        mirrorEnemies(frame)
        mirrorSoldiers(frame)
        mirrorShots(frame, dt: dt)
        mirrorMortars(frame)
    }

    private func sendInput(dt: Double) {
        guard let world = guestWorld, let link = versusRole?.link else { return }
        world.inputTimer -= dt
        guard world.inputTimer <= 0 else { return }
        world.inputTimer = Self.inputInterval
        world.inputSeq += 1
        link.send(.input(InputFrame(seq: world.inputSeq, held: localPlayer.input.bits, presses: world.takePresses())))
    }

    private func mirror(_ player: Player, from a: PlayerSnapshot, to b: PlayerSnapshot, t: Double) {
        let tank = player.tank
        let respawning = b.has(PlayerSnapshot.respawning)
        if respawning && !tank.isHidden {
            addWreck(Textures.hull(for: player.slot), at: tank.position, heading: tank.heading)
            tank.isHidden = true
        } else if !respawning && tank.isHidden {
            tank.respawn(at: b.position.cgPoint, heading: CGFloat(b.heading))
            if player === localPlayer { cameraBase = tank.position }
        }
        guard !respawning else { return }
        let from = a.has(PlayerSnapshot.respawning) ? b : a   // don't slide from where it died
        let before = tank.position
        tank.position = from.position.lerp(to: b.position, t).cgPoint
        tank.heading = CGFloat(lerpAngle(from.heading, b.heading, t))
        tank.turretAngle = CGFloat(lerpAngle(from.turret, b.turret, t))
        leaveTracks(tank, moved: tank.position.distance(to: before))
        tank.isInvulnerable = b.has(PlayerSnapshot.invulnerable)
        tank.alpha = tank.isInvulnerable && Int(lastUpdate * 8) % 2 == 0 ? 0.35 : 1
        if b.has(PlayerSnapshot.destroyed) { tank.showWreck() }
    }

    private func mirrorEnemies(_ frame: SnapshotBuffer.Frame) {
        let live = Set(frame.to.tanks.map(\.id))
        for tank in enemies where !live.contains(tank.netID) {
            addWreck(Textures.enemyHull, at: tank.position, heading: tank.heading)
            tank.removeFromParent()
        }
        enemies.removeAll { !live.contains($0.netID) }
        for state in frame.to.tanks {
            let from = frame.from.tanks.first { $0.id == state.id } ?? state
            let tank = enemies.first { $0.netID == state.id } ?? addMirroredEnemy(state)
            let before = tank.position
            tank.position = from.position.lerp(to: state.position, frame.t).cgPoint
            tank.heading = CGFloat(lerpAngle(from.heading, state.heading, frame.t))
            tank.turretAngle = CGFloat(lerpAngle(from.turret, state.turret, frame.t))
            tank.showHealth(Double(state.health))
            leaveTracks(tank, moved: tank.position.distance(to: before))
        }
    }

    private func addMirroredEnemy(_ state: EnemyTankSnapshot) -> EnemyTank {
        let origin = level.map.grid(state.position.cgPoint)
        let tank = EnemyTank(spawn: EnemyTankSpawn(position: origin, patrol: [origin]), difficulty: Difficulty(level: levelNumber))
        tank.netID = state.id
        tank.position = state.position.cgPoint
        tank.heading = CGFloat(state.heading)
        worldNode.addChild(tank)
        enemies.append(tank)
        return tank
    }

    private func mirrorSoldiers(_ frame: SnapshotBuffer.Frame) {
        let live = Set(frame.to.soldiers.map(\.id))
        for soldier in infantry where !live.contains(soldier.netID) {
            soldier.removeAllActions()
            soldier.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
        infantry.removeAll { !live.contains($0.netID) }
        for state in frame.to.soldiers {
            let soldier = infantry.first { $0.netID == state.id } ?? addMirroredSoldier(state)
            soldier.position = state.position.cgPoint
            soldier.zRotation = CGFloat(state.facing)
        }
    }

    private func addMirroredSoldier(_ state: SoldierSnapshot) -> InfantryNode {
        let soldier = InfantryNode(spawn: InfantrySpawn(kind: state.kind, buildingID: 0), initialDelay: 0)
        soldier.netID = state.id
        soldier.position = state.position.cgPoint
        soldier.run(.fadeIn(withDuration: 0.15))
        worldNode.addChild(soldier)
        infantry.append(soldier)
        return soldier
    }

    private func mirrorShots(_ frame: SnapshotBuffer.Frame, dt: Double) {
        guard let world = guestWorld else { return }
        let live = Set(frame.to.shots.map(\.id))
        for (id, shot) in world.shots where !live.contains(id) {
            shot.removeFromParent()
            world.shots[id] = nil
        }
        for state in frame.to.shots {
            let from = frame.from.shots.first { $0.id == state.id } ?? state
            let shot = world.shots[state.id] ?? addMirroredShot(state)
            shot.position = from.position.lerp(to: state.position, frame.t).cgPoint
            if state.weapon == .bazooka {
                shot.smokeTimer -= dt
                if shot.smokeTimer <= 0 {
                    effects.smokePuff(at: shot.position)
                    shot.smokeTimer = 0.03
                }
            }
        }
    }

    private func addMirroredShot(_ state: ShotSnapshot) -> Projectile {
        let shot = Projectile(weapon: state.weapon, angle: CGFloat(state.angle), shooter: .enemyTank, ownerBuilding: nil)
        shot.netID = state.id
        shot.position = state.position.cgPoint
        worldNode.addChild(shot)
        guestWorld?.shots[state.id] = shot
        return shot
    }

    private func mirrorMortars(_ frame: SnapshotBuffer.Frame) {
        guard let world = guestWorld else { return }
        let live = Set(frame.to.mortars.map(\.id))
        for (id, shell) in world.mortars where !live.contains(id) {
            shell.marker.removeFromParent()
            shell.removeFromParent()
            world.mortars[id] = nil
        }
        for state in frame.to.mortars {
            let from = frame.from.mortars.first { $0.id == state.id } ?? state
            let shell = world.mortars[state.id] ?? addMirroredMortar(state)
            shell.show(progress: CGFloat(from.progress + (state.progress - from.progress) * Float(frame.t)))
        }
    }

    private func addMirroredMortar(_ state: MortarSnapshot) -> MortarShell {
        let shell = MortarShell(from: state.start.cgPoint, to: state.target.cgPoint)
        shell.netID = state.id
        worldNode.addChild(shell.marker)
        worldNode.addChild(shell)
        guestWorld?.mortars[state.id] = shell
        return shell
    }
}
```

- [ ] **Step 7: The developer quick match**

Create `Sources/TanksOfDoom/QuickMatch.swift`:

```swift
import AppKit
import SpriteKit
import TanksCore
import TanksNet

/// Developer shortcut for networked matches without the lobby.
/// TANKS_HOST=1 creates a room (code printed to the terminal) and starts when someone joins;
/// TANKS_JOIN=<code> joins it. Both use TANKS_RELAY_URL or the default relay.
enum QuickMatch {
    static func start(in view: SKView) -> Bool {
        let env = ProcessInfo.processInfo.environment
        let joinCode = env["TANKS_JOIN"]
        guard env["TANKS_HOST"] == "1" || joinCode != nil else { return false }

        let connection = RelayConnection()
        // The closure keeps the connection alive until a scene takes it over.
        connection.onEvent = { [unowned view] event in
            switch event {
            case .relay(.roomCreated(let code)):
                print("Room code: \(code)")
            case .relay(.joined):
                let link = MatchLink(connection: connection)
                if joinCode == nil {
                    let settings = MatchSettings(seed: .random(in: 0...UInt64.max))
                    link.send(.matchStart(settings))
                    print("Match started as host")
                    view.presentScene(GameScene(size: view.bounds.size, versus: settings, role: .host(link)))
                } else {
                    link.onMessage = { message in
                        guard case .matchStart(let settings) = message else { return }
                        print("Match started as guest")
                        view.presentScene(GameScene(size: view.bounds.size, versus: settings, role: .guest(link)))
                    }
                }
            case .relay(.error(let code)):
                print("Relay error: \(code.message)")
            case .closed(let reason):
                print("Connection closed: \(reason ?? "")")
            default:
                break
            }
        }
        connection.open()
        if let joinCode {
            connection.send(relay: .joinRoom(code: joinCode))
        } else {
            connection.send(relay: .createRoom)
        }
        view.presentScene(MenuScene(size: view.bounds.size,
                                    lines: [MenuScene.Line(text: "QUICK MATCH", size: 64),
                                            MenuScene.Line(text: "See the terminal for the room code.", size: 22)],
                                    prompt: "WAITING FOR THE OTHER PLAYER…") { _ in })
        return true
    }
}
```

In `AppDelegate.swift`, add a branch before the final `else`:

```swift
        } else if QuickMatch.start(in: view) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
```

- [ ] **Step 8: Build and test**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`, then the **Launch check** from Phase B.
Expected: `Build complete!`, all tests pass, `still running after 8 s: OK`.

- [ ] **Step 9: Scripted two-instance smoke test**

```bash
swift build 2>&1 | tail -1
LOG=$(mktemp -d)
.build/debug/TanksRelay > "$LOG/relay.log" 2>&1 & RELAY=$!
sleep 2
TANKS_RELAY_URL=ws://localhost:8080/ws TANKS_HOST=1 .build/debug/TanksOfDoom > "$LOG/host.log" 2>&1 & HOST=$!
sleep 3
CODE=$(grep -o "Room code: [A-Z]*" "$LOG/host.log" | awk '{print $3}')
echo "room $CODE"
TANKS_RELAY_URL=ws://localhost:8080/ws TANKS_JOIN=$CODE .build/debug/TanksOfDoom > "$LOG/guest.log" 2>&1 & GUEST=$!
sleep 15
kill -0 $HOST && kill -0 $GUEST && echo "both games still running"
cat "$LOG/host.log" "$LOG/guest.log"
kill $HOST $GUEST $RELAY
```

Expected: `room XXXXX`, `both games still running`, and the logs contain `Match started as host` and `Match started as guest` with no `Connection closed`.

- [ ] **Step 10: Manual networked check**

Run the relay and two games as in Step 9 (or on two Macs with `TANKS_RELAY_URL=ws://<relay-mac-ip>:8080/ws`) and confirm:
- Both games show 3-2-1-GO. The host is olive at bottom-left and the guest blue at top-right.
- The guest drives with W/A/S/D. Its tank responds with a short delay (prediction comes in Task 13), and the host sees it move.
- AI tanks, soldiers, shots, mortars, explosions, building damage and collapse, pickups and the kill feed all appear on both screens.
- Each player's own hits shake only their own screen. The latency (`NN ms`) shows bottom-left.
- When the guest dies they see their respawn countdown, then reappear blinking.
- Quitting one game (Cmd-Q): the other shows "OPPONENT LEFT" and VICTORY.

- [ ] **Step 11: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): networked versus with host snapshots, guest mirroring and a quick-match shortcut

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Guest prediction, reconciliation and instant fire feedback

**Files:**
- Modify: `Sources/TanksOfDoom/GuestWorld.swift`, `GameScene+Guest.swift`, `GameScene+Combat.swift`

**Interfaces:**
- Consumes: `InputHistory` (Task 8); `drive(_:with:dt:blockers:)` (Task 4); `GuestWorld` (Task 12).
- Produces: `GuestWorld.history`, `correction`, `mainCooldown`, `machineGunCooldown`, constants `correctionTime = 0.1`, `ignoreDistance = 2`, `snapDistance = 64`.

- [ ] **Step 1: Prediction state**

In `GuestWorld.swift`, add `import CoreGraphics` and these members to `GuestWorld`:

```swift
    static let correctionTime = 0.1
    static let ignoreDistance: CGFloat = 2
    static let snapDistance: CGFloat = 64

    /// Local inputs the host hasn't confirmed, for replay after each snapshot.
    var history = InputHistory<InputState>()
    /// What's left of the last correction, eased in over `correctionTime`.
    var correction = CGPoint.zero
    /// Local stand-ins for the guns' reload, so firing looks and sounds instant.
    var mainCooldown = 0.0
    var machineGunCooldown = 0.0
```

- [ ] **Step 2: Predict, reconcile, and play our own shots at once**

In `GameScene+Guest.swift`:

Replace `updateGuest(dt:)` with:

```swift
    func updateGuest(dt: Double) {
        guard let world = guestWorld else { return }
        predictOwnTank(dt: dt)
        predictOwnFireFX(dt: dt)
        sendInput(dt: dt)
        guard let frame = world.buffer.frame(at: lastUpdate) else { return }
        for state in frame.to.players {
            let from = frame.from.players.first { $0.slot == state.slot } ?? state
            mirror(player(state.slot), from: from, to: state, t: frame.t)
        }
        mirrorEnemies(frame)
        mirrorSoldiers(frame)
        mirrorShots(frame, dt: dt)
        mirrorMortars(frame)
    }
```

In `receiveSnapshot(_:)`, replace the last line with:

```swift
        if let mine = snapshot.players.first(where: { $0.slot == localPlayer.slot }) {
            applyOwnState(mine)
            reconcile(with: mine, acknowledged: snapshot.ackInputSeq)
        }
```

In `mirror(_:from:to:t:)`, replace the six lines from `let from = a.has(PlayerSnapshot.respawning) ? b : a` through `leaveTracks(tank, moved: tank.position.distance(to: before))` with:

```swift
        if player === localPlayer {
            // Our own hull is predicted; the turret is aimed by the host, so follow its newest angle.
            if let latest = guestWorld?.buffer.latest?.players.first(where: { $0.slot == player.slot }) {
                tank.turretAngle = CGFloat(lerpAngle(Float(tank.turretAngle), latest.turret, 0.5))
            }
        } else {
            let from = a.has(PlayerSnapshot.respawning) ? b : a   // don't slide from where it died
            let before = tank.position
            tank.position = from.position.lerp(to: b.position, t).cgPoint
            tank.heading = CGFloat(lerpAngle(from.heading, b.heading, t))
            tank.turretAngle = CGFloat(lerpAngle(from.turret, b.turret, t))
            leaveTracks(tank, moved: tank.position.distance(to: before))
        }
```

Add these methods to the extension:

```swift
    /// Drives our own tank immediately from local keys, and eases in any pending correction.
    private func predictOwnTank(dt: Double) {
        guard let world = guestWorld else { return }
        let tank = localPlayer.tank
        guard !tank.isHidden, !tank.isDestroyed else { return }
        let drove = drive(tank, with: localPlayer.input, dt: dt, blockers: allTanks)
        if drove.distance > 0 { leaveTracks(tank, moved: drove.distance) }
        // These keys reach the host in the next input frame, numbered inputSeq + 1.
        world.history.record(seq: world.inputSeq + 1, input: localPlayer.input, dt: dt)
        let step = world.correction * CGFloat(min(1, dt / GuestWorld.correctionTime))
        tank.position = tank.position + step
        world.correction = world.correction - step
    }

    /// Re-runs unconfirmed inputs from the host's position. Small errors are eased in, big ones snap.
    private func reconcile(with mine: PlayerSnapshot, acknowledged seq: UInt32) {
        guard let world = guestWorld else { return }
        let tank = localPlayer.tank
        world.history.acknowledge(through: seq)
        guard !tank.isHidden, !mine.has(PlayerSnapshot.respawning) else {
            world.correction = .zero
            return
        }
        let shown = tank.position
        let shownHeading = tank.heading
        tank.position = mine.position.cgPoint
        tank.heading = CGFloat(mine.heading)
        for entry in world.history.entries {
            _ = drive(tank, with: entry.input, dt: entry.dt, blockers: allTanks)
        }
        let error = tank.position - shown
        if error.length > GuestWorld.snapDistance {
            world.correction = .zero   // too far off: stay where the host says
            return
        }
        tank.position = shown
        if abs(normalizeAngle(tank.heading - shownHeading)) < 0.02 { tank.heading = shownHeading }
        world.correction = error.length < GuestWorld.ignoreDistance ? .zero : error
    }

    /// Muzzle flash, sound and kick for our own shots straight away. The host leaves these out for us.
    private func predictOwnFireFX(dt: Double) {
        guard let world = guestWorld else { return }
        let tank = localPlayer.tank
        let input = localPlayer.input
        world.mainCooldown -= dt
        world.machineGunCooldown -= dt
        guard !tank.isHidden, !tank.isDestroyed else { return }
        if input.firePrimary && world.mainCooldown <= 0 && tank.stats.shells > 0 {
            world.mainCooldown = Combat.spec(.mainGun).reload
            playLocally(.muzzleFlash(at: tank.muzzlePosition.vec, angle: Float(tank.turretAngle), big: true))
            playLocally(.sound(.cannon, at: tank.position.vec, volume: 1))
            shake(4, duration: 0.15)
        }
        if input.fireSecondary && world.machineGunCooldown <= 0 && tank.stats.rounds > 0 {
            world.machineGunCooldown = Combat.spec(.machineGun).reload
            let origin = tank.position + CGPoint(angle: tank.turretAngle, length: 30)
            playLocally(.muzzleFlash(at: origin.vec, angle: Float(tank.turretAngle), big: false))
            playLocally(.sound(.machineGun, at: origin.vec, volume: 0.5))
        }
    }
```

- [ ] **Step 3: Host stops sending the guest their own fire effects**

In `GameScene+Combat.swift`, in `fire(_:from:angle:shooter:ownerBuilding:)`, add before the `switch weapon`:

```swift
        // A guest plays their own muzzle flashes and gun sounds the moment they fire.
        let audience: Audience = remotePlayer.map { remote -> Audience in
            shooter == .player(remote.slot) ? .allBut(remote) : .everyone
        } ?? .everyone
```

and pass `for: audience` to each `fx(...)` call inside that `switch`.

In `updateWeapons(for:dt:)`, replace `fx(.shake(magnitude: 4, duration: 0.15), for: .only(player))` with:

```swift
                if player !== remotePlayer { fx(.shake(magnitude: 4, duration: 0.15), for: .only(player)) }
```

- [ ] **Step 4: Build, test, smoke test**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`, then repeat Task 12 Step 9.
Expected: `Build complete!`, all tests pass, `both games still running`.

- [ ] **Step 5: Manual feel check under bad network conditions**

Install Apple's **Network Link Conditioner** (Additional Tools for Xcode). Set a custom profile with 100 ms delay and 1% packet loss, run a relay and two games on one Mac as in Task 12 Step 9, and confirm on the guest:
- Driving and turning respond instantly. There's no visible rubber-banding when driving straight or sliding along walls, and only small smooth corrections when bumping into the host's tank or AI tanks.
- Pressing Space flashes and sounds at once. The shell appears about RTT/2 later and leaves from where the barrel points.
- The host's tank, AI and projectiles move smoothly (100 ms behind, no stutter).
- Turning the Network Link Conditioner to 100% loss for 4 s shows "CONNECTION LOST…". Turning it off again recovers. More than 10 s ends the match in favour of the player who is still there.

- [ ] **Step 6: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): guest-side movement prediction with reconciliation and instant fire feedback

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase F: Menus, lobby and wrap-up

### Task 14: Title menu, multiplayer menu and lobby

**Files:**
- Create: `Sources/TanksOfDoom/LobbyScene.swift`
- Modify: `Sources/TanksOfDoom/MenuScene.swift`

**Interfaces:**
- Consumes: `RelayConnection`, `MatchLink` (Task 12); `MatchSettings` (Task 2); `TanksNet.normalizeRoomCode` (Task 7); `GameScene(size:versus:role:)`.
- Produces:
  - `MenuScene.init(size:lines:prompt:shortcuts:onContinue:)`, where `shortcuts: [UInt16: (MenuScene) -> Void]` defaults to `[:]`
  - `MenuScene.multiplayer(size:) -> MenuScene`
  - `final class LobbyScene: SKScene { enum Role { case host, guest }; init(size:role:) }`

- [ ] **Step 1: Menu shortcuts and the two menus**

In `MenuScene.swift`:

Add a stored property below `private let onContinue`:

```swift
    private let shortcuts: [UInt16: (MenuScene) -> Void]
```

Replace the initializer with:

```swift
    init(size: CGSize, lines: [Line], prompt: String, shortcuts: [UInt16: (MenuScene) -> Void] = [:],
         onContinue: @escaping (MenuScene) -> Void) {
        self.lines = lines
        self.prompt = prompt
        self.shortcuts = shortcuts
        self.onContinue = onContinue
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.06, alpha: 1)
    }
```

Replace `keyDown(with:)` with:

```swift
    override func keyDown(with event: NSEvent) {
        if let action = shortcuts[event.keyCode] {
            guard acceptsInput else { return }
            acceptsInput = false
            action(self)
        } else if [36, 76, 49].contains(event.keyCode) {   // Return, keypad Enter, Space
            proceed()
        }
    }
```

In `title(size:)`, replace the `return MenuScene(...)` statement with:

```swift
        let startCampaign: (MenuScene) -> Void = { scene in
            let game = GameScene(size: scene.size, levelNumber: 1, runStats: RunStats())
            scene.view?.presentScene(game, transition: .fade(withDuration: 0.6))
        }
        return MenuScene(size: size, lines: lines, prompt: "ENTER  CAMPAIGN  ·  2  MULTIPLAYER",
                         shortcuts: [
                             18: startCampaign,   // 1
                             19: { scene in scene.view?.presentScene(MenuScene.multiplayer(size: scene.size), transition: .fade(withDuration: 0.4)) },   // 2
                         ],
                         onContinue: startCampaign)
```

Add at the end of the file:

```swift
extension MenuScene {
    static func multiplayer(size: CGSize) -> MenuScene {
        let mono = "Menlo-Bold"
        let lines = [
            Line(text: "MULTIPLAYER", size: 72, color: NSColor(calibratedRed: 0.9, green: 0.3, blue: 0.15, alpha: 1)),
            Line(text: "Two players, two Macs, one city. Take all of the other's lives.", size: 22),
            Line(text: " ", size: 10),
            Line(text: "H  Host a match and get a room code", size: 20, color: .lightGray, font: mono),
            Line(text: "J  Join a match with a code", size: 20, color: .lightGray, font: mono),
            Line(text: "ESC  Back", size: 20, color: .lightGray, font: mono),
        ]
        return MenuScene(size: size, lines: lines, prompt: "H  HOST  ·  J  JOIN",
                         shortcuts: [
                             4: { $0.view?.presentScene(LobbyScene(size: $0.size, role: .host), transition: .fade(withDuration: 0.4)) },    // H
                             38: { $0.view?.presentScene(LobbyScene(size: $0.size, role: .guest), transition: .fade(withDuration: 0.4)) },  // J
                             53: { $0.view?.presentScene(MenuScene.title(size: $0.size), transition: .fade(withDuration: 0.4)) },           // Esc
                         ],
                         onContinue: { $0.view?.presentScene(LobbyScene(size: $0.size, role: .host), transition: .fade(withDuration: 0.4)) })
    }
}
```

- [ ] **Step 2: The lobby**

Create `Sources/TanksOfDoom/LobbyScene.swift`:

```swift
import AppKit
import SpriteKit
import TanksCore
import TanksNet

/// Host: connect, show the room code, choose lives and AI, start once the guest is ready.
/// Guest: type the code, then wait (toggling ready) until the host starts.
final class LobbyScene: SKScene {
    enum Role { case host, guest }

    private enum Phase {
        case enteringCode(typed: String, problem: String?)
        case connecting
        case waitingForGuest
        case paired
        case failed(String)
    }

    private let role: Role
    private var phase: Phase
    private var connection: RelayConnection?
    private var link: MatchLink?
    private var roomCode: String?
    private var settings = MatchSettings()
    private var guestReady = false

    init(size: CGSize, role: Role) {
        self.role = role
        phase = role == .host ? .connecting : .enteringCode(typed: "", problem: nil)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.06, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        if role == .host { connect(joining: nil) }
        render()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        render()
    }

    // MARK: Networking

    private func connect(joining code: String?) {
        let connection = RelayConnection()
        self.connection = connection
        connection.onEvent = { [weak self] event in self?.handle(event) }
        connection.open()
        if let code {
            connection.send(relay: .joinRoom(code: code))
        } else {
            connection.send(relay: .createRoom)
        }
        phase = .connecting
    }

    private func handle(_ event: RelayConnection.Event) {
        switch event {
        case .relay(.roomCreated(let code)):
            roomCode = code
            phase = .waitingForGuest
        case .relay(.joined):
            guard let connection else { return }
            let link = MatchLink(connection: connection)
            link.onMessage = { [weak self] message in self?.receive(message) }
            link.onClosed = { [weak self] reason in self?.fail(reason ?? "Connection lost") }
            self.link = link
            phase = .paired
            if role == .host { link.send(.lobby(settings)) }
        case .relay(.error(let code)):
            fail(code.message)
        case .closed(let reason):
            fail(reason ?? "Can't reach server")
        default:
            break
        }
        render()
    }

    private func receive(_ message: GameMessage) {
        switch message {
        case .lobby(let hostSettings): settings = hostSettings
        case .guestReady(let ready): guestReady = ready
        case .matchStart(let matchSettings): startMatch(matchSettings)
        case .leave: fail("Opponent left")
        default: break
        }
        render()
    }

    private func fail(_ reason: String) {
        connection?.close()
        link = nil
        guestReady = false
        phase = .failed(reason)
        render()
    }

    private func startMatch(_ matchSettings: MatchSettings) {
        guard let link, let view else { return }
        let role: VersusRole = self.role == .host ? .host(link) : .guest(link)
        view.presentScene(GameScene(size: size, versus: matchSettings, role: role), transition: .fade(withDuration: 0.6))
    }

    private func leave() {
        link?.send(.leave)
        connection?.close()
        view?.presentScene(MenuScene.multiplayer(size: size), transition: .fade(withDuration: 0.4))
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let code = event.keyCode
        let enter = code == 36 || code == 76
        if code == 53 { return leave() }   // Esc
        switch phase {
        case .enteringCode(let typed, _):
            if enter {
                if let normalized = TanksNet.normalizeRoomCode(typed) {
                    connect(joining: normalized)
                } else {
                    phase = .enteringCode(typed: typed, problem: "Codes are 5 letters (no I or O)")
                }
            } else if code == 51 {   // Delete
                phase = .enteringCode(typed: String(typed.dropLast()), problem: nil)
            } else if let letters = event.charactersIgnoringModifiers?.uppercased().filter(\.isLetter), !letters.isEmpty,
                      typed.count < TanksNet.roomCodeLength {
                phase = .enteringCode(typed: typed + String(letters.prefix(TanksNet.roomCodeLength - typed.count)), problem: nil)
            }
        case .waitingForGuest, .paired:
            guard role == .host else {
                if enter, let link {   // guest toggles ready
                    guestReady.toggle()
                    link.send(.guestReady(guestReady))
                }
                break
            }
            switch code {
            case 123: settings.changeLives(by: -1)       // ←
            case 124: settings.changeLives(by: 1)        // →
            case 125: settings.changeIntensity(by: 1)    // ↓
            case 126: settings.changeIntensity(by: -1)   // ↑
            case 36, 76:
                guard let link, guestReady else { break }
                settings.seed = .random(in: 0...UInt64.max)
                link.send(.matchStart(settings))
                startMatch(settings)
                return
            default: break
            }
            link?.send(.lobby(settings))
        case .failed:
            if enter { leave() }
        case .connecting:
            break
        }
        render()
    }

    // MARK: Drawing

    private func render() {
        removeAllChildren()
        let mono = "Menlo-Bold"
        var lines: [(String, CGFloat, NSColor, String)] = []
        func line(_ text: String, _ size: CGFloat, _ color: NSColor = .white, _ font: String = "Impact") {
            lines.append((text, size, color, font))
        }
        let title = role == .host ? "HOST A MATCH" : "JOIN A MATCH"
        line(title, 64, NSColor(calibratedRed: 0.9, green: 0.3, blue: 0.15, alpha: 1))
        var prompt = "ESC  BACK"

        switch phase {
        case .enteringCode(let typed, let problem):
            line("Type the room code your opponent gave you:", 22)
            line(spaced(typed.padding(toLength: TanksNet.roomCodeLength, withPad: "_", startingAt: 0)), 72, .systemYellow, mono)
            line(problem ?? " ", 20, .systemRed, mono)
            prompt = "ENTER  JOIN  ·  ESC  BACK"
        case .connecting:
            line("Connecting…", 28, .lightGray)
        case .waitingForGuest, .paired:
            if let roomCode {
                line("ROOM CODE", 20, .lightGray, mono)
                line(spaced(roomCode), 72, .systemYellow, mono)
            }
            let canEdit = role == .host
            line("Lives:  \(canEdit ? "◀ " : "")\(settings.lives)\(canEdit ? " ▶" : "")", 26, .white, mono)
            line("AI:  \(canEdit ? "▲ " : "")\(settings.aiIntensity.name)\(canEdit ? " ▼" : "")", 26, .white, mono)
            line(" ", 10)
            switch (phase, role) {
            case (.waitingForGuest, _):
                line("Tell your opponent the code. Waiting for them to join…", 22, .lightGray)
                prompt = "←/→  LIVES  ·  ↑/↓  AI  ·  ESC  CANCEL"
            case (_, .host):
                line(guestReady ? "Opponent is READY" : "Opponent joined, not ready yet", 24, guestReady ? .systemGreen : .systemOrange)
                prompt = guestReady ? "ENTER  START  ·  ESC  LEAVE" : "←/→  LIVES  ·  ↑/↓  AI  ·  ESC  LEAVE"
            default:
                line(guestReady ? "You are READY. Waiting for the host to start…" : "Press Enter when you're ready", 24,
                     guestReady ? .systemGreen : .systemOrange)
                prompt = "ENTER  \(guestReady ? "NOT READY" : "READY")  ·  ESC  LEAVE"
            }
        case .failed(let reason):
            line(reason, 30, .systemRed)
            prompt = "ENTER / ESC  BACK"
        }

        let spacing: CGFloat = 1.5
        let total = lines.reduce(CGFloat(0)) { $0 + $1.1 * spacing } + 70
        var y = size.height / 2 + total / 2
        for (text, fontSize, color, font) in lines {
            y -= fontSize * spacing / 2
            let label = SKLabelNode.make(text, size: fontSize, color: color, font: font)
            label.position = CGPoint(x: size.width / 2, y: y)
            addChild(label)
            y -= fontSize * spacing / 2
        }
        let promptLabel = SKLabelNode.make(prompt, size: 24, color: .systemYellow)
        promptLabel.position = CGPoint(x: size.width / 2, y: y - 60)
        addChild(promptLabel)
    }

    private func spaced(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }
}
```

- [ ] **Step 3: Build, test, launch check**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`, then the **Launch check**.
Expected: `Build complete!`, all tests pass, `still running after 8 s: OK`.

- [ ] **Step 4: Manual lobby check**

With a local relay running (`swift run TanksRelay`) and two games (`TANKS_RELAY_URL=ws://localhost:8080/ws swift run TanksOfDoom`):
- Title: Enter or 1 still starts the campaign. 2 opens MULTIPLAYER, and Esc goes back.
- Game A: H shows "Connecting…", then a big room code. ←/→ changes lives within 1–9 and ↑/↓ cycles LIGHT/NORMAL/HEAVY.
- Game B: J, then typing the code in lower case, with a typo, then Delete and Enter. Six letters are refused. "I" or "O" shows the hint. A wrong-but-valid code shows "Room not found".
- B joins: A shows "Opponent joined, not ready yet". B sees A's settings, which update live when A changes them.
- B presses Enter: A shows READY. A presses Enter: both go into the match with 3-2-1 and the chosen lives and AI.
- Esc in either lobby returns the other side to "Opponent left".
- With the relay stopped, Host shows "Can't reach server".

- [ ] **Step 5: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): multiplayer menu and lobby with room codes, settings and ready-up

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Leave prompt, result screen and rematch

**Files:**
- Create: `Sources/TanksOfDoom/VersusResultScene.swift`
- Modify: `Sources/TanksOfDoom/GameScene.swift`, `GameScene+Input.swift`, `GameScene+Host.swift`, `GameScene+Flow.swift`, `HUD.swift`

**Interfaces:**
- Consumes: `MatchLink` (Task 12), `VersusResult` (Task 5), `GameScene(size:versus:role:)`.
- Produces:
  - `final class VersusResultScene: SKScene { init(size:result:link:settings:isHost:opponentWantsRematch:opponentLeft:) }`
  - `HUD.setLeavePrompt(_:)`; `GameScene.leavePromptShown`, `opponentRequestedRematch`, `opponentLeft`, `leaveMatch()`

- [ ] **Step 1: Leave prompt on the HUD**

In `HUD.swift`, add a property below `pausedLabel`:

```swift
    private let leaveLabel = SKLabelNode.make("LEAVE MATCH?  Y / N", size: 48, color: .systemOrange)
```

In `init(level:versus:)`, add before the `for node in [...]` loop:

```swift
        leaveLabel.zPosition = 7
        leaveLabel.isHidden = true
```

and add `leaveLabel` to that loop's array. In `layout(size:)`, add `leaveLabel.position = .zero`. Add:

```swift
    func setLeavePrompt(_ shown: Bool) {
        leaveLabel.isHidden = !shown
    }
```

- [ ] **Step 2: Scene state and keys**

In `GameScene.swift`, add these stored properties below `var matchWinner`:

```swift
    var leavePromptShown = false
    /// Messages that can arrive while the match is ending, handed on to the result screen.
    var opponentRequestedRematch = false
    var opponentLeft = false
```

In `GameScene+Host.swift`:
- in `receive(_:)`, add the case `case .rematch: opponentRequestedRematch = true`
- at the start of `linkClosed(_:)`, before the `guard`, add `opponentLeft = true`

In `GameScene+Input.swift`, in `handleKeyPress(_:)`, replace `case 53: togglePause()` with:

```swift
        case 53:                                       // Esc
            if versusRole?.link != nil {
                leavePromptShown.toggle()
                hud.setLeavePrompt(leavePromptShown)
            } else {
                togglePause()
            }
        case 16 where leavePromptShown: leaveMatch()   // Y
        case 45 where leavePromptShown:                // N
            leavePromptShown = false
            hud.setLeavePrompt(false)
```

In `GameScene+Flow.swift`, add:

```swift
    /// Quit a networked match from the leave prompt; the opponent is told and wins.
    func leaveMatch() {
        guard let link = versusRole?.link, let view else { return }
        link.send(.leave)
        link.close()
        levelOver = true
        view.presentScene(MenuScene.title(size: size), transition: .fade(withDuration: 0.6))
    }
```

and in `finishLevel()`, replace the `if isVersus { ... }` block with:

```swift
        if isVersus {
            if let link = versusRole?.link {
                let result = VersusResultScene(size: size, result: versusResult(), link: link,
                                               settings: match?.settings ?? MatchSettings(), isHost: versusRole?.isHost == true,
                                               opponentWantsRematch: opponentRequestedRematch, opponentLeft: opponentLeft)
                view.presentScene(result, transition: .fade(withDuration: 0.8))
            } else {
                view.presentScene(MenuScene.versusResult(size: size, result: versusResult()), transition: .fade(withDuration: 0.8))
            }
            return
        }
```

- [ ] **Step 3: The result scene**

Create `Sources/TanksOfDoom/VersusResultScene.swift`:

```swift
import AppKit
import SpriteKit
import TanksCore
import TanksNet

/// End of a networked match. R asks for a rematch (both must ask; the host then starts a new city
/// with the same settings), Esc or Enter leaves.
final class VersusResultScene: SKScene {
    private let result: VersusResult
    private let link: MatchLink
    private let settings: MatchSettings
    private let isHost: Bool
    private var wantsRematch = false
    private var opponentWantsRematch: Bool
    private var opponentLeft: Bool

    init(size: CGSize, result: VersusResult, link: MatchLink, settings: MatchSettings, isHost: Bool,
         opponentWantsRematch: Bool, opponentLeft: Bool) {
        self.result = result
        self.link = link
        self.settings = settings
        self.isHost = isHost
        self.opponentWantsRematch = opponentWantsRematch
        self.opponentLeft = opponentLeft
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.06, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        link.onMessage = { [weak self] message in self?.receive(message) }
        link.onClosed = { [weak self] _ in
            self?.opponentLeft = true
            self?.render()
        }
        render()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        render()
    }

    private func receive(_ message: GameMessage) {
        switch message {
        case .rematch:
            opponentWantsRematch = true
            startIfBothWant()
        case .matchStart(let next) where !isHost:
            view?.presentScene(GameScene(size: size, versus: next, role: .guest(link)), transition: .fade(withDuration: 0.6))
            return
        case .leave:
            opponentLeft = true
        default:
            break
        }
        render()
    }

    private func startIfBothWant() {
        guard isHost, wantsRematch, opponentWantsRematch, !opponentLeft, let view else { return }
        var next = settings
        next.seed = .random(in: 0...UInt64.max)
        link.send(.matchStart(next))
        view.presentScene(GameScene(size: size, versus: next, role: .host(link)), transition: .fade(withDuration: 0.6))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 15 where !opponentLeft && !wantsRematch:   // R
            wantsRematch = true
            link.send(.rematch)
            startIfBothWant()
        case 53, 36, 76:                                // Esc, Return, keypad Enter
            link.send(.leave)
            link.close()
            view?.presentScene(MenuScene.title(size: size), transition: .fade(withDuration: 0.6))
            return
        default:
            break
        }
        render()
    }

    private func render() {
        removeAllChildren()
        let mono = "Menlo-Bold"
        let me = result.localSlot
        let them = me.opponent
        let won = result.winner == me
        var lines: [(String, CGFloat, NSColor, String)] = [
            (won ? "VICTORY" : "DEFEAT", 88, won ? .systemGreen : .systemRed, "Impact"),
            ("You: \(result.lives[me] ?? 0) lives left, \(result.kills[me] ?? 0) kills", 22, me.color, mono),
            ("Opponent: \(result.lives[them] ?? 0) lives left, \(result.kills[them] ?? 0) kills", 22, them.color, mono),
            (" ", 12, .white, mono),
        ]
        let status: String
        if opponentLeft {
            status = "Opponent left"
        } else if wantsRematch {
            status = opponentWantsRematch ? "Starting…" : "Waiting for opponent…"
        } else {
            status = opponentWantsRematch ? "Opponent wants a rematch!" : " "
        }
        lines.append((status, 24, opponentLeft ? .systemOrange : .lightGray, "Impact"))

        let spacing: CGFloat = 1.5
        let total = lines.reduce(CGFloat(0)) { $0 + $1.1 * spacing } + 70
        var y = size.height / 2 + total / 2
        for (text, fontSize, color, font) in lines {
            y -= fontSize * spacing / 2
            let label = SKLabelNode.make(text, size: fontSize, color: color, font: font)
            label.position = CGPoint(x: size.width / 2, y: y)
            addChild(label)
            y -= fontSize * spacing / 2
        }
        let prompt = opponentLeft || wantsRematch ? "ESC  MENU" : "R  REMATCH  ·  ESC  MENU"
        let promptLabel = SKLabelNode.make(prompt, size: 28, color: .systemYellow)
        promptLabel.position = CGPoint(x: size.width / 2, y: y - 60)
        addChild(promptLabel)
    }
}
```

- [ ] **Step 4: Build, test, smoke test**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3`, the **Launch check**, then Task 12 Step 9.
Expected: all pass; `both games still running`.

- [ ] **Step 5: Manual check**

Using the lobby (Task 14) with a local relay and two games, play a match with 1 life:
- Esc during the match shows "LEAVE MATCH? Y / N" without pausing. N hides it. Y returns to the title, and the other player sees "OPPONENT LEFT", then VICTORY and "Opponent left" on the result screen.
- At the end, both see VICTORY/DEFEAT with lives and kills. One presses R ("Waiting for opponent…"), and the other sees "Opponent wants a rematch!" and presses R. Both start a fresh city with the same lives and AI and a 3-2-1.
- Pressing R very quickly on the host while the guest's DEFEAT banner is still up still results in a rematch.
- Esc on the result screen returns to the title. The other side shows "Opponent left" and only offers ESC.

- [ ] **Step 6: Commit**

```bash
git add Sources/TanksOfDoom
git commit -m "feat(app): leave prompt, networked result screen and rematch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: README, relay deployment and final verification

**Files:**
- Modify: `README.md`, `Sources/TanksOfDoom/RelayConnection.swift` (`RelayConfig.defaultURL`), `Sources/TanksOfDoom/MenuScene.swift` (title help lines)

**Interfaces:**
- Consumes: everything above.
- Produces: user-facing documentation and a release-ready relay URL.

- [ ] **Step 1: Ask for the relay's public address**

Ask your human partner: *"Where will the relay run? I need its public `wss://…/ws` URL (see docs/relay.md for setting one up)."* Don't invent a domain. If they don't have one yet, leave `RelayConfig.defaultURL` as `ws://localhost:8080/ws`, finish the remaining steps, and say clearly in your report that releases can't play online until it's set.

When you have the URL, set it in `Sources/TanksOfDoom/RelayConnection.swift`:

```swift
    static let defaultURL = "wss://<the address they gave you>/ws"
```

- [ ] **Step 2: Title screen help**

In `MenuScene.title(size:)`, insert this line after the "ESC pause · M minimap size…" line:

```swift
            Line(text: "Press 2 for online MULTIPLAYER against a friend", size: 17, color: .systemYellow, font: mono),
```

- [ ] **Step 3: README**

In `README.md`, add this section after "## Controls" and its table:

````markdown
## Multiplayer

Two players on two Macs fight it out in the same city, with the Rust Brigade still roaming and the
snipers still in their windows. Each player starts with the same number of lives. Every death costs
one, whether your opponent got you or a librarian with a bazooka did. You respawn somewhere random
after three seconds, blinking and untouchable until you fire or three more seconds pass. Take all of
your opponent's lives to win.

1. Press **2** on the title screen.
2. One player presses **H** to host and reads out the five-letter room code. The host picks the
   number of lives (←/→) and how much AI joins in (↑/↓).
3. The other player presses **J**, types the code and presses **Enter**, then **Enter** again when
   ready.
4. The host presses **Enter** to start.

Each player has their own base (olive bottom-left for the host, blue top-right for the guest) and can
only repair there. In a match, **Esc** offers to leave instead of pausing. After the match, both
pressing **R** starts a rematch in a new city.

Matches go through a small relay server (see [docs/relay.md](docs/relay.md)). To play against
yourself locally:

```bash
swift run TanksRelay                                          # terminal 1
TANKS_RELAY_URL=ws://localhost:8080/ws swift run TanksOfDoom   # terminals 2 and 3
```
````

Also add this row to the "Other useful commands" block:

```bash
swift run TanksRelay         # run the multiplayer relay server locally
```

- [ ] **Step 4: Full verification**

Run:

```bash
swift build 2>&1 | tail -1
swift build -c release --product TanksOfDoom 2>&1 | tail -1
swift build -c release --product TanksRelay 2>&1 | tail -1
swift test 2>&1 | tail -3
```

Expected: four `Build complete!`/pass results; the test summary lists TanksCoreTests, TanksNetTests and TanksRelayCoreTests with 0 failures.

Then repeat the Phase B **Launch check** and Task 12 Step 9's two-instance smoke test.

If Docker is available, also run:

```bash
docker build -t tanks-relay . && docker run --rm -d -p 8098:8080 --name tanks-relay-check tanks-relay && sleep 3 && \
  docker logs tanks-relay-check && docker rm -f tanks-relay-check
```

Expected: `TanksRelay listening on ws://0.0.0.0:8080/ws (protocol 1)`.

- [ ] **Step 5: Manual end-to-end over the internet**

Once the relay is deployed (docs/relay.md), build the release app (`scripts/package-app.sh 0.2.0-test`). Play a full match between two Macs on different networks: a phone hotspot for one is fine. Go through the checks from Tasks 12–15, and finish with a campaign level to confirm single-player is untouched.

- [ ] **Step 6: Commit**

```bash
git add README.md Sources/TanksOfDoom/RelayConnection.swift Sources/TanksOfDoom/MenuScene.swift
git commit -m "docs: multiplayer instructions; point the game at the deployed relay

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
