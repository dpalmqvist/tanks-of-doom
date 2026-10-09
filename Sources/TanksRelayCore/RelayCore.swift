import Foundation
import TanksNet

public enum RelayLimits {
    public static let maxFrameBytes = 1 << 16
    public static let framesPerSecond = 100.0
    /// Seconds of frames a connection may save up, so a backlog flushed after a network hiccup
    /// (inside the game's 10 s grace) isn't mistaken for a flood.
    public static let burstSeconds = 10.0
    public static let maxRooms = 500
    public static let defaultRoomTTL = 600.0
}

/// Token bucket: refills at `perSecond` frames a second, holding at most `burst` (and starting full).
public struct FrameRateLimiter: Sendable {
    public let perSecond: Double
    public let burst: Double
    private var tokens: Double
    private var last: Double?

    public init(perSecond: Double, burst: Double) {
        self.perSecond = perSecond
        self.burst = burst
        tokens = burst
    }

    public mutating func allow(now: Double) -> Bool {
        if let last { tokens = min(burst, tokens + (now - last) * perSecond) }
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
        var limiter = limiters[connection]
            ?? FrameRateLimiter(perSecond: framesPerSecond, burst: framesPerSecond * RelayLimits.burstSeconds)
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
