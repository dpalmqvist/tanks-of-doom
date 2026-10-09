import AppKit
import SpriteKit
import TanksCore

/// What the result screen shows.
struct VersusResult {
    let winner: PlayerSlot
    let localSlot: PlayerSlot
    let lives: [PlayerSlot: Int]
    let kills: [PlayerSlot: Int]
}

extension GameScene {
    var isVersus: Bool {
        if case .versus = mode { return true }
        return false
    }

    var versusRole: VersusRole? {
        if case .versus(let role) = mode { return role }
        return nil
    }

    func player(_ slot: PlayerSlot) -> Player {
        players.first { $0.slot == slot }!
    }

    /// Lives, respawns and AI/pickup replenishment, where the match is simulated (host or hot-seat).
    func updateVersus(dt: Double) {
        guard match != nil else { return }
        for slot in match?.tick(dt: dt) ?? [] { respawn(player(slot)) }
        for player in players {
            let tank = player.tank
            tank.isInvulnerable = match?.isInvulnerable(player.slot) ?? false
            tank.alpha = tank.isInvulnerable && Int(lastUpdate * 8) % 2 == 0 ? 0.35 : 1
        }
        for spawn in aiTankQueue.tick(dt: dt) { respawnEnemy(spawn) }
        for spawn in infantryQueue.tick(dt: dt) where !level.buildings[spawn.buildingID].isDestroyed {
            addSoldier(spawn, initialDelay: 0)
        }
        for index in pickupQueue.tick(dt: dt) { pickups[index].isAvailable = true }
        if let winner = match?.winner { matchEnded(winner: winner) }
    }

    /// What the versus overlay should show right now; nil in the campaign.
    func versusHUDState() -> VersusHUDState? {
        guard let match else { return nil }
        return VersusHUDState(localSlot: localPlayer.slot, lives: match.lives,
                              respawnIn: match.respawnRemaining(localPlayer.slot), latencyMs: nil, notice: nil)
    }

    /// A player tank just blew up: score it, leave a wreck and take the tank off the field until it respawns.
    func playerDestroyed(_ tank: PlayerTank, by killer: Combatant?) {
        guard match != nil, let victim = players.first(where: { $0.tank === tank }) else { return }
        match?.playerDied(victim.slot, killer: killer)
        hud.addKillFeed(KillFeed.line(killer: killer, victim: victim.slot, viewer: localPlayer.slot))
        addWreck(Textures.hull(for: victim.slot), at: tank.position, heading: tank.heading)
        tank.isHidden = true
    }

    func respawn(_ player: Player) {
        var rng = SystemRandomNumberGenerator()
        let opponent = players.first { $0 !== player && !$0.tank.isHidden }.map { level.map.grid($0.tank.position) }
        let spot = RespawnPicker.playerSpawn(in: level.map, reachableFrom: level.bases[player.slot.baseIndex].center,
                                             opponent: opponent, aiTanks: enemies.map { level.map.grid($0.position) },
                                             using: &rng)
        player.tank.respawn(at: level.map.center(spot), heading: .random(in: -.pi ... .pi))
        player.turretAim = TurretAim()
        player.lockedTargetID = nil
        effects.dustPuff(at: player.tank.position)
        if player === localPlayer { cameraBase = player.tank.position }
    }

    func respawnEnemy(_ spawn: EnemyTankSpawn) {
        var rng = SystemRandomNumberGenerator()
        let spot = RespawnPicker.aiTankSpawn(in: level.map, reachableFrom: level.bases[0].center,
                                             players: players.map { level.map.grid($0.tank.position) }, using: &rng)
        addEnemy(spawn, at: level.map.center(spot))
    }

    func matchEnded(winner: PlayerSlot) {
        guard endTimer == nil else { return }
        let won = winner == localPlayer.slot
        endTimer = 3
        hud.flash(won ? "VICTORY!" : "DEFEAT", color: won ? .systemGreen : .systemRed, duration: 3)
    }

    func versusResult() -> VersusResult {
        let state = match ?? MatchState(settings: MatchSettings())
        return VersusResult(winner: state.winner ?? localPlayer.slot, localSlot: localPlayer.slot,
                            lives: state.lives, kills: state.kills)
    }
}
