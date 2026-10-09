import AppKit
import SpriteKit
import TanksCore
import TanksNet

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

    var isGuest: Bool { versusRole?.isGuest == true }

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
        if let winner = match?.winner, endTimer == nil {
            fx(.matchOver(winner: winner), for: .allBut(localPlayer))
            matchEnded(winner: winner)
        }
    }

    /// What the versus overlay should show right now; nil in the campaign.
    func versusHUDState() -> VersusHUDState? {
        guard let role = versusRole else { return nil }
        var state: VersusHUDState
        if let match {
            state = VersusHUDState(localSlot: localPlayer.slot, lives: match.lives,
                                   respawnIn: match.respawnRemaining(localPlayer.slot), latencyMs: nil, notice: nil)
        } else {
            let latest = guestWorld?.buffer.latest
            var lives: [PlayerSlot: Int] = [:]
            for p in latest?.players ?? [] { lives[p.slot] = Int(p.lives) }
            let mine = latest?.players.first { $0.slot == localPlayer.slot }
            let respawnIn = mine.flatMap { $0.has(PlayerSnapshot.respawning) ? Double($0.respawnIn) : nil }
            state = VersusHUDState(localSlot: localPlayer.slot, lives: lives, respawnIn: respawnIn, latencyMs: nil, notice: nil)
        }
        if let link = role.link {
            state.latencyMs = link.latencyMs
            if link.silence > MatchLink.lostAfter && endTimer == nil { state.notice = "CONNECTION LOST…" }
        }
        return state
    }

    /// A player tank just blew up: score it, leave a wreck and take the tank off the field until it respawns.
    func playerDestroyed(_ tank: PlayerTank, by killer: Combatant?) {
        guard match != nil, let victim = players.first(where: { $0.tank === tank }) else { return }
        match?.playerDied(victim.slot, killer: killer)
        fx(.kill(killer: killer, victim: victim.slot))
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
        fx(.dust(at: player.tank.position.vec))
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
        matchWinner = winner
        leavePromptShown = false
        hud.setLeavePrompt(false)
        let won = winner == localPlayer.slot
        endTimer = 3
        hud.flash(won ? "VICTORY!" : "DEFEAT", color: won ? .systemGreen : .systemRed, duration: 3)
    }

    func versusResult() -> VersusResult {
        var lives: [PlayerSlot: Int] = [:]
        var kills: [PlayerSlot: Int] = [:]
        if let match {
            lives = match.lives
            kills = match.kills
        } else {
            for p in guestWorld?.buffer.latest?.players ?? [] {
                lives[p.slot] = Int(p.lives)
                kills[p.slot] = Int(p.kills)
            }
        }
        return VersusResult(winner: matchWinner ?? localPlayer.slot, localSlot: localPlayer.slot, lives: lives, kills: kills)
    }
}
