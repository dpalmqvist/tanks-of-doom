import Foundation
import TanksNet

enum RelayConfig {
    /// The deployed relay (see docs/relay.md). TANKS_RELAY_URL overrides it, e.g. ws://localhost:8080/ws.
    static let defaultURL = "ws://localhost:8080/ws"

    static var url: URL {
        let configured = ProcessInfo.processInfo.environment["TANKS_RELAY_URL"] ?? defaultURL
        return URL(string: configured) ?? URL(string: defaultURL)!
    }
}

/// One WebSocket to the relay. Every callback arrives on the main thread.
final class RelayConnection {
    enum Event {
        case relay(RelayMessage)
        case game(GameMessage)
        /// The connection ended; the reason is for the player.
        case closed(String?)
    }

    var onEvent: ((Event) -> Void)?
    private let task: URLSessionWebSocketTask
    private var isClosed = false

    init(url: URL = RelayConfig.url) {
        task = URLSession.shared.webSocketTask(with: url)
    }

    func open() {
        task.resume()
        send(relay: .hello(version: TanksNet.protocolVersion))
        receiveNext()
    }

    func send(relay message: RelayMessage) {
        send(bytes: message.encoded())
    }

    func send(_ message: GameMessage) {
        send(bytes: message.encoded())
    }

    /// Hangs up quietly (no `.closed` event): we chose to leave.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        task.cancel(with: .goingAway, reason: nil)
    }

    private func send(bytes: [UInt8]) {
        guard !isClosed else { return }
        task.send(.data(Data(bytes))) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async { self?.fail("Can't reach server") }
        }
    }

    private func receiveNext() {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, !self.isClosed else { return }
                switch result {
                case .success(.data(let data)):
                    self.handle([UInt8](data))
                    self.receiveNext()
                case .success:
                    self.fail("Connection error")
                case .failure:
                    self.fail("Can't reach server")
                }
            }
        }
    }

    private func handle(_ bytes: [UInt8]) {
        do {
            if RelayMessage.isControlFrame(bytes) {
                onEvent?(.relay(try RelayMessage.decode(bytes)))
            } else {
                onEvent?(.game(try GameMessage.decode(bytes)))
            }
        } catch {
            fail("Connection error")
        }
    }

    private func fail(_ reason: String) {
        guard !isClosed else { return }
        isClosed = true
        task.cancel(with: .goingAway, reason: nil)
        onEvent?(.closed(reason))
    }
}
