# Tanks of Doom — Online Multiplayer Design Spec

Date: 2026-10-09

## Goal

Add a two-player online versus mode. Two players on different Macs, connected
over the internet through a relay server, fight in a generated city that also
contains the usual AI hazards (Rust Brigade tanks and infantry). Each player
starts with the same number of lives, chosen before the match. Every death
costs a life, whoever caused it, and the player respawns at a random location.
The first player to reduce the opponent to 0 lives wins.

The single-player campaign stays exactly as it is.

### Success criteria

- From the title screen a player can host a match, get a room code, and a
  second player on another Mac can join with that code over the internet.
- The host picks lives (1–9) and AI intensity in a lobby; both players see the
  settings before the match starts.
- During the match both players drive, shoot, collect pickups and repair at
  their own base. AI tanks and infantry attack both players.
- Deaths cost a life, respawns happen at a random safe location after a short
  delay, and the match ends with a result screen when one player hits 0 lives.
  Rematch and return-to-menu both work.
- Driving your own tank feels immediate on the client (local prediction).
- If a player disconnects, the other is told and wins after a grace period.
- Single-player is unchanged. `swift test` passes, including new tests for
  match rules, respawn selection, the wire protocol and the relay.

### Out of scope (first version)

- More than two players, teams, spectators.
- Reconnecting to a match in progress.
- Public matchmaking, accounts, rankings. Players share room codes themselves.
- Lag compensation for hit detection (hits are judged on the host at host time).
- Game Center, Steam or any platform service.

## Decisions

| Topic | Decision |
|---|---|
| Connection | Two Macs over the internet. |
| Discovery | Own relay server; players pair with a 5-letter room code. |
| Netcode | Host-authoritative. The host runs the whole simulation; the client sends inputs and renders snapshots. |
| Transport | WebSocket (TLS in production). Server: SwiftNIO. Client: `URLSessionWebSocketTask`. |
| World | Generated city with destructible buildings, pickups, AI tanks and infantry. |
| AI kills | Any death costs a life. |
| AI over time | Destroyed AI tanks respawn after a delay; the threat never runs out. |
| Bases | Two bases, one per player, in opposite corners. |
| Relay language | Swift, as a new target in this package. |

## Architecture

### Package layout

| Target | Kind | Depends on | Responsibility |
|---|---|---|---|
| `TanksCore` | library | Foundation | Existing game logic, plus match rules, respawn selection, two-base city generation. |
| `TanksNet` | library (new) | Foundation, `TanksCore` | Wire protocol: message types, binary encoding/decoding, protocol version. No networking I/O. |
| `TanksOfDoom` | executable | `TanksCore`, `TanksNet` | Game app. Gains the multiplayer session, host/client loops, lobby screens and HUD additions. |
| `TanksRelayCore` | library (new) | `TanksNet`, SwiftNIO (`NIOCore`, `NIOPosix`, `NIOHTTP1`, `NIOWebSocket`) | Relay logic (rooms, pairing, rate limits) and the WebSocket server. A library so it can be unit tested. |
| `TanksRelay` | executable (new) | `TanksRelayCore` | Relay server entry point: reads `PORT` / `ROOM_TTL` and runs the server. |
| `TanksCoreTests` | test | `TanksCore` | Existing plus new match-rule tests. |
| `TanksNetTests` | test (new) | `TanksNet` | Encode/decode round trips, version checks, malformed input. |
| `TanksRelayCoreTests` | test (new) | `TanksRelayCore` | Room creation, joining, forwarding, disconnect handling. |

SwiftNIO is the project's first third-party dependency and is used only by
`TanksRelayCore` / `TanksRelay`. The game app stays dependency-free.

### Roles

- **Host**: the player who created the room. Runs `GameScene` as the
  authoritative simulation for everything: both player tanks, AI, projectiles,
  mortars, buildings, pickups, damage, lives and respawns. Applies the remote
  player's inputs as they arrive. Sends snapshots and events to the client.
- **Client**: the player who joined. Builds the same city locally from the
  seed (for rendering and prediction only), sends its inputs, and renders the
  world from host snapshots. It never decides damage, deaths or pickups.
- **Relay**: pairs host and client by room code and forwards frames between
  them. It does not look inside game messages.

## Game-side refactor: more than one player tank

Today `GameScene` has one `playerTank`, one `InputState`, one `TurretAim`, and
every system (camera, HUD, auto-aim, minimap, infantry and AI targeting, audio,
level end) refers to it directly. The refactor introduces:

