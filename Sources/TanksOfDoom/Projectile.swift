import AppKit
import SpriteKit
import TanksCore

/// Something the player's weapons can hit (enemy tanks, exposed infantry).
protocol Hostile: SKNode {
    var hitRadius: CGFloat { get }
    var targetKind: TargetKind { get }
    var canBeHit: Bool { get }
    func applyDamage(_ amount: Int, in scene: GameScene)
}

/// A straight-flying shot.
final class Projectile: SKSpriteNode {
    let weapon: WeaponKind
    let byPlayer: Bool
    /// Infantry shots start inside their own building, so that building never stops them.
    let ownerBuilding: Int?
    let velocity: CGVector
    var remainingRange: CGFloat
    var smokeTimer: Double = 0

    init(weapon: WeaponKind, angle: CGFloat, byPlayer: Bool, ownerBuilding: Int?) {
        let spec = Combat.spec(weapon)
        self.weapon = weapon
        self.byPlayer = byPlayer
        self.ownerBuilding = ownerBuilding
        velocity = CGVector(dx: cos(angle) * spec.projectileSpeed, dy: sin(angle) * spec.projectileSpeed)
        remainingRange = CGFloat(spec.range)
        let texture = Textures.projectile(weapon)
        super.init(texture: texture, color: .clear, size: texture.size())
        zRotation = angle
        zPosition = Z.projectiles
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// A mortar round: flies a fixed-time arc over buildings to a marked target.
final class MortarShell: SKSpriteNode {
    static let flightTime = 1.8

    let start: CGPoint
    let target: CGPoint
    let marker: SKShapeNode
    private var elapsed: Double = 0

    init(from start: CGPoint, to target: CGPoint) {
        self.start = start
        self.target = target
        marker = SKShapeNode(circleOfRadius: CGFloat(Combat.spec(.mortar).splashRadius))
        marker.strokeColor = NSColor.systemRed.withAlphaComponent(0.8)
        marker.fillColor = NSColor.systemRed.withAlphaComponent(0.12)
        marker.lineWidth = 2
        marker.position = target
        marker.zPosition = Z.pickups
        marker.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.25), .fadeAlpha(to: 1, duration: 0.25)])))
        super.init(texture: Textures.mortarShell, color: .clear, size: Textures.mortarShell.size())
        position = start
        zPosition = Z.effects - 1
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Advances along the arc; returns true on landing.
    func advance(dt: Double) -> Bool {
        elapsed += dt
        let t = CGFloat(min(1, elapsed / Self.flightTime))
        position = start + (target - start) * t
        setScale(1 + 1.8 * sin(.pi * t))
        return t >= 1
    }
}
