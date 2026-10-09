import SpriteKit
import TanksCore
import TanksNet

extension GameScene {
    static let snapshotInterval = 0.05

    func attach(_ link: MatchLink) {
        link.onMessage = { [weak self] message in self?.receive(message) }
        link.onClosed = { [weak self] reason in self?.linkClosed(reason) }
    }

    func receive(_ message: GameMessage) {
        switch message {
        case .input(let frame): remoteInput.receive(frame, at: lastUpdate)
        case .snapshot(let snapshot): receiveSnapshot(snapshot)
        case .leave: linkClosed("Opponent left")
        default: break
        }
    }

    /// The other side is gone: whoever is still here wins.
    func linkClosed(_ reason: String?) {
        guard isVersus, endTimer == nil else { return }
        hud.flash((reason ?? "Connection lost").uppercased(), color: .systemOrange, duration: 3)
        match?.playerLeft(localPlayer.slot.opponent)
        matchEnded(winner: localPlayer.slot)
    }

    /// Gives up on a silent opponent.
    func watchConnection() {
        guard let link = versusRole?.link, endTimer == nil, link.silence > MatchLink.giveUpAfter else { return }
        linkClosed("Connection lost")
    }

    /// Host: the guest's latest keys drive their Player; one-shot presses act once.
    func applyRemoteInput() {
        guard let guest = remotePlayer else { return }
        guest.input = InputState(bits: remoteInput.heldKeys(at: lastUpdate))
        let presses = remoteInput.takePresses()
        if presses & InputFrame.cycleTarget != 0 { cycleTarget(for: guest) }
        if presses & InputFrame.manualTurret != 0 { guest.turretAim.manualInput() }
        if presses & InputFrame.abandon != 0 { abandonTank(guest) }
    }

    func sendSnapshotIfDue(dt: Double) {
        snapshotTimer -= dt
        guard snapshotTimer <= 0, let link = versusRole?.link else { return }
        snapshotTimer = Self.snapshotInterval
        hostTick += 1
        link.send(.snapshot(makeSnapshot()))
        outgoingEvents.removeAll()
    }

    func makeSnapshot() -> Snapshot {
        Snapshot(
            tick: hostTick, time: lastUpdate, ackInputSeq: remoteInput.lastSeq,
            players: players.map(snapshot(of:)),
            tanks: enemies.map {
                EnemyTankSnapshot(id: $0.netID, position: $0.position.vec, heading: Float($0.heading),
                                  turret: Float($0.turretAngle), health: Float($0.armorFraction))
            },
            soldiers: infantry.filter(\.isExposed).map {
                SoldierSnapshot(id: $0.netID, kind: $0.kind, position: $0.position.vec, facing: Float($0.zRotation))
            },
            shots: projectiles.map {
                ShotSnapshot(id: $0.netID, weapon: $0.weapon, position: $0.position.vec, angle: Float($0.zRotation))
            },
            mortars: mortars.map {
                MortarSnapshot(id: $0.netID, start: $0.start.vec, target: $0.target.vec, progress: Float($0.progress))
            },
            pickups: pickups.map(\.isAvailable),
            events: outgoingEvents)
    }

    private func snapshot(of player: Player) -> PlayerSnapshot {
        let tank = player.tank
        let slot = player.slot
        var flags: UInt8 = 0
        if tank.isDestroyed { flags |= PlayerSnapshot.destroyed }
        if tank.isInvulnerable { flags |= PlayerSnapshot.invulnerable }
        if tank.isHidden { flags |= PlayerSnapshot.respawning }
        if player.inBase { flags |= PlayerSnapshot.inBase }
        return PlayerSnapshot(
            slot: slot, position: tank.position.vec, heading: Float(tank.heading), turret: Float(tank.turretAngle),
            armor: Float(tank.stats.armor), fuel: Float(tank.stats.fuel),
            shells: UInt16(clamping: tank.stats.shells), rounds: UInt16(clamping: tank.stats.rounds),
            lives: UInt8(clamping: match?.lives[slot] ?? 0), kills: UInt16(clamping: match?.kills[slot] ?? 0),
            flags: flags, respawnIn: Float(match?.respawnRemaining(slot) ?? 0),
            lockedTarget: lockedTarget(of: player)?.netID ?? 0)
    }
}
