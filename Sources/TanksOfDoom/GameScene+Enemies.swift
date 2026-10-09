import SpriteKit
import TanksCore
import TanksNet

extension GameScene {
    /// Every tank that blocks movement: players still in play and the AI.
    var allTanks: [TankNode] {
        (players.map(\.tank).filter { !$0.isHidden } as [TankNode]) + (enemies as [TankNode])
    }

    func spawnEnemies() {
        for spawn in level.enemyTanks { addEnemy(spawn, at: level.map.center(spawn.position)) }
    }

    @discardableResult
    func addEnemy(_ spawn: EnemyTankSpawn, at point: CGPoint) -> EnemyTank {
        let tank = EnemyTank(spawn: spawn, difficulty: Difficulty(level: levelNumber))
        tank.netID = makeNetID()
        tank.position = point
        tank.heading = .random(in: -.pi ... .pi)
        tank.turretAngle = tank.heading
        worldNode.addChild(tank)
        enemies.append(tank)
        return tank
    }

    func updateEnemies(dt: Double) {
        for tank in enemies { tank.update(dt: dt, scene: self) }
    }

    func hasLineOfSight(from a: CGPoint, to b: CGPoint, ignoringBuilding: Int? = nil) -> Bool {
        LineOfSight.isClear(in: level.map, from: level.map.grid(a), to: level.map.grid(b), ignoringBuilding: ignoringBuilding)
    }

    /// The player tank an AI unit at `point` should go after: the nearest one it can see, else the nearest one.
    /// Destroyed, respawning and spawn-protected tanks are ignored.
    func aiTarget(from point: CGPoint, sightRange: Double) -> PlayerTank? {
        let candidates = players.map(\.tank)
            .filter { !$0.isDestroyed && !$0.isHidden && !$0.isInvulnerable }
            .sorted { $0.position.distance(to: point) < $1.position.distance(to: point) }
        return candidates.first { Double($0.position.distance(to: point)) <= sightRange && hasLineOfSight(from: point, to: $0.position) }
            ?? candidates.first
    }

    func enemyDestroyed(_ tank: EnemyTank) {
        runStats.tanksDestroyed += 1
        if isVersus { aiTankQueue.schedule(tank.spawn, after: VersusTimings.aiTankRespawn) }
        fx(.explosion(at: tank.position.vec, scale: 1.8))
        fx(.sound(.bigExplosion, at: tank.position.vec, volume: 1))
        fx(.shake(magnitude: 8, duration: 0.3))
        addWreck(Textures.enemyHull, at: tank.position, heading: tank.heading)
        tank.removeFromParent()
        enemies.removeAll { $0 === tank }
    }

    /// A blackened hull left on the ground where a tank died.
    func addWreck(_ texture: SKTexture, at point: CGPoint, heading: CGFloat) {
        let wreck = SKSpriteNode(texture: texture)
        wreck.color = .black
        wreck.colorBlendFactor = 0.75
        wreck.position = point
        wreck.zRotation = heading
        wreck.zPosition = Z.tracks + 0.5
        worldNode.addChild(wreck)
    }
}
