import AppKit
import SpriteKit
import TanksCore
import TanksNet

/// Host: connect, show the room code, choose lives and AI, start once the guest is ready.
/// Guest: type the code, then wait (toggling ready) until the host starts.
final class LobbyScene: SKScene {
    enum Role { case host, guest }

    private enum Phase {
        case enteringCode(typed: String, problem: String?)
        case connecting
        case waitingForGuest
        case paired
        case failed(String)
    }

    private let role: Role
    private var phase: Phase
    private var connection: RelayConnection?
    private var link: MatchLink?
    private var roomCode: String?
    private var settings = MatchSettings()
    private var guestReady = false

    init(size: CGSize, role: Role) {
        self.role = role
        phase = role == .host ? .connecting : .enteringCode(typed: "", problem: nil)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.06, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        if role == .host { connect(joining: nil) }
        render()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        render()
    }

    // MARK: Networking

    private func connect(joining code: String?) {
        let connection = RelayConnection()
        self.connection = connection
        connection.onEvent = { [weak self] event in self?.handle(event) }
        connection.open()
        if let code {
            connection.send(relay: .joinRoom(code: code))
        } else {
            connection.send(relay: .createRoom)
        }
        phase = .connecting
    }

    private func handle(_ event: RelayConnection.Event) {
        switch event {
        case .relay(.roomCreated(let code)):
            roomCode = code
            phase = .waitingForGuest
        case .relay(.joined):
            guard let connection else { return }
            let link = MatchLink(connection: connection)
            link.onMessage = { [weak self] message in self?.receive(message) }
            link.onClosed = { [weak self] reason in self?.fail(reason ?? "Connection lost") }
            self.link = link
            phase = .paired
            if role == .host { link.send(.lobby(settings)) }
        case .relay(.error(let code)):
            fail(code.message)
        case .closed(let reason):
            fail(reason ?? "Can't reach server")
        default:
            break
        }
        render()
    }

    private func receive(_ message: GameMessage) {
        switch message {
        case .lobby(let hostSettings): settings = hostSettings
        case .guestReady(let ready): guestReady = ready
        case .matchStart(let matchSettings): startMatch(matchSettings)
        case .leave: fail("Opponent left")
        default: break
        }
        render()
    }

    private func fail(_ reason: String) {
        connection?.close()
        link = nil
        guestReady = false
        phase = .failed(reason)
        render()
    }

    private func startMatch(_ matchSettings: MatchSettings) {
        guard let link, let view else { return }
        let role: VersusRole = self.role == .host ? .host(link) : .guest(link)
        view.presentScene(GameScene(size: size, versus: matchSettings, role: role), transition: .fade(withDuration: 0.6))
    }

    private func leave() {
        link?.send(.leave)
        connection?.close()
        view?.presentScene(MenuScene.multiplayer(size: size), transition: .fade(withDuration: 0.4))
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let code = event.keyCode
        let enter = code == 36 || code == 76
        if code == 53 { return leave() }   // Esc
        switch phase {
        case .enteringCode(let typed, _):
            if enter {
                if let normalized = TanksNet.normalizeRoomCode(typed) {
                    connect(joining: normalized)
                } else {
                    phase = .enteringCode(typed: typed, problem: "Codes are 5 letters (no I or O)")
                }
            } else if code == 51 {   // Delete
                phase = .enteringCode(typed: String(typed.dropLast()), problem: nil)
            } else if let letters = event.charactersIgnoringModifiers?.uppercased().filter(\.isLetter), !letters.isEmpty,
                      typed.count < TanksNet.roomCodeLength {
                phase = .enteringCode(typed: typed + String(letters.prefix(TanksNet.roomCodeLength - typed.count)), problem: nil)
            }
        case .waitingForGuest, .paired:
            guard role == .host else {
                if enter, let link {   // guest toggles ready
                    guestReady.toggle()
                    link.send(.guestReady(guestReady))
                }
                break
            }
            switch code {
            case 123: settings.changeLives(by: -1)       // ←
            case 124: settings.changeLives(by: 1)        // →
            case 125: settings.changeIntensity(by: 1)    // ↓
            case 126: settings.changeIntensity(by: -1)   // ↑
            case 36, 76:
                guard let link, guestReady else { break }
                settings.seed = .random(in: 0...UInt64.max)
                link.send(.matchStart(settings))
                startMatch(settings)
                return
            default: break
            }
            link?.send(.lobby(settings))
        case .failed:
            if enter { leave() }
        case .connecting:
            break
        }
        render()
    }

