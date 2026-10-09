import SpriteKit
import TanksCore

/// A tank: a hull that drives and a turret that aims independently.
class TankNode: SKNode {
    static let radius: CGFloat = 22

    let hull: SKSpriteNode
    let turret: SKSpriteNode
    var heading: CGFloat = 0 { didSet { hull.zRotation = heading } }
    var turretAngle: CGFloat = 0 { didSet { turret.zRotation = turretAngle } }
    var distanceSinceTrack: CGFloat = 0

    init(hullTexture: SKTexture, turretTexture: SKTexture) {
        hull = SKSpriteNode(texture: hullTexture)
        turret = SKSpriteNode(texture: turretTexture)
        super.init()
        turret.anchorPoint = Textures.turretAnchor
        hull.zPosition = 0
        turret.zPosition = 1
        addChild(hull)
        addChild(turret)
        zPosition = Z.tanks
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    var muzzlePosition: CGPoint { position + CGPoint(angle: turretAngle, length: Textures.muzzleOffset) }

    /// Moves with wall sliding. Other tanks block, unless the move separates overlapping tanks.
    /// Returns the distance actually travelled.
    @discardableResult
    func move(by delta: CGPoint, in map: TileMap, blockers: [TankNode]) -> CGFloat {
        let start = position
        func isFree(_ p: CGPoint) -> Bool {
            guard map.canOccupy(p.world, radius: Double(Self.radius)) else { return false }
            return !blockers.contains { other in
                other !== self && other.position.distance(to: p) < Self.radius * 2
                    && other.position.distance(to: p) < other.position.distance(to: start)
            }
        }
        let target = position + delta
        if isFree(target) {
            position = target
        } else if isFree(CGPoint(x: target.x, y: position.y)) {
            position.x = target.x
        } else if isFree(CGPoint(x: position.x, y: target.y)) {
            position.y = target.y
        }
        return position.distance(to: start)
    }
}

final class PlayerTank: TankNode, Hostile {
    static let forwardSpeed: CGFloat = 170
    static let reverseSpeed: CGFloat = 100
    static let turnRate: CGFloat = 2.2
    static let turretTurnRate: CGFloat = 4.0

    let slot: PlayerSlot
    var stats = TankStats()
    var mainCooldown: Double = 0
    var machineGunCooldown: Double = 0
    /// Spawn protection in versus: takes no damage and the AI looks elsewhere.
    var isInvulnerable = false
    var isDestroyed: Bool { stats.isDestroyed }

    var netID: UInt32 { UInt32(slot.rawValue + 1) }
    var hitRadius: CGFloat { TankNode.radius }
    var targetKind: TargetKind { .tank }
    /// Hidden tanks are waiting to respawn in versus.
    var canBeHit: Bool { !isDestroyed && !isInvulnerable && !isHidden }

    init(slot: PlayerSlot) {
        self.slot = slot
        super.init(hullTexture: Textures.hull(for: slot), turretTexture: Textures.turret(for: slot))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyDamage(_ amount: Int, from shooter: Combatant, in scene: GameScene) {
        scene.damagePlayer(self, amount, from: shooter)
    }

    func showWreck() {
        for part in [hull, turret] {
            part.color = .black
            part.colorBlendFactor = 0.75
        }
    }

    /// Back in factory condition at `point` (versus respawn).
    func respawn(at point: CGPoint, heading: CGFloat) {
        stats = TankStats()
        mainCooldown = 0
        machineGunCooldown = 0
        position = point
        self.heading = heading
        turretAngle = heading
        for part in [hull, turret] { part.colorBlendFactor = 0 }
        isHidden = false
    }
}