- `Player` (app target): owns a `PlayerTank`, its `InputState`, `TurretAim`,
  locked target, `inBase` flag, slot (`.host` / `.guest`), lives, respawn timer
  and invulnerability timer.
- `GameScene.players: [Player]` and `GameScene.localPlayer: Player`.
  Single-player has exactly one player, which is also the local player.
- Camera, HUD, minimap, audio falloff and screen shake follow `localPlayer`.
- Movement, weapons, turret aim and pickups are updated per player using that
  player's input.
- `hostiles` for a player includes AI tanks, infantry and the other player's
  tank, so auto-aim and Tab cycling can lock onto the opponent.
- Hit tests and splash damage check every player tank, not just one.
  Projectiles record the shooter (`Player`, AI tank or infantry) so kills can
  be credited in the kill feed.
- AI targeting: AI tanks and infantry pick the nearest visible, living,
  non-invulnerable player instead of "the player". `EnemyTankBrain` and
  `InfantryBrain` keep their current inputs (visible / distance); the scene
  chooses which player to feed them.
- A `GameMode` value (`.campaign(level:)` / `.versus(MatchSettings, role)`)
  decides level-end handling: the campaign keeps today's
  `checkLevelEnd`; versus uses the match rules below.
- The guest's tank uses a second colour scheme (steel blue hull) generated in
  `Textures`, so the players can tell the tanks apart.

This refactor lands first and is verified by playing single-player before any
networking is added.

## Match rules (`TanksCore`)

New pure-logic types, all unit tested:

- `MatchSettings`: `lives` (1–9, default 3), `aiIntensity` (`.light`,
  `.normal`, `.heavy`, mapping to `Difficulty(level:)` 1, 3 and 6 for enemy
  counts, HP, speed and weapon mix), `seed`.
- `MatchState`: per-slot lives, respawn countdown, invulnerability countdown,
  and the winner. Operations:
  - `playerDied(slot)` → lives −1. If lives reach 0, the match is over and the
    other slot wins. Otherwise a respawn countdown of **3 s** starts.
  - `tick(dt)` → advances the countdowns and reports slots that should respawn now.
  - After a respawn, invulnerability lasts **3 s**. Invulnerable tanks take no
    damage and AI ignores them. Firing ends invulnerability early.
  - `opponentDisconnected(slot)` → the other slot wins.
- `RespawnPicker.pick(map:, avoiding:, rng:)` → a random reachable, drivable
  tile (road, rubble or park, not inside a building) at least **15 tiles** from
  the opponent and at least **8 tiles** from every AI tank. If none qualifies,
  the distances are relaxed step by step down to 0, so a tile is always
  returned.
- A respawned tank gets full armor, fuel, shells and rounds (`TankStats()`).
- `AIRespawnSchedule`: when an AI tank is destroyed it respawns after **20 s**
  on a road tile at least 15 tiles from both players, keeping the count at the
  starting number. Infantry killed in a still-standing building is replaced
  after **30 s**. Infantry in a collapsed building is gone for good.
- Pickups respawn in the same spot **45 s** after being collected.

### Two-base cities

`CityGenerator.generate(seed:level:bases:)` gains a `bases` count (1 or 2,
default 1, so the campaign is unchanged). With 2 bases, the second base is
placed in the opposite (top-right) corner. Generation must guarantee that both
bases reach each other and every cache, and AI spawns respect the safe-zone
radius around both. `Level` gains `bases: [BaseSite]` (centre plus tiles);
the existing `baseCenter` / `baseTiles` remain as the first base, so
single-player code does not change. The host's base is `bases[0]` and the
guest's is `bases[1]`. A player repairs only at their own base. The opponent's
base works for neither player and is drawn in the opponent's colour.

Players start the match at their own base.

## Wire protocol (`TanksNet`)

All messages are binary WebSocket frames. Each frame starts with a 1-byte
message type. Encoding is hand-written with a small `ByteWriter` / `ByteReader`
(little-endian integers, `Float32` for positions and angles, length-prefixed
arrays). Decoding never traps on bad input. It throws, and the receiver drops
the connection.

`TanksNet.protocolVersion` is a single integer, bumped on any change.

### Relay control messages (client ⇄ relay)

| Message | Direction | Content |
|---|---|---|
| `hello` | game → relay | protocol version |
| `createRoom` | game → relay | — |
| `roomCreated` | relay → game | 5-letter code (A–Z without I/O, so codes are easy to read aloud) |
| `joinRoom` | game → relay | code |
| `joined` | relay → both | peer is present; the forwarding phase begins |
| `error` | relay → game | reason: `versionMismatch`, `roomNotFound`, `roomFull`, `serverFull`, `protocolError` |
| `peerLeft` | relay → game | the other side disconnected |

