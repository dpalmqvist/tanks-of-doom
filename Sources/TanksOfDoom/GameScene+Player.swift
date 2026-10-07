import SpriteKit
import TanksCore

extension GameScene {
    func updatePlayer(dt: Double) {
        guard !playerTank.isDestroyed else { return }
        let map = level.map
        var turn: CGFloat = 0
        if input.left { turn += 1 }
        if input.right { turn -= 1 }
        var drive: CGFloat = 0
        if input.forward { drive += 1 }
        if input.backward { drive -= 1 }

        var moving = false
        if playerTank.stats.canMove {
            if turn != 0 {
                playerTank.heading += turn * PlayerTank.turnRate * CGFloat(dt)
                moving = true
            }
            if drive != 0 {
                let speed = (drive > 0 ? PlayerTank.forwardSpeed : PlayerTank.reverseSpeed)
                    * CGFloat(map.speedMultiplier(at: playerTank.position.world))
                let moved = playerTank.move(by: CGPoint(angle: playerTank.heading, length: drive * speed * CGFloat(dt)),
                                            in: map, blockers: [])
                if moved > 0 {
                    moving = true
                    leaveTracks(playerTank, moved: moved)
                }
            }
        }
        let hadFuel = playerTank.stats.fuel > 0
        playerTank.stats.burnFuel(seconds: dt, moving: moving)
        if hadFuel && playerTank.stats.fuel <= 0 {
            effects.floatingText("OUT OF FUEL!", at: playerTank.position + CGPoint(x: 0, y: 44), color: .systemOrange)
        }

        let aim = playerTank.position.angle(to: aimPoint)
        playerTank.turretAngle = rotateAngle(playerTank.turretAngle, toward: aim, maxStep: PlayerTank.turretTurnRate * CGFloat(dt))

        inBase = level.isBase(map.grid(playerTank.position))
        if inBase { playerTank.stats.applyBase(seconds: dt) }
        collectPickups()
    }

    func leaveTracks(_ tank: TankNode, moved: CGFloat) {
        tank.distanceSinceTrack += moved
        guard tank.distanceSinceTrack >= 12 else { return }
        tank.distanceSinceTrack = 0
        effects.trackMark(at: tank.position, angle: tank.heading)
    }

    func collectPickups() {
        for pickup in pickups where pickup.position.distance(to: playerTank.position) < 40 {
            playerTank.stats.collect(pickup.kind)
            effects.floatingText(pickup.kind == .gas ? "+GAS" : "+AMMO", at: pickup.position, color: .systemGreen)
            Audio.shared.play(.pickup)
            pickup.removeFromParent()
            pickups.removeAll { $0 === pickup }
        }
    }
}
