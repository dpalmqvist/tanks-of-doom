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
