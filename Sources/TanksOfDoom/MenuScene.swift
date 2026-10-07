import AppKit
import SpriteKit

extension SKLabelNode {
    static func make(_ text: String, size: CGFloat, color: NSColor = .white, font: String = "Impact") -> SKLabelNode {
        let label = SKLabelNode(fontNamed: font)
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }
}

/// A centred stack of text lines plus a blinking prompt; Enter, Space or a click continues.
final class MenuScene: SKScene {
    struct Line {
        var text: String
        var size: CGFloat
        var color: NSColor = .white
        var font: String = "Impact"
    }

    private let lines: [Line]
    private let prompt: String
    private let onContinue: (MenuScene) -> Void
    private var acceptsInput = false

    init(size: CGSize, lines: [Line], prompt: String, onContinue: @escaping (MenuScene) -> Void) {
        self.lines = lines
        self.prompt = prompt
        self.onContinue = onContinue
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.06, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        layoutContent()
        // Ignore input briefly so a key held from the previous screen doesn't skip this one.
        run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in self?.acceptsInput = true }]))
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutContent()
    }

    private func layoutContent() {
        removeAllChildren()
        let spacing: CGFloat = 1.5
        let total = lines.reduce(CGFloat(0)) { $0 + $1.size * spacing } + 70
        var y = size.height / 2 + total / 2
        for line in lines {
            y -= line.size * spacing / 2
            let label = SKLabelNode.make(line.text, size: line.size, color: line.color, font: line.font)
            label.position = CGPoint(x: size.width / 2, y: y)
            addChild(label)
            y -= line.size * spacing / 2
        }
        let promptLabel = SKLabelNode.make(prompt, size: 28, color: .systemYellow)
        promptLabel.position = CGPoint(x: size.width / 2, y: y - 70)
        promptLabel.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)])))
        addChild(promptLabel)
    }

    override func keyDown(with event: NSEvent) {
        if [36, 76, 49].contains(event.keyCode) { proceed() }   // Return, keypad Enter, Space
    }

    override func mouseDown(with event: NSEvent) {
        proceed()
    }

    private func proceed() {
        guard acceptsInput else { return }
        acceptsInput = false
        onContinue(self)
    }
}

extension MenuScene {
    static func title(size: CGSize) -> MenuScene {
        let mono = "Menlo-Bold"
        var lines: [Line] = [
            Line(text: "TANKS OF DOOM", size: 88, color: NSColor(calibratedRed: 0.9, green: 0.3, blue: 0.15, alpha: 1)),
            Line(text: "Hunt down every enemy tank in the ruined city.", size: 24),
            Line(text: " ", size: 10),
            Line(text: "W/S drive · A/D turn · MOUSE aim turret", size: 17, color: .lightGray, font: mono),
            Line(text: "LEFT CLICK main gun · RIGHT CLICK or SPACE machine gun", size: 17, color: .lightGray, font: mono),
            Line(text: "Find hidden GAS and AMMO caches · return to BASE for repairs", size: 17, color: .lightGray, font: mono),
            Line(text: "ESC pause · M minimap size · R abandon tank when out of fuel", size: 17, color: .lightGray, font: mono),
        ]
        if HighScores.bestLevels > 0 || HighScores.bestKills > 0 {
            lines.append(Line(text: " ", size: 10))
            lines.append(Line(text: "BEST RUN: \(HighScores.bestLevels) levels cleared, \(HighScores.bestKills) kills",
                              size: 20, color: .systemGreen, font: mono))
        }
        // Task 9 replaces this closure body to start the game.
        return MenuScene(size: size, lines: lines, prompt: "PRESS ENTER TO START") { _ in }
    }
}