    // MARK: Drawing

    private func render() {
        removeAllChildren()
        let mono = "Menlo-Bold"
        var lines: [(String, CGFloat, NSColor, String)] = []
        func line(_ text: String, _ size: CGFloat, _ color: NSColor = .white, _ font: String = "Impact") {
            lines.append((text, size, color, font))
        }
        let title = role == .host ? "HOST A MATCH" : "JOIN A MATCH"
        line(title, 64, NSColor(calibratedRed: 0.9, green: 0.3, blue: 0.15, alpha: 1))
        var prompt = "ESC  BACK"

        switch phase {
        case .enteringCode(let typed, let problem):
            line("Type the room code your opponent gave you:", 22)
            line(spaced(typed.padding(toLength: TanksNet.roomCodeLength, withPad: "_", startingAt: 0)), 72, .systemYellow, mono)
            line(problem ?? " ", 20, .systemRed, mono)
            prompt = "ENTER  JOIN  ·  ESC  BACK"
        case .connecting:
            line("Connecting…", 28, .lightGray)
        case .waitingForGuest, .paired:
            if let roomCode {
                line("ROOM CODE", 20, .lightGray, mono)
                line(spaced(roomCode), 72, .systemYellow, mono)
            }
            let canEdit = role == .host
            line("Lives:  \(canEdit ? "◀ " : "")\(settings.lives)\(canEdit ? " ▶" : "")", 26, .white, mono)
            line("AI:  \(canEdit ? "▲ " : "")\(settings.aiIntensity.name)\(canEdit ? " ▼" : "")", 26, .white, mono)
            line(" ", 10)
            switch (phase, role) {
            case (.waitingForGuest, _):
                line("Tell your opponent the code. Waiting for them to join…", 22, .lightGray)
                prompt = "←/→  LIVES  ·  ↑/↓  AI  ·  ESC  CANCEL"
            case (_, .host):
                line(guestReady ? "Opponent is READY" : "Opponent joined, not ready yet", 24, guestReady ? .systemGreen : .systemOrange)
                prompt = guestReady ? "ENTER  START  ·  ESC  LEAVE" : "←/→  LIVES  ·  ↑/↓  AI  ·  ESC  LEAVE"
            default:
                line(guestReady ? "You are READY. Waiting for the host to start…" : "Press Enter when you're ready", 24,
                     guestReady ? .systemGreen : .systemOrange)
                prompt = "ENTER  \(guestReady ? "NOT READY" : "READY")  ·  ESC  LEAVE"
            }
        case .failed(let reason):
            line(reason, 30, .systemRed)
            prompt = "ENTER / ESC  BACK"
        }

        let spacing: CGFloat = 1.5
        let total = lines.reduce(CGFloat(0)) { $0 + $1.1 * spacing } + 70
        var y = size.height / 2 + total / 2
        for (text, fontSize, color, font) in lines {
            y -= fontSize * spacing / 2
            let label = SKLabelNode.make(text, size: fontSize, color: color, font: font)
            label.position = CGPoint(x: size.width / 2, y: y)
            addChild(label)
            y -= fontSize * spacing / 2
        }
        let promptLabel = SKLabelNode.make(prompt, size: 24, color: .systemYellow)
        promptLabel.position = CGPoint(x: size.width / 2, y: y - 60)
        addChild(promptLabel)
    }

    private func spaced(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }
}
