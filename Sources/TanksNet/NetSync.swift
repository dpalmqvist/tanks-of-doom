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
    /// The last render time handed out, so smoothing the offset never moves the picture backwards.
    private var lastRenderTime: Double?

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
            lastRenderTime = nil   // after a resync the render clock may jump, either way
        }
        snapshots.append(snapshot)
        if snapshots.count > Self.capacity { snapshots.removeFirst(snapshots.count - Self.capacity) }
        return true
    }

    /// The snapshots either side of the render time. Holds at the oldest/newest rather than guessing beyond them.
    /// The render time never steps backwards, except straight after a resync.
    public mutating func frame(at localTime: Double) -> Frame? {
        guard let offset = clockOffset, let first = snapshots.first, let last = snapshots.last else { return nil }
        let renderTime = max(localTime + offset - Self.delay, lastRenderTime ?? -.infinity)
        lastRenderTime = renderTime
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
