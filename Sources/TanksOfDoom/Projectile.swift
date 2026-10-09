import AppKit
import SpriteKit
import TanksCore

/// Something a weapon can hit: enemy tanks, exposed infantry and, in versus, the other player's tank.
protocol Hostile: SKNode {
    /// Stable id shared with the guest's mirror of the world.
    var netID: UInt32 { get }
    var hitRadius: CGFloat { get }
    var targetKind: TargetKind { get }
    var canBeHit: Bool { get }
    func applyDamage(_ amount: Int, from shooter: Combatant, in scene: GameScene)
}

/// A straight-flying shot.
final class Projectile: SKSpriteNode {
    let weapon: WeaponKind
    let shooter: Combatant
    /// Infantry shots start inside their own building, so that building never stops them.
    let ownerBuilding: Int?
    let velocity: CGVector
    var remainingRange: CGFloat
    var smokeTimer: Double = 0
    var netID: UInt32 = 0

    init(weapon: WeaponKind, angle: CGFloat, shooter: Combatant, ownerBuilding: Int?) {
        let spec = Combat.spec(weapon)
        self.weapon = weapon
        self.shooter = shooter
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
    var netID: UInt32 = 0
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

    /// 0 at launch, 1 on landing.
    var progress: Double { min(1, elapsed / Self.flightTime) }

    /// Advances along the arc; returns true on landing.
    func advance(dt: Double) -> Bool {
        elapsed += dt
        show(progress: CGFloat(progress))
        return progress >= 1
    }

    /// Puts the shell at `t` along its arc (the guest drives this from snapshots).
    func show(progress t: CGFloat) {
        position = start + (target - start) * t
        setScale(1 + 1.8 * sin(.pi * t))
    }
}
