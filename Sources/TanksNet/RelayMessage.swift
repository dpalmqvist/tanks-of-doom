import Foundation

public enum RelayErrorCode: UInt8, Error, Sendable {
    case versionMismatch = 1
    case roomNotFound = 2
    case roomFull = 3
    case serverFull = 4
    case protocolError = 5

    /// What the player sees.
    public var message: String {
        switch self {
        case .versionMismatch: return "Version mismatch — update the game"
        case .roomNotFound: return "Room not found"
        case .roomFull: return "Room full"
        case .serverFull: return "Server full — try again later"
        case .protocolError: return "Connection error"
        }
    }
}

/// Frames between a game and the relay itself. Their type bytes are 1–31; game frames (32 and up)
/// pass through the relay untouched once two players are paired.
public enum RelayMessage: Equatable, Sendable {
    case hello(version: UInt16)
    case createRoom
    case roomCreated(code: String)
    case joinRoom(code: String)
    case joined
    case error(RelayErrorCode)
    case peerLeft

    public static let firstGameType: UInt8 = 32

    public static func isControlFrame(_ bytes: [UInt8]) -> Bool {
        guard let type = bytes.first else { return false }
        return type < firstGameType
    }

    public func encoded() -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case .hello(let version):
            w.u8(1)
            w.u16(version)
        case .createRoom:
            w.u8(2)
        case .roomCreated(let code):
            w.u8(3)
            w.string(code)
        case .joinRoom(let code):
            w.u8(4)
            w.string(code)
        case .joined:
            w.u8(5)
        case .error(let code):
            w.u8(6)
            w.u8(code.rawValue)
        case .peerLeft:
            w.u8(7)
        }
        return w.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> RelayMessage {
        var r = ByteReader(bytes)
        let message: RelayMessage
        switch try r.u8() {
        case 1: message = .hello(version: try r.u16())
        case 2: message = .createRoom
        case 3: message = .roomCreated(code: try r.string())
        case 4: message = .joinRoom(code: try r.string())
        case 5: message = .joined
        case 6: message = .error(try r.raw(RelayErrorCode.self))
        case 7: message = .peerLeft
        case let type: throw WireError.badValue("relay message type \(type)")
        }
        try r.finish()
        return message
    }
}