After `joined`, every frame the relay receives is forwarded unchanged to the
other side.

### Game messages (host ⇄ guest, through the relay)

| Message | Direction | Rate | Content |
|---|---|---|---|
| `lobbyState` | host → guest | on change | `MatchSettings`, host ready flag |
| `guestReady` | guest → host | on change | ready flag |
| `matchStart` | host → guest | once | seed, settings (both sides show a 3-2-1 countdown, then the host starts simulating) |
| `input` | guest → host | 30 Hz | sequence number, input bits (forward, back, left, right, turret L/R, fire main, fire MG), discrete presses since last frame (Tab, Q/E manual) |
| `snapshot` | host → guest | 20 Hz | host tick, last processed guest input seq, both players (position, heading, turret, stats, lives, flags), AI tanks (id, position, heading, turret, health), exposed infantry (id, kind, position, facing), projectiles and mortars (id, kind, position, angle), pickups present (bitset), and the events since the previous snapshot |
| `ping` / `pong` | both | 1 Hz | timestamp, used for the latency display and disconnect detection |
| `leave` | both | once | the player quit on purpose |

Events (building HP changes, explosions, floating text, sound cues, screen
shake, kill feed entries, match over) ride inside the next snapshot frame, so
they arrive in order with no acknowledgement and the host never sends more
than about 21 frames per second. Rough snapshot size with heavy AI is under 2 KB, which is
about 40 KB/s, well within any connection.

## Netcode

### Host loop

- Runs the normal `GameScene.update` with two players. The guest's `Player`
  uses the most recently received `InputState`. Discrete presses (Tab, Q/E)
  are applied once.
- If no guest input has arrived for 250 ms, the guest's held keys are
  released, so the tank stops rather than driving off on its own.
- Every 50 ms, builds and sends a `snapshot`, carrying every event queued
  since the previous one.

### Client loop

- Each frame, records local input and sends an `input` message at 30 Hz.
- **Own tank, prediction:** applies local input immediately using the same
  movement code and the local copy of the map. Keeps a buffer of unacknowledged
  inputs. On each snapshot, takes the host's position for the guest tank,
  replays the inputs newer than `lastProcessedInputSeq`, and if the result is
  more than 2 px from the predicted position, eases toward it over 100 ms. If
  it is more than 64 px away, it snaps. The turret angle is not predicted: the
  host aims it (auto-aim picks targets on the host), and the guest shows the
  host's angle, so shots always leave the barrel where it is drawn.
- **Everything else, interpolation:** renders the opponent, AI, infantry and
  projectiles 100 ms in the past, interpolating between the two surrounding
  snapshots. Entities are created and removed as they appear in or disappear
  from snapshots.
- Firing: the client plays the muzzle flash and sound immediately for
  responsiveness. The real projectile appears when the host's snapshot
  includes it.
- Building damage, explosions and kill-feed entries come from events and use
  the existing `Effects` and `WorldRenderer` code paths.
- The client does not run AI, damage, pickup collection, base repair or match
  rules. Its HUD numbers come from the snapshot.

### Disconnects and pausing

- There is no pause in versus. **Esc** opens a "Leave match? Y / N" overlay;
  the simulation keeps running.
- If no messages arrive from the peer for 3 s, the HUD shows "Connection lost…".
  After 10 s, or immediately on `peerLeft` / `leave`, the remaining player wins
  and sees the result screen.
- If the relay connection itself fails, the player sees an error screen and
  returns to the multiplayer menu.

## Relay server (`TanksRelay`)

- One SwiftNIO WebSocket server, configured by environment variables:
  `PORT` (default 8080) and `ROOM_TTL` (default 10 min for an unpaired room).
- Rooms: `[code: Room]` with host channel and optional guest channel, held in
  one event-loop-confined actor or locked dictionary.
- After `hello`, the relay rejects version mismatches. `createRoom` makes a
  unique code. `joinRoom` pairs the guest with the host, or returns an error.
- After pairing, the relay forwards frames between the two channels. When
  either side closes, the other gets `peerLeft` and the room is removed.
- Limits: 64 KB maximum frame size, at most 100 frames per second per
  connection (excess frames close the connection), at most 500 rooms.
- TLS is terminated by the hosting platform or a reverse proxy (Caddy).
  `TanksRelay` itself speaks plain `ws://`.
