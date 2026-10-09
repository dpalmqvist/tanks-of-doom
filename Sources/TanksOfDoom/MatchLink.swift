import Foundation
import TanksNet

/// The connection between two paired players: game messages in and out, latency pings, and how long
/// the other side has been silent. Scenes take turns owning it (lobby → match → result screen).
final class MatchLink {
    static let pingInterval = 1.0
    static let lostAfter = 3.0
    static let giveUpAfter = 10.0

    let connection: RelayConnection
    var onMessage: ((GameMessage) -> Void)?
    /// The opponent left or the connection died.
    var onClosed: ((String?) -> Void)?
    private(set) var latencyMs: Int?
    private var lastHeard = ProcessInfo.processInfo.systemUptime
    private var pingTimer = 0.0

    init(connection: RelayConnection) {
        self.connection = connection
        connection.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Seconds since the other side last said anything.
    var silence: Double { ProcessInfo.processInfo.systemUptime - lastHeard }

    func send(_ message: GameMessage) {
        connection.send(message)
    }

    func tick(dt: Double) {
        pingTimer -= dt
        guard pingTimer <= 0 else { return }
        pingTimer = Self.pingInterval
        send(.ping(ProcessInfo.processInfo.systemUptime))
    }

    func close() {
        connection.close()
    }

    private func handle(_ event: RelayConnection.Event) {
        switch event {
        case .game(let message):
            lastHeard = ProcessInfo.processInfo.systemUptime
            switch message {
            case .ping(let time):
                send(.pong(time))
            case .pong(let time):
                latencyMs = Int(((ProcessInfo.processInfo.systemUptime - time) * 1000).rounded())
            default:
                onMessage?(message)
            }
        case .relay(.peerLeft):
            onClosed?("Opponent left")
        case .relay:
            break
        case .closed(let reason):
            onClosed?(reason)
        }
    }
}
