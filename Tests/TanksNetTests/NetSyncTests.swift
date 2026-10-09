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
    let first = buffer.insert(snap(5, at: 100), receivedAt: 0)
    let duplicate = buffer.insert(snap(5, at: 100), receivedAt: 0.01)
    let stale = buffer.insert(snap(4, at: 99.95), receivedAt: 0.02)
    #expect(first)
    #expect(!duplicate)
    #expect(!stale)
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
