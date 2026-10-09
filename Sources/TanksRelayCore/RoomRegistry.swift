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
