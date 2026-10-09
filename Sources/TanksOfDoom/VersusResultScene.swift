import AppKit
import SpriteKit
import TanksCore
import TanksNet

/// End of a networked match. R asks for a rematch (both must ask; the host then starts a new city
/// with the same settings), Esc or Enter leaves.
final class VersusResultScene: SKScene {
    private let result: VersusResult
    private let link: MatchLink
    private let settings: MatchSettings
    private let isHost: Bool
    private var wantsRematch = false
    private var opponentWantsRematch: Bool
    private var opponentLeft: Bool

    init(size: CGSize, result: VersusResult, link: MatchLink, settings: MatchSettings, isHost: Bool,
         opponentWantsRematch: Bool, opponentLeft: Bool) {
        self.result = result
        self.link = link
        self.settings = settings
        self.isHost = isHost
        self.opponentWantsRematch = opponentWantsRematch
        self.opponentLeft = opponentLeft
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.06, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        link.onMessage = { [weak self] message in self?.receive(message) }
        link.onClosed = { [weak self] _ in
            self?.opponentLeft = true
            self?.render()
        }
        // The finished GameScene's handler is gone; failures fall back to onClosed.
        link.onFailed = nil
        render()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        render()
    }

    private func receive(_ message: GameMessage) {
        switch message {
        case .rematch:
            opponentWantsRematch = true
            startIfBothWant()
        case .matchStart(let next) where !isHost:
            view?.presentScene(GameScene(size: size, versus: next, role: .guest(link)), transition: .fade(withDuration: 0.6))
            return
        case .leave:
            opponentLeft = true
        default:
            break
        }
        render()
    }

    private func startIfBothWant() {
        guard isHost, wantsRematch, opponentWantsRematch, !opponentLeft, let view else { return }
        var next = settings
        next.seed = .random(in: 0...UInt64.max)
        link.send(.matchStart(next))
        view.presentScene(GameScene(size: size, versus: next, role: .host(link)), transition: .fade(withDuration: 0.6))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 15 where !opponentLeft && !wantsRematch:   // R
            wantsRematch = true
            link.send(.rematch)
            startIfBothWant()
        case 53, 36, 76:                                // Esc, Return, keypad Enter
            link.send(.leave)
            link.close()
            view?.presentScene(MenuScene.title(size: size), transition: .fade(withDuration: 0.6))
            return
        default:
            break
        }
        render()
    }

    private func render() {
        removeAllChildren()
        let mono = "Menlo-Bold"
        let me = result.localSlot
        let them = me.opponent
        let won = result.winner == me
        var lines: [(String, CGFloat, NSColor, String)] = [
            (won ? "VICTORY" : "DEFEAT", 88, won ? .systemGreen : .systemRed, "Impact"),
            ("You: \(result.lives[me] ?? 0) lives left, \(result.kills[me] ?? 0) kills", 22, me.color, mono),
            ("Opponent: \(result.lives[them] ?? 0) lives left, \(result.kills[them] ?? 0) kills", 22, them.color, mono),
            (" ", 12, .white, mono),
        ]
        let status: String
        if opponentLeft {
            status = "Opponent left"
        } else if wantsRematch {
            status = opponentWantsRematch ? "Starting…" : "Waiting for opponent…"
        } else {
            status = opponentWantsRematch ? "Opponent wants a rematch!" : " "
        }
        lines.append((status, 24, opponentLeft ? .systemOrange : .lightGray, "Impact"))

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
        let prompt = opponentLeft || wantsRematch ? "ESC  MENU" : "R  REMATCH  ·  ESC  MENU"
        let promptLabel = SKLabelNode.make(prompt, size: 28, color: .systemYellow)
        promptLabel.position = CGPoint(x: size.width / 2, y: y - 60)
        addChild(promptLabel)
    }
}
