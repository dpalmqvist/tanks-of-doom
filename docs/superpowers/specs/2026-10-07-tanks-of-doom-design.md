# Tanks of Doom — Design Spec

Date: 2026-10-07

## Goal

A native macOS 2D top-down shooter written in Swift. The player drives a tank
through a procedurally generated, war-torn city, hunting roaming enemy tanks
while infantry hidden in buildings fire on them. Fuel and ammo are scarce and
hidden around the map; a home base repairs and resupplies the tank. Each level
is cleared by destroying all enemy tanks; levels continue indefinitely with
increasing difficulty.

### Success criteria

- `swift run TanksOfDoom` launches a playable game window on macOS.
- Every level is procedurally generated from a seed and is always completable
  (all roads, caches and enemy tanks reachable from the home base).
- All mechanics below are present and playable: driving, fuel, both weapons,
  pickups, home-base repair, infantry in buildings, destructible buildings,
  roaming enemy tanks, win/lose and level progression.
- `swift test` passes for the core logic.

## Technology

- Swift 6, SpriteKit, AppKit. Swift Package Manager only — no Xcode project.
- Target: macOS 14+ on Apple Silicon/Intel.
- All graphics are generated in code (shapes / textures rendered at launch);
  all sounds are synthesized in code. No external asset files required.

## Architecture

Swift package with three targets:

| Target | Kind | Depends on | Responsibility |
|---|---|---|---|
| `TanksCore` | library | Foundation only | Pure game logic: seeded RNG, tile map model, city generator, A* pathfinding, line of sight, combat/fuel/ammo rules, AI decision logic, difficulty scaling. No SpriteKit. |
| `TanksOfDoom` | executable | `TanksCore`, SpriteKit, AppKit | App window, scenes, nodes, input, HUD, effects, audio. |
| `TanksCoreTests` | test | `TanksCore` | Unit tests for core logic. |

The SpriteKit layer owns presentation and physics-based movement/collision;
it asks `TanksCore` for decisions (where to path, whether an enemy can see the
player, how much damage a hit does, what an AI should do next).

### Core units (`TanksCore`)

- `SeededRandom` — deterministic `RandomNumberGenerator` (SplitMix64).
- `TileMap` — grid of `Tile` (`road`, `building(id)`, `rubble`, `park`,
  `crater`, `base`, `wall`), size, accessors, passability and movement cost.
- `Building` — id, tile footprint, HP, occupants.
- `CityGenerator` — `generate(seed:, level:) -> Level`.
- `Level` — map, buildings, base location, caches, infantry, enemy tanks
  (spawn + patrol routes), seed, level number.
- `Pathfinder` — A* over the tile map (rubble cost 2, buildings impassable).
- `LineOfSight` — grid raycast; standing buildings block, rubble does not.
- `Difficulty` — level number → enemy counts, HP, speeds, weapon mix, cache
  counts.
- `Combat` — weapon definitions (damage, splash, reload, what they can hurt),
  damage application.
- `TankStats` — armor, fuel, shells, MG rounds, consumption/resupply rules.
- `EnemyTankBrain` — state machine: `patrol → attack → search → retreat`.
- `InfantryBrain` — state machine: `hidden → exposed(firing) → hidden`.

### App units (`TanksOfDoom`)

- `main.swift` / `AppDelegate` — NSApplication, window, SKView.
- `Textures` — procedurally drawn textures (tank hull/turret, buildings in
  damage states, rubble, road, pickups, base, infantry).
- `TitleScene`, `GameScene`, `LevelCompleteScene`, `GameOverScene`.
- `PlayerTank`, `EnemyTank`, `InfantryNode`, `Projectile` (shell, bullet,
  rocket, mortar), `PickupNode`, `BuildingNode`.
- `InputState` — keyboard/mouse state.
- `HUD` — bars, counters, minimap, floating text.
- `Effects` — explosions, muzzle flash, track marks, screen shake.
- `Audio` — synthesized sound effects via AVAudioEngine.
- `HighScores` — UserDefaults persistence.

## City generation

Per level, from a seed:

