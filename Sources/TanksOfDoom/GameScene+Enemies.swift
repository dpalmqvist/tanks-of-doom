import SpriteKit
import TanksCore

extension GameScene {
    var allTanks: [TankNode] {
        var tanks: [TankNode] = [playerTank]
        tanks.append(contentsOf: enemies)
        return tanks
    }

    func spawnEnemies() {
        let difficulty = Difficulty(level: levelNumber)
        for spawn in level.enemyTanks {
            let tank = EnemyTank(spawn: spawn, difficulty: difficulty)
            tank.position = level.map.center(spawn.position)
            tank.heading = .random(in: -.pi ... .pi)
            tank.turretAngle = tank.heading
            worldNode.addChild(tank)
            enemies.append(tank)
        }
    }

    func updateEnemies(dt: Double) {
        for tank in enemies { tank.update(dt: dt, scene: self) }
    }

    func hasLineOfSight(from a: CGPoint, to b: CGPoint, ignoringBuilding: Int? = nil) -> Bool {
        LineOfSight.isClear(in: level.map, from: level.map.grid(a), to: level.map.grid(b), ignoringBuilding: ignoringBuilding)
    }

    func enemyDestroyed(_ tank: EnemyTank) {
        runStats.tanksDestroyed += 1
        effects.explosion(at: tank.position, scale: 1.8)
        playSound(.bigExplosion, at: tank.position)
        shake(8, duration: 0.3)
        let wreck = SKSpriteNode(texture: Textures.enemyHull)
        wreck.color = .black
        wreck.colorBlendFactor = 0.75
        wreck.position = tank.position
        wreck.zRotation = tank.heading
        wreck.zPosition = Z.tracks + 0.5
        worldNode.addChild(wreck)
        tank.removeFromParent()
        enemies.removeAll { $0 === tank }
    }
}
