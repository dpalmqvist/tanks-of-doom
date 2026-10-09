import AppKit
import SpriteKit
import TanksCore

extension SKLabelNode {
    static func hud(size: CGFloat) -> SKLabelNode {
        make("", size: size, color: .white, font: "Menlo-Bold")
    }
}

/// A labelled horizontal bar.
final class StatBar: SKNode {
    static let width: CGFloat = 180
    static let height: CGFloat = 14
    private let fill: SKSpriteNode

    init(title: String, color: NSColor) {
        fill = SKSpriteNode(color: color, size: CGSize(width: Self.width, height: Self.height))
        super.init()
        let label = SKLabelNode.hud(size: 14)
        label.text = title
        label.horizontalAlignmentMode = .left
        label.zPosition = 2
        let back = SKSpriteNode(color: NSColor(white: 0, alpha: 0.6), size: CGSize(width: Self.width + 4, height: Self.height + 4))
        back.anchorPoint = CGPoint(x: 0, y: 0.5)
        back.position = CGPoint(x: 68, y: 0)
        back.zPosition = 0
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: 70, y: 0)
        fill.zPosition = 1
        addChild(label)
        addChild(back)
        addChild(fill)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func set(_ fraction: Double) {
        fill.xScale = CGFloat(max(0, min(1, fraction)))
    }
}

/// Everything the versus overlay shows, from whichever side knows it (the host's match or the guest's snapshots).
struct VersusHUDState {
    var localSlot: PlayerSlot
    var lives: [PlayerSlot: Int]
    var respawnIn: Double?
    var latencyMs: Int?
    var notice: String?
}

/// Screen-space overlay attached to the camera (origin at the screen centre).
final class HUD: SKNode {
    let minimap: Minimap
    private let armorBar = StatBar(title: "ARMOR", color: .systemRed)
    private let fuelBar = StatBar(title: "FUEL", color: .systemOrange)
    private let ammoLabel = SKLabelNode.hud(size: 15)
    private let levelLabel = SKLabelNode.hud(size: 18)
    private let enemiesLabel = SKLabelNode.hud(size: 18)
    private let statusLabel = SKLabelNode.hud(size: 18)
    private let messageLabel = SKLabelNode.make("", size: 34)
    private let pausedLabel = SKLabelNode.make("PAUSED", size: 64)
    private let leaveLabel = SKLabelNode.make("LEAVE MATCH?  Y / N", size: 48, color: .systemOrange)
    private let isVersus: Bool
    private let livesLabel = SKLabelNode.hud(size: 20)
    private let respawnLabel = SKLabelNode.make("", size: 44)
    private let livesLeftLabel = SKLabelNode.make("", size: 24, color: .lightGray)
    private let noticeLabel = SKLabelNode.make("", size: 30, color: .systemOrange)
    private let latencyLabel = SKLabelNode.hud(size: 13)
    private var killFeed: [SKLabelNode] = []
    private var lastSize = CGSize.zero

