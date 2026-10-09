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
