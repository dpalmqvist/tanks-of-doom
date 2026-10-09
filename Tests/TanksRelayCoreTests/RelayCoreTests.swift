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
    let actual1 = relay.received(RelayMessage.createRoom.encoded(), from: 1, now: 0, using: &rng)
    #expect(actual1 == [.send(error(.protocolError), to: 1), .close(1)])
}

@Test func mismatchedVersionsAreTurnedAway() {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 1)
    let oldHello = RelayMessage.hello(version: TanksNet.protocolVersion + 1).encoded()
    let actual2 = relay.received(oldHello, from: 1, now: 0, using: &rng)
    #expect(actual2 == [.send(error(.versionMismatch), to: 1), .close(1)])
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
    let actual3 = relay.received(RelayMessage.joinRoom(code: code.lowercased()).encoded(), from: 2, now: 0, using: &rng)
    #expect(actual3 == [.send(joined, to: 1), .send(joined, to: 2)])
}

@Test func pairedPlayersExchangeGameFramesBothWays() {
    var relay = pairedRelay().0
    var rng = SeededRandom(seed: 3)
    let frame: [UInt8] = [36, 1, 2, 3]
    let actual4 = relay.received(frame, from: 2, now: 1, using: &rng)
    #expect(actual4 == [.send(frame, to: 1)])
    let actual5 = relay.received(frame, from: 1, now: 1, using: &rng)
    #expect(actual5 == [.send(frame, to: 2)])
}

@Test func wrongCodesAndFullRoomsAreReportedWithoutHangingUp() {
    let paired = pairedRelay()
    var relay = paired.0
    let code = paired.1
    var rng = SeededRandom(seed: 4)
    _ = relay.received(hello, from: 3, now: 0, using: &rng)
    let actual6 = relay.received(RelayMessage.joinRoom(code: "ZZZZZ").encoded(), from: 3, now: 0, using: &rng)
    #expect(actual6 == [.send(error(.roomNotFound), to: 3)])
    let actual7 = relay.received(RelayMessage.joinRoom(code: code).encoded(), from: 3, now: 0, using: &rng)
    #expect(actual7 == [.send(error(.roomFull), to: 3)])
}

@Test func whenOneSideLeavesTheOtherHearsAboutIt() {
    var relay = pairedRelay().0
    var rng = SeededRandom(seed: 5)
    let actual8 = relay.disconnected(1)
    #expect(actual8 == [.send(RelayMessage.peerLeft.encoded(), to: 2)])
    #expect(relay.roomCount == 0)
    let actual9 = relay.received([36, 9], from: 2, now: 1, using: &rng)
    #expect(actual9.isEmpty)   // nobody left to forward to
    let actual10 = relay.disconnected(2)
    #expect(actual10.isEmpty)
}

@Test func gameFramesBeforePairingGoNowhere() {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 6)
    _ = relay.received(hello, from: 1, now: 0, using: &rng)
    let actual11 = relay.received([36, 1], from: 1, now: 0, using: &rng)
    #expect(actual11.isEmpty)
}

@Test func garbageAndRepliesFromClientsAreProtocolErrors() {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 7)
    _ = relay.received(hello, from: 1, now: 0, using: &rng)
    let actual12 = relay.received([9, 9, 9], from: 1, now: 0, using: &rng)
    #expect(actual12 == [.send(error(.protocolError), to: 1), .close(1)])
    _ = relay.received(hello, from: 2, now: 0, using: &rng)
    let actual13 = relay.received(RelayMessage.joined.encoded(), from: 2, now: 0, using: &rng)
    #expect(actual13 == [.send(error(.protocolError), to: 2), .close(2)])
}

@Test func floodingAndOversizeFramesGetTheSenderDisconnected() {
    var relay = pairedRelay().0
    var rng = SeededRandom(seed: 8)
    var last: [RelayAction<Int>] = []
    // A sustained flood: more than the whole burst allowance (plus any refill) at one instant.
    for _ in 0...Int(RelayLimits.framesPerSecond * RelayLimits.burstSeconds) {
        last = relay.received([36], from: 2, now: 5, using: &rng)
    }
    #expect(last == [.close(2)])
    let huge = [UInt8](repeating: 36, count: RelayLimits.maxFrameBytes + 1)
    let actual14 = relay.received(huge, from: 1, now: 5, using: &rng)
    #expect(actual14 == [.close(1)])
}

@Test func aBacklogFlushedAfterANetworkHiccupIsAllowed() {
    var relay = pairedRelay().0
    var rng = SeededRandom(seed: 10)
    // Steady play at ~30 frames a second for a few seconds...
    for i in 0..<90 {
        _ = relay.received([36], from: 2, now: 1 + Double(i) / 30, using: &rng)
    }
    // ...then a 5 s uplink stall, after which the backlog arrives in one burst.
    var forwarded = 0
    for _ in 0..<150 {
        let actions = relay.received([36], from: 2, now: 9, using: &rng)
        if actions == [.send([36], to: 1)] { forwarded += 1 }
    }
    #expect(forwarded == 150)
}

@Test func rateLimitBurstIsCappedAndRefillsAtTheRate() {
    var limiter = FrameRateLimiter(perSecond: 2, burst: 4)
    var allowed = 0
    for _ in 0..<10 where limiter.allow(now: 0) { allowed += 1 }
    #expect(allowed == 4)                 // starts full, capped at the burst
    var afterLongWait = 0
    for _ in 0..<10 where limiter.allow(now: 100) { afterLongWait += 1 }
    #expect(afterLongWait == 4)           // a long silence never saves up more than the burst
}

@Test func rateLimitRefillsOverTime() {
    var limiter = FrameRateLimiter(perSecond: 2, burst: 2)
    let first = limiter.allow(now: 0)
    let second = limiter.allow(now: 0)
    let third = limiter.allow(now: 0)
    let later = limiter.allow(now: 0.5)
    #expect(first)
    #expect(second)
    #expect(!third)
    #expect(later)
}

@Test func lonelyHostsAreDisconnectedAfterTheTTL() {
    var relay = RelayCore<Int>()
    var rng = SeededRandom(seed: 9)
    _ = relay.received(hello, from: 1, now: 0, using: &rng)
    _ = relay.received(RelayMessage.createRoom.encoded(), from: 1, now: 0, using: &rng)
    let actual15 = relay.expire(now: 100, ttl: 600)
    #expect(actual15.isEmpty)
    let actual16 = relay.expire(now: 700, ttl: 600)
    #expect(actual16 == [.close(1)])
}