- `Dockerfile` (multi-stage: `swift:6.0` build, `swift:6.0-slim` run) and a
  `docs/relay.md` with deploy steps for a typical VPS with Caddy, plus local
  run instructions.

### Relay address in the game

- `RelayConfig.url` defaults to a constant set in the source
  (`wss://<your-domain>/ws`, filled in once the server is deployed).
- An environment variable, `TANKS_RELAY_URL`, overrides it, for local testing
  (`ws://localhost:8080/ws`).

## Screens and HUD

### Menu flow

Title → **1** Campaign / **2** Multiplayer.

Multiplayer menu → **H** Host / **J** Join / **Esc** back.

- **Host** connects, shows the room code in large letters, and shows the lobby:
  lives (←/→ to change, 1–9) and AI intensity (↑/↓), plus the guest's status
  (waiting / joined / ready). **Enter** starts once the guest is ready.
- **Join** shows a 5-letter code entry field. **Enter** connects, then shows
  the lobby read-only with **Enter** to toggle ready.
- Errors such as "Room not found", "Room full", "Version mismatch — update the
  game" and "Can't reach server" show on the same screen with **Esc** to go back.

These screens extend `MenuScene` or add a small `LobbyScene` that follows the
same text-stack style.

### In-match HUD additions

- Lives for both players at the top, for example `YOU ♥♥♥   OPPONENT ♥♥`,
  in each player's colour.
- A kill feed in the top-right with the last 3 entries, such as
  "You destroyed Opponent" or "Sniper destroyed You".
- When dead: "RESPAWNING IN 3…" and "LIVES LEFT: 2".
- Invulnerable tanks blink.
- Minimap: the opponent is shown in their colour only while in line of sight,
  the same rule as AI tanks. Both bases are drawn.
- A small latency readout (`42 ms`) in the corner.

### Match end

The result screen shows "VICTORY" or "DEFEAT", the remaining lives and kill
counts for both players. **R** requests a rematch (both players must press
it; the host then starts a new seed with the same settings). **Esc** leaves to
the title screen. Versus results are not recorded in campaign high scores.

## Error handling

- Malformed frames close the connection: the relay drops the sender, and the
  game shows "Connection error".
- Protocol version mismatch is caught at `hello`, before a room is created or
  joined.
- Late or out-of-order snapshots (by host tick) are discarded on the client.
- The host clamps guest inputs to valid values. The guest can only send key
  states, never positions or damage.

## Testing

- **TanksCore:** `MatchState` (life loss, win, respawn and invulnerability
  timing, disconnect win), `RespawnPicker` (distance rules, relaxation
  fallback, always returns a drivable reachable tile), AI respawn schedule,
  two-base generation (both bases reachable from each other and every cache,
  across many seeds), and confirming that one-base generation produces the
  same level as before for a given seed.
- **TanksNet:** encode→decode round trips for every message, truncated and
  garbage input throws, version constant is checked.
- **TanksRelayCore:** the relay logic tested as plain values (no sockets), plus
  an in-process server on a random port driven by two real WebSocket clients:
  create/join/pair, wrong code, full room, forwarding in both directions,
  `peerLeft` on close, version mismatch rejection.
- **Manual:** run `swift run TanksRelay` locally and two game instances with
  `TANKS_RELAY_URL=ws://localhost:8080/ws`. Play a full match: deaths by
  opponent and by AI, respawns, the win screen, rematch, quitting mid-match.
  Repeat over the deployed relay between two Macs. Use macOS Network Link
  Conditioner (100 ms, 1% loss) to check that prediction and interpolation
  stay playable.
- **Regression:** play single-player levels to confirm nothing changed.

## Build order

1. Multi-player refactor of `GameScene` (single-player still works).
2. Match rules, respawn, two-base generation in `TanksCore` with tests.
3. Local hot-seat test harness: a debug flag that runs versus with two local
   players on one keyboard (second key set) to exercise the rules before any
   networking. It is debug-only and not shipped as a mode.
4. `TanksNet` protocol and tests.
5. `TanksRelay` server, tests, Dockerfile, docs.
6. Host and client network loops in the game, with prediction and
   interpolation.
7. Lobby, menus, HUD additions, result screen, rematch.
8. Deploy the relay, set the default URL, update the README with
   multiplayer instructions.

## What the owner must provide

- A server or container host reachable from the internet, a domain name and
  TLS (for example a small VPS with Caddy, or Fly.io).
- Two Macs (or one Mac running two instances) for testing.
