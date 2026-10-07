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

final class PlayerTank: TankNode {
    static let forwardSpeed: CGFloat = 170
    static let reverseSpeed: CGFloat = 100
    static let turnRate: CGFloat = 2.2
    static let turretTurnRate: CGFloat = 4.0

    var stats = TankStats()
    var mainCooldown: Double = 0
    var machineGunCooldown: Double = 0
    var isDestroyed: Bool { stats.isDestroyed }

    init() {
        super.init(hullTexture: Textures.playerHull, turretTexture: Textures.playerTurret)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showWreck() {
        for part in [hull, turret] {
            part.color = .black
            part.colorBlendFactor = 0.75
        }
    }
}
