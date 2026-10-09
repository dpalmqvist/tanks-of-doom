import Foundation
import Testing
import TanksNet
@testable import TanksRelayCore

/// A real WebSocket client, like the game's.
private final class Client {
    let task: URLSessionWebSocketTask

    init(port: Int) {
        task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
        task.resume()
    }

    func send(_ bytes: [UInt8]) async throws {
        try await task.send(.data(Data(bytes)))
    }

    func receive() async throws -> [UInt8] {
        switch try await task.receive() {
        case .data(let data): return [UInt8](data)
        case .string(let text): Issue.record("unexpected text frame \(text)"); return []
        @unknown default: return []
        }
    }

    func relayMessage() async throws -> RelayMessage {
        try RelayMessage.decode(try await receive())
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

@Test func twoClientsPairUpAndTalkThroughTheRelay() async throws {
    let server = RelayServer()
    let port = try server.start(host: "127.0.0.1", port: 0)
    let host = Client(port: port)
    let guest = Client(port: port)
    let hello = RelayMessage.hello(version: TanksNet.protocolVersion).encoded()

    try await host.send(hello)
    try await host.send(RelayMessage.createRoom.encoded())
    guard case .roomCreated(let code) = try await host.relayMessage() else {
        Issue.record("host got no room code")
        return
    }

    try await guest.send(hello)
    try await guest.send(RelayMessage.joinRoom(code: code.lowercased()).encoded())
    #expect(try await guest.relayMessage() == .joined)
    #expect(try await host.relayMessage() == .joined)

    let ping = GameMessage.ping(1.5).encoded()
    try await guest.send(ping)
    #expect(try await host.receive() == ping)
    let pong = GameMessage.pong(1.5).encoded()
    try await host.send(pong)
    #expect(try await guest.receive() == pong)

    host.close()
    #expect(try await guest.relayMessage() == .peerLeft)
    guest.close()
    try await server.shutdown()
}

@Test func outdatedGamesAreTurnedAway() async throws {
    let server = RelayServer()
    let port = try server.start(host: "127.0.0.1", port: 0)
    let client = Client(port: port)
    try await client.send(RelayMessage.hello(version: TanksNet.protocolVersion + 1).encoded())
    #expect(try await client.relayMessage() == .error(.versionMismatch))
    client.close()
    try await server.shutdown()
}

@Test func unknownRoomCodesAreReported() async throws {
    let server = RelayServer()
    let port = try server.start(host: "127.0.0.1", port: 0)
    let client = Client(port: port)
    try await client.send(RelayMessage.hello(version: TanksNet.protocolVersion).encoded())
    try await client.send(RelayMessage.joinRoom(code: "ZZZZZ").encoded())
    #expect(try await client.relayMessage() == .error(.roomNotFound))
    client.close()
    try await server.shutdown()
}
