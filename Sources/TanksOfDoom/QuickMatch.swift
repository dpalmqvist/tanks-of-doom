import AppKit
import Foundation
import SpriteKit
import TanksCore
import TanksNet

/// Developer shortcut for networked matches without the lobby.
/// TANKS_HOST=1 creates a room (code printed to the terminal) and starts when someone joins;
/// TANKS_JOIN=<code> joins it. Both use TANKS_RELAY_URL or the default relay.
enum QuickMatch {
    static func start(in view: SKView) -> Bool {
        let env = ProcessInfo.processInfo.environment
        let joinCode = env["TANKS_JOIN"]
        guard env["TANKS_HOST"] == "1" || joinCode != nil else { return false }

        let connection = RelayConnection()
        // The closure keeps the connection alive until a scene takes it over.
        connection.onEvent = { [unowned view] event in
            switch event {
            case .relay(.roomCreated(let code)):
                print("Room code: \(code)")
                fflush(stdout)
            case .relay(.joined):
                let link = MatchLink(connection: connection)
                if joinCode == nil {
                    let settings = MatchSettings(seed: .random(in: 0...UInt64.max))
                    link.send(.matchStart(settings))
                    print("Match started as host")
                    fflush(stdout)
                    view.presentScene(GameScene(size: view.bounds.size, versus: settings, role: .host(link)))
                } else {
                    link.onMessage = { message in
                        guard case .matchStart(let settings) = message else { return }
                        print("Match started as guest")
                        fflush(stdout)
                        view.presentScene(GameScene(size: view.bounds.size, versus: settings, role: .guest(link)))
                    }
                }
            case .relay(.error(let code)):
                print("Relay error: \(code.message)")
                fflush(stdout)
            case .closed(let reason):
                print("Connection closed: \(reason ?? "")")
                fflush(stdout)
            default:
                break
            }
        }
        connection.open()
        if let joinCode {
            connection.send(relay: .joinRoom(code: joinCode))
        } else {
            connection.send(relay: .createRoom)
        }
        view.presentScene(MenuScene(size: view.bounds.size,
                                    lines: [MenuScene.Line(text: "QUICK MATCH", size: 64),
                                            MenuScene.Line(text: "See the terminal for the room code.", size: 22)],
                                    prompt: "WAITING FOR THE OTHER PLAYER…") { _ in })
        return true
    }
}
