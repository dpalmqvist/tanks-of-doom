import SpriteKit
import TanksCore
import TanksNet

extension GameScene {
    func updatePlayers(dt: Double) {
        for player in players {
            updatePlayer(player, dt: dt)
            updateWeapons(for: player, dt: dt)
        }
    }

    func updatePlayer(_ player: Player, dt: Double) {
        let tank = player.tank
        guard !tank.isDestroyed, !tank.isHidden else { return }
        let drove = drive(tank, with: player.input, dt: dt, blockers: allTanks)
        if drove.distance > 0 { leaveTracks(tank, moved: drove.distance) }
        let hadFuel = tank.stats.fuel > 0
        tank.stats.burnFuel(seconds: dt, moving: drove.moving)
        if hadFuel && tank.stats.fuel <= 0 {
            fx(.text("OUT OF FUEL!", at: (tank.position + CGPoint(x: 0, y: 44)).vec, color: .orange))
        }

        updateTurret(for: player, dt: dt)

        player.inBase = level.baseIndex(at: level.map.grid(tank.position)) == player.slot.baseIndex
        if player.inBase { tank.stats.applyBase(seconds: dt) }
        collectPickups(for: player)
    }

    /// Turns and drives `tank` as `input` asks. Shared by the simulation and the guest's own-tank prediction,
    /// so it touches nothing but the tank.
    func drive(_ tank: PlayerTank, with input: InputState, dt: Double, blockers: [TankNode]) -> (distance: CGFloat, moving: Bool) {
        guard tank.stats.canMove else { return (0, false) }
        var turn: CGFloat = 0
        if input.left { turn += 1 }
        if input.right { turn -= 1 }
        var throttle: CGFloat = 0
        if input.forward { throttle += 1 }
        if input.backward { throttle -= 1 }

        var moving = false
        if turn != 0 {
            tank.heading += turn * PlayerTank.turnRate * CGFloat(dt)
            moving = true
        }
        var distance: CGFloat = 0
        if throttle != 0 {
            let speed = (throttle > 0 ? PlayerTank.forwardSpeed : PlayerTank.reverseSpeed)
                * CGFloat(level.map.speedMultiplier(at: tank.position.world))
            distance = tank.move(by: CGPoint(angle: tank.heading, length: throttle * speed * CGFloat(dt)),
                                 in: level.map, blockers: blockers)
            if distance > 0 { moving = true }
        }
        return (distance, moving)
    }

    func leaveTracks(_ tank: TankNode, moved: CGFloat) {
        tank.distanceSinceTrack += moved
        guard tank.distanceSinceTrack >= 12 else { return }
        tank.distanceSinceTrack = 0
        effects.trackMark(at: tank.position, angle: tank.heading)
    }

    func collectPickups(for player: Player) {
        let tank = player.tank
        for (index, pickup) in pickups.enumerated() where pickup.isAvailable && pickup.position.distance(to: tank.position) < 40 {
            tank.stats.collect(pickup.kind)
            fx(.text(pickup.kind == .gas ? "+GAS" : "+AMMO", at: pickup.position.vec, color: .green))
            fx(.uiSound(.pickup, volume: 1), for: .only(player))
            pickup.isAvailable = false
            if isVersus { pickupQueue.schedule(index, after: VersusTimings.pickupRespawn) }
        }
    }
}