    init(level: Level, versus: Bool = false) {
        minimap = Minimap(map: level.map)
        isVersus = versus
        super.init()
        zPosition = Z.hud
        ammoLabel.horizontalAlignmentMode = .left
        levelLabel.horizontalAlignmentMode = .right
        enemiesLabel.horizontalAlignmentMode = .right
        latencyLabel.horizontalAlignmentMode = .left
        latencyLabel.fontColor = .lightGray
        messageLabel.alpha = 0
        // Text stays readable on top of the (enlarged) minimap.
        statusLabel.zPosition = 5
        messageLabel.zPosition = 5
        leaveLabel.zPosition = 7
        leaveLabel.isHidden = true
        pausedLabel.zPosition = 6
        pausedLabel.isHidden = true
        for label in [respawnLabel, livesLeftLabel, noticeLabel] {
            label.zPosition = 6
            label.isHidden = true
        }
        levelLabel.isHidden = versus
        enemiesLabel.isHidden = versus
        livesLabel.isHidden = !versus
        for node in [armorBar, fuelBar, ammoLabel, levelLabel, enemiesLabel, statusLabel, messageLabel, pausedLabel, leaveLabel, minimap,
                     livesLabel, respawnLabel, livesLeftLabel, noticeLabel, latencyLabel] as [SKNode] {
            addChild(node)
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func layout(size: CGSize) {
        lastSize = size
        let left = -size.width / 2 + 20
        let right = size.width / 2 - 20
        let top = size.height / 2 - 24
        let bottom = -size.height / 2
        armorBar.position = CGPoint(x: left, y: top)
        fuelBar.position = CGPoint(x: left, y: top - 26)
        ammoLabel.position = CGPoint(x: left, y: top - 54)
        levelLabel.position = CGPoint(x: right, y: top)
        enemiesLabel.position = CGPoint(x: right, y: top - 26)
        statusLabel.position = CGPoint(x: 0, y: bottom + 40)
        messageLabel.position = CGPoint(x: 0, y: size.height / 2 - 110)
        pausedLabel.position = .zero
        leaveLabel.position = .zero
        minimap.position = CGPoint(x: right - minimap.displaySize, y: bottom + 20)
        livesLabel.position = CGPoint(x: 0, y: top)
        respawnLabel.position = CGPoint(x: 0, y: 40)
        livesLeftLabel.position = CGPoint(x: 0, y: -10)
        noticeLabel.position = CGPoint(x: 0, y: size.height / 2 - 160)
        latencyLabel.position = CGPoint(x: left, y: bottom + 16)
        layoutKillFeed()
    }

    func update(stats: TankStats, level: Int, enemiesLeft: Int, inBase: Bool) {
        armorBar.set(stats.armor / TankStats.maxArmor)
        fuelBar.set(stats.fuel / TankStats.maxFuel)
        ammoLabel.text = "SHELLS \(stats.shells)/\(TankStats.maxShells)   MG \(stats.rounds)/\(TankStats.maxRounds)"
        levelLabel.text = "LEVEL \(level)"
        enemiesLabel.text = "ENEMY TANKS: \(enemiesLeft)"
        if inBase {
            if stats.armor < TankStats.maxArmor {
                statusLabel.text = "AT BASE: REPAIRING ARMOR"
            } else if stats.fuel < TankStats.maxFuel {
                statusLabel.text = "AT BASE: REFUELLING"
            } else {
                statusLabel.text = "AT BASE: FULLY REPAIRED AND REFUELLED"
            }
            statusLabel.fontColor = .systemGreen
        } else if stats.fuel <= 0 && !stats.isDestroyed {
            statusLabel.text = "OUT OF FUEL: PRESS R TO ABANDON TANK"
            statusLabel.fontColor = .systemRed
        } else {
            statusLabel.text = ""
        }
    }

    func flash(_ text: String, color: NSColor = .white, duration: Double = 2) {
        messageLabel.text = text
        messageLabel.fontColor = color
        messageLabel.removeAllActions()
        messageLabel.alpha = 1
        messageLabel.run(.sequence([.wait(forDuration: duration), .fadeOut(withDuration: 0.5)]))
    }

    func updateVersus(_ state: VersusHUDState) {
        let me = state.localSlot
        let font = NSFont(name: "Menlo-Bold", size: 20) ?? .boldSystemFont(ofSize: 20)
        let text = NSMutableAttributedString()
        func add(_ string: String, _ color: NSColor) {
            text.append(NSAttributedString(string: string, attributes: [.foregroundColor: color, .font: font]))
        }
        add("YOU \(Self.hearts(state.lives[me] ?? 0))", me.color)
        add("     ", .white)
        add("OPPONENT \(Self.hearts(state.lives[me.opponent] ?? 0))", me.opponent.color)
        livesLabel.attributedText = text

        if let seconds = state.respawnIn {
            respawnLabel.isHidden = false
            livesLeftLabel.isHidden = false
            respawnLabel.text = "RESPAWNING IN \(Int(seconds.rounded(.up)))…"
            livesLeftLabel.text = "LIVES LEFT: \(state.lives[me] ?? 0)"
        } else {
            respawnLabel.isHidden = true
            livesLeftLabel.isHidden = true
        }
        noticeLabel.isHidden = state.notice == nil
        noticeLabel.text = state.notice
        latencyLabel.text = state.latencyMs.map { "\($0) ms" } ?? ""
    }

    /// Newest line on top; at most three, each fading after six seconds.
    func addKillFeed(_ line: String) {
        let label = SKLabelNode.hud(size: 15)
        label.text = line
        label.horizontalAlignmentMode = .right
        label.zPosition = 5
        addChild(label)
        label.run(.sequence([.wait(forDuration: 6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
        killFeed.removeAll { $0.parent == nil }
        killFeed.insert(label, at: 0)
        while killFeed.count > 3 { killFeed.removeLast().removeFromParent() }
        layoutKillFeed()
    }

    private func layoutKillFeed() {
        let right = lastSize.width / 2 - 20
        let top = lastSize.height / 2 - 24
        for (index, label) in killFeed.enumerated() {
            label.position = CGPoint(x: right, y: top - CGFloat(index) * 22)
        }
    }

    private static func hearts(_ count: Int) -> String {
        count <= 0 ? "–" : String(repeating: "♥", count: count)
    }

    func setLeavePrompt(_ shown: Bool) {
        leaveLabel.isHidden = !shown
    }

    func setPaused(_ paused: Bool) {
        pausedLabel.isHidden = !paused
    }

    func toggleMinimap() {
        minimap.toggleSize()
        layout(size: lastSize)
    }
}
