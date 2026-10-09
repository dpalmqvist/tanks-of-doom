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
