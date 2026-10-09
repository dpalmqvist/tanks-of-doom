import AppKit
import SpriteKit
import TanksCore
import TanksNet

final class EnemyTank: TankNode, Hostile {
    static let turnRate: CGFloat = 1.8
    static let turretTurnRate: CGFloat = 1.8

    let maxArmor: Double
    private(set) var armor: Double
    let driveSpeed: CGFloat
    let reactionTime: Double
    let patrol: [GridPoint]
    let spawn: EnemyTankSpawn
    var netID: UInt32 = 0

    private var brain = EnemyTankBrain()
    private var patrolIndex = 0
    private var path: [CGPoint] = []
    private var repathTimer: Double = 0
    private var stuckTime: Double = 0
    private var reverseTime: Double = 0
    /// Tiles held by nearby tanks when this tank got stuck; the next route avoids them.
    private var avoidTiles: Set<GridPoint> = []
    private var fireCooldown: Double = 1
    private var lastKnownPlayer: CGPoint?
    private let healthBack = SKSpriteNode(color: NSColor(white: 0, alpha: 0.6), size: CGSize(width: 42, height: 6))
    private let healthBar = SKSpriteNode(color: .systemRed, size: CGSize(width: 40, height: 4))

    var hitRadius: CGFloat { TankNode.radius }
    var targetKind: TargetKind { .tank }
    var canBeHit: Bool { armor > 0 }