1. Grid ~80×80 tiles, 64 pt per tile. Outer border is impassable wall.
2. Lay main avenues (2 tiles wide) at irregular spacing in both axes; then
   recursively subdivide large blocks with 1-tile streets until blocks are
   within a target size range.
3. Fill blocks with building lots (each building is a rectangle of tiles).
   A fraction of lots become parks, craters or pre-existing rubble.
4. Place the home base in a corner block (cleared, walkable, marked `base`).
5. Enemy tank spawns are placed on road tiles at least a minimum distance from
   the base; each gets a patrol route of 3–5 road waypoints.
6. Gas and ammo caches go on dead ends, alleys and rubble tiles, biased
   toward distance from the base.
7. Infantry are assigned to buildings; density and weapon mix from
   `Difficulty`.
8. Validation: flood-fill from the base; every road tile, cache and tank spawn
   must be reachable. Unreachable regions are connected by carving a road;
   if validation still fails, regenerate with a derived seed.

## Gameplay

### Controls

- W/S — drive forward/back; A/D — rotate hull.
- Mouse — turret aims at the cursor.
- Left click — main gun. Right click or Space (hold) — machine gun.
- Esc — pause. M — toggle minimap size.

### Player tank

- Armor 100. Fuel 100: drains while moving (faster) and slowly while idling;
  at 0 fuel the tank cannot move but can still turn the turret and fire.
- Main gun: 20 shells max, 1.2 s reload, splash damage; damages tanks,
  infantry and buildings.
- Machine gun: 300 rounds max, high fire rate, low damage; damages infantry
  only.
- Home base: while inside, armor repairs gradually; fuel, shells and rounds
  are topped up to a base minimum (not full — caches are needed for that).
- Caches: gas cache refills a chunk of fuel; ammo cache refills shells and
  rounds. Caches are single-use.

### Infantry (inside buildings)

- Become exposed at a window facing the player when the player is within
  range and in line of sight; fire for a short burst; duck back in. Only
  hittable while exposed.
- Types: Rifleman (low damage), Machine gunner (sustained fire), Bazooka
  (slow dodgeable rocket, heavy damage), Mortar (arcing shell with a ground
  target marker shown before impact).
- Killed instantly when their building collapses.

### Enemy tanks

- Patrol their route using A*.
- On seeing the player (range + line of sight) switch to attack: close to
  firing range, aim and fire shells.
- On losing sight: search the last known position, then return to patrol.
- Retreat when armor is low.
- HP, speed, count and reaction time scale with level.

### Buildings

- Have HP; main-gun hits crack them (visible damage stages) and finally
  collapse them into rubble tiles.
- Rubble is passable at 50% speed and does not block line of sight.

### HUD

- Armor, fuel, shells, MG rounds; enemy tanks remaining.
- Minimap: roads, buildings, base, player, enemy tanks that are currently
  spotted. Caches are not shown.
- Floating text for damage and pickups.

### Flow

- Title → Level N → (all enemy tanks destroyed) Level Complete → Level N+1
  with a new seed and higher difficulty.
- Armor 0 → Game Over with run summary (levels cleared, kills).
- Best run saved in UserDefaults.

### Feel

- Particle explosions, muzzle flashes, track marks, screen shake on hits.
- Synthesized sound effects.

## Testing

Unit tests in `TanksCoreTests`:

- Generator over many seeds: exactly one base; all road tiles, caches and tank
  spawns reachable; cache and enemy counts match `Difficulty`; same seed →
  identical level.
- Pathfinder: finds shortest paths, avoids buildings, prefers roads over
  rubble, returns nil when unreachable.
- Line of sight: blocked by buildings, not by rubble.
- Combat: weapon/target rules (MG can't hurt tanks/buildings), splash,
  building collapse → rubble + occupants killed.
- TankStats: fuel consumption, immobile at zero fuel, base resupply caps.
- AI brains: state transitions for given inputs.

Rendering and game feel are verified by playing the game.

## Out of scope (v1)

- External art/sound assets, music.
- Save/resume mid-level.
- Gamepad support, key rebinding.
- `.app` bundle packaging (can wrap the package later).