    init(spawn: EnemyTankSpawn, difficulty: Difficulty) {
        maxArmor = Double(difficulty.enemyTankArmor)
        armor = maxArmor
        driveSpeed = CGFloat(difficulty.enemyTankSpeed)
        reactionTime = difficulty.enemyReactionTime
        patrol = spawn.patrol
        self.spawn = spawn
        super.init(hullTexture: Textures.enemyHull, turretTexture: Textures.enemyTurret)
        healthBack.position = CGPoint(x: 0, y: 34)
        healthBack.zPosition = 3
        healthBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        healthBar.position = CGPoint(x: -20, y: 34)
        healthBar.zPosition = 4
        healthBack.isHidden = true
        healthBar.isHidden = true
        addChild(healthBack)
        addChild(healthBar)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyDamage(_ amount: Int, from shooter: Combatant, in scene: GameScene) {
        guard armor > 0 else { return }
        armor -= Double(amount)
        healthBack.isHidden = false
        healthBar.isHidden = false
        healthBar.xScale = CGFloat(max(0, armor / maxArmor))
        scene.fx(.text("-\(amount)", at: (position + CGPoint(x: 0, y: 40)).vec, color: .yellow))
        if armor <= 0 { scene.enemyDestroyed(self) }
    }

    func update(dt: Double, scene: GameScene) {
        let map = scene.level.map
        let target = scene.aiTarget(from: position, sightRange: EnemyTankBrain.sightRange)
        let toTarget = target.map { position.distance(to: $0.position) } ?? .greatestFiniteMagnitude
        let sees = target.map { Double(toTarget) <= EnemyTankBrain.sightRange && scene.hasLineOfSight(from: position, to: $0.position) } ?? false
        if sees, let target { lastKnownPlayer = target.position }
        let reachedSearchPoint = lastKnownPlayer.map { position.distance(to: $0) < tileSize } ?? true

        let previous = brain.state
        let perception = EnemyPerception(canSeePlayer: sees, distanceToPlayer: Double(toTarget),
                                         armorFraction: armor / maxArmor, reachedSearchPoint: reachedSearchPoint)
        let state = brain.update(perception, dt: dt)
        if state != previous {
            path = []
            repathTimer = 0
        }
        repathTimer -= dt
        fireCooldown -= dt

        switch state {
        case .patrol:
            if path.isEmpty && repathTimer <= 0 {
                patrolIndex = (patrolIndex + 1) % patrol.count
                setPath(to: map.center(patrol[patrolIndex]), map: map)
                repathTimer = 0.5
            }
            aimTurret(at: heading, dt: dt)
        case .attack:
            guard let target else { break }
            if toTarget > CGFloat(Combat.spec(.enemyShell).range) * 0.7 {
                if repathTimer <= 0 {
                    setPath(to: target.position, map: map)
                    repathTimer = 1.5
                }
            } else {
                path = []
            }
            engage(target, scene: scene, dt: dt)
        case .search:
            if path.isEmpty && repathTimer <= 0, let lastSeen = lastKnownPlayer {
                setPath(to: lastSeen, map: map)
                repathTimer = 2
            }
            aimTurret(at: heading, dt: dt)
        case .retreat:
            if path.isEmpty && repathTimer <= 0 {
                let threat = target?.position ?? position
                let refuge = patrol.max { map.center($0).distance(to: threat) < map.center($1).distance(to: threat) } ?? patrol[0]
                setPath(to: map.center(refuge), map: map)
                repathTimer = 2
            }
            if sees, let target { engage(target, scene: scene, dt: dt) } else { aimTurret(at: heading, dt: dt) }
        }
        followPath(dt: dt, scene: scene)
    }

    private func engage(_ target: PlayerTank, scene: GameScene, dt: Double) {
        let angle = position.angle(to: target.position)
        aimTurret(at: angle, dt: dt)
        let aligned = abs(normalizeAngle(turretAngle - angle)) < 0.08
        let ready = brain.timeInState >= reactionTime || brain.state == .retreat
        guard aligned, ready, fireCooldown <= 0, scene.hasLineOfSight(from: position, to: target.position) else { return }
        scene.fire(.enemyShell, from: muzzlePosition, angle: turretAngle + .random(in: -0.06...0.06), shooter: .enemyTank)
        fireCooldown = Combat.spec(.enemyShell).reload
    }

    private func aimTurret(at angle: CGFloat, dt: Double) {
        turretAngle = rotateAngle(turretAngle, toward: angle, maxStep: Self.turretTurnRate * CGFloat(dt))
    }

    private func setPath(to target: CGPoint, map: TileMap) {
        let route = Pathfinder.findPath(in: map, from: map.grid(position), to: map.grid(target), avoiding: avoidTiles)
            ?? (avoidTiles.isEmpty ? nil : Pathfinder.findPath(in: map, from: map.grid(position), to: map.grid(target)))
        avoidTiles = []
        guard let route else {
            path = []
            return
        }
        path = route.dropFirst().map { map.center($0) }
    }

    private func followPath(dt: Double, scene: GameScene) {
        let map = scene.level.map
        let step = driveSpeed * CGFloat(map.speedMultiplier(at: position.world)) * CGFloat(dt)
        if reverseTime > 0 {
            // Unsticking: back up while turning, then pick a fresh route.
            reverseTime -= dt
            heading += Self.turnRate * 0.5 * CGFloat(dt)
            move(by: CGPoint(angle: heading + .pi, length: step * 0.6), in: map, blockers: scene.allTanks)
            return
        }
        guard let next = path.first else { return }
        if position.distance(to: next) < 14 {
            path.removeFirst()
            return
        }
        let desired = position.angle(to: next)
        heading = rotateAngle(heading, toward: desired, maxStep: Self.turnRate * CGFloat(dt))
        guard abs(normalizeAngle(desired - heading)) < 0.6 else { return }
        let moved = move(by: CGPoint(angle: heading, length: step), in: map, blockers: scene.allTanks)
        scene.leaveTracks(self, moved: moved)
        if moved < step * 0.2 {
            stuckTime += dt
            if stuckTime > 1.0 {
                stuckTime = 0
                avoidTiles = Set(scene.allTanks.filter { $0 !== self && $0.position.distance(to: position) < tileSize * 3 }
                    .map { map.grid($0.position) })
                path = []
                reverseTime = 0.7
                repathTimer = 0
            }
        } else {
            stuckTime = 0
        }
    }
}
