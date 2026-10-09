import SpriteKit
import TanksCore
import TanksNet

extension GameScene {
    static let inputInterval = 1.0 / 30

    func receiveSnapshot(_ snapshot: Snapshot) {
        guard let world = guestWorld, world.buffer.insert(snapshot, receivedAt: lastUpdate) else { return }
        for event in snapshot.events { playLocally(event) }
        for (index, available) in snapshot.pickups.enumerated() where index < pickups.count {
            pickups[index].isAvailable = available
        }
        if let mine = snapshot.players.first(where: { $0.slot == localPlayer.slot }) {
            applyOwnState(mine)
            reconcile(with: mine, acknowledged: snapshot.ackInputSeq)
        }
    }

    /// Everything the host decided about the local player apart from where the tank is.
    private func applyOwnState(_ mine: PlayerSnapshot) {
        let tank = localPlayer.tank
        tank.stats.armor = Double(mine.armor)
        tank.stats.fuel = Double(mine.fuel)
        tank.stats.shells = Int(mine.shells)
        tank.stats.rounds = Int(mine.rounds)
        localPlayer.inBase = mine.has(PlayerSnapshot.inBase)
        localPlayer.lockedTargetID = mine.lockedTarget == 0 ? nil : Int(mine.lockedTarget)
    }

    func updateGuest(dt: Double) {
        guard let world = guestWorld else { return }
        predictOwnTank(dt: dt)
        predictOwnFireFX(dt: dt)
        sendInput(dt: dt)
        guard let frame = world.buffer.frame(at: lastUpdate) else { return }
        for state in frame.to.players {
            let from = frame.from.players.first { $0.slot == state.slot } ?? state
            mirror(player(state.slot), from: from, to: state, t: frame.t)
        }
        mirrorEnemies(frame)
        mirrorSoldiers(frame)
        mirrorShots(frame, dt: dt)
        mirrorMortars(frame)
    }

    private func sendInput(dt: Double) {
        guard let world = guestWorld, let link = versusRole?.link else { return }
        world.inputTimer -= dt
        guard world.inputTimer <= 0 else { return }
        world.inputTimer = Self.inputInterval
        world.inputSeq += 1
        link.send(.input(InputFrame(seq: world.inputSeq, held: localPlayer.input.bits, presses: world.takePresses())))
    }

    private func mirror(_ player: Player, from a: PlayerSnapshot, to b: PlayerSnapshot, t: Double) {
        let tank = player.tank
        let respawning = b.has(PlayerSnapshot.respawning)
        if respawning && !tank.isHidden {
            addWreck(Textures.hull(for: player.slot), at: tank.position, heading: tank.heading)
            tank.isHidden = true
        } else if !respawning && tank.isHidden {
            tank.respawn(at: b.position.cgPoint, heading: CGFloat(b.heading))
            if player === localPlayer { cameraBase = tank.position }
        }
        guard !respawning else { return }
        if player === localPlayer {
            // Our own hull is predicted; the turret is aimed by the host, so follow its newest angle.
            if let latest = guestWorld?.buffer.latest?.players.first(where: { $0.slot == player.slot }) {
                tank.turretAngle = CGFloat(lerpAngle(Float(tank.turretAngle), latest.turret, 0.5))
            }
        } else {
            let from = a.has(PlayerSnapshot.respawning) ? b : a   // don't slide from where it died
            let before = tank.position
            tank.position = from.position.lerp(to: b.position, t).cgPoint
            tank.heading = CGFloat(lerpAngle(from.heading, b.heading, t))
            tank.turretAngle = CGFloat(lerpAngle(from.turret, b.turret, t))
            leaveTracks(tank, moved: tank.position.distance(to: before))
        }
        tank.isInvulnerable = b.has(PlayerSnapshot.invulnerable)
        tank.alpha = tank.isInvulnerable && Int(lastUpdate * 8) % 2 == 0 ? 0.35 : 1
        if b.has(PlayerSnapshot.destroyed) { tank.showWreck() }
    }

    /// Drives our own tank immediately from local keys, and eases in any pending correction.
    private func predictOwnTank(dt: Double) {
        guard let world = guestWorld else { return }
        let tank = localPlayer.tank
        guard !tank.isHidden, !tank.isDestroyed else { return }
        let drove = drive(tank, with: localPlayer.input, dt: dt, blockers: allTanks)
        if drove.distance > 0 { leaveTracks(tank, moved: drove.distance) }
        // These keys reach the host in the next input frame, numbered inputSeq + 1.
        world.history.record(seq: world.inputSeq + 1, input: localPlayer.input, dt: dt)
        let step = world.correction * CGFloat(min(1, dt / GuestWorld.correctionTime))
        tank.position = tank.position + step
        world.correction = world.correction - step
        let turn = world.headingCorrection * CGFloat(min(1, dt / GuestWorld.correctionTime))
        tank.heading += turn
        world.headingCorrection -= turn
    }

    /// Re-runs unconfirmed inputs from the host's position. Small errors are eased in, big ones snap.
    private func reconcile(with mine: PlayerSnapshot, acknowledged seq: UInt32) {
        guard let world = guestWorld else { return }
        let tank = localPlayer.tank
        world.history.acknowledge(through: seq)
        guard !tank.isHidden, !mine.has(PlayerSnapshot.respawning) else {
            world.correction = .zero
            world.headingCorrection = 0
            return
        }
        let shown = tank.position
        let shownHeading = tank.heading
        tank.position = mine.position.cgPoint
        tank.heading = CGFloat(mine.heading)
        for entry in world.history.entries {
            _ = drive(tank, with: entry.input, dt: entry.dt, blockers: allTanks)
        }
        let error = tank.position - shown
        let headingError = normalizeAngle(tank.heading - shownHeading)
        if error.length > GuestWorld.snapDistance {
            world.correction = .zero   // too far off: stay where the host says
            world.headingCorrection = 0
            return
        }
        tank.position = shown
        if abs(headingError) > GuestWorld.headingSnap {
            world.headingCorrection = 0   // keep the replayed heading
        } else {
            tank.heading = shownHeading
            world.headingCorrection = abs(headingError) < GuestWorld.headingIgnore ? 0 : headingError
        }
        world.correction = error.length < GuestWorld.ignoreDistance ? .zero : error
    }

    /// Muzzle flash, sound and kick for our own shots straight away. The host leaves these out for us.
    private func predictOwnFireFX(dt: Double) {
        guard let world = guestWorld else { return }
        let tank = localPlayer.tank
        let input = localPlayer.input
        world.mainCooldown -= dt
        world.machineGunCooldown -= dt
        guard !tank.isHidden, !tank.isDestroyed else { return }
        if input.firePrimary && world.mainCooldown <= 0 && tank.stats.shells > 0 {
            world.mainCooldown = Combat.spec(.mainGun).reload
            playLocally(.muzzleFlash(at: tank.muzzlePosition.vec, angle: Float(tank.turretAngle), big: true))
            playLocally(.sound(.cannon, at: tank.position.vec, volume: 1))
            shake(4, duration: 0.15)
        }
        if input.fireSecondary && world.machineGunCooldown <= 0 && tank.stats.rounds > 0 {
            world.machineGunCooldown = Combat.spec(.machineGun).reload
            let origin = tank.position + CGPoint(angle: tank.turretAngle, length: 30)
            playLocally(.muzzleFlash(at: origin.vec, angle: Float(tank.turretAngle), big: false))
            playLocally(.sound(.machineGun, at: origin.vec, volume: 0.5))
        }
    }

    private func mirrorEnemies(_ frame: SnapshotBuffer.Frame) {
        let live = Set(frame.to.tanks.map(\.id))
        for tank in enemies where !live.contains(tank.netID) {
            addWreck(Textures.enemyHull, at: tank.position, heading: tank.heading)
            tank.removeFromParent()
        }
        enemies.removeAll { !live.contains($0.netID) }
        for state in frame.to.tanks {
            let from = frame.from.tanks.first { $0.id == state.id } ?? state
            let tank = enemies.first { $0.netID == state.id } ?? addMirroredEnemy(state)
            let before = tank.position
            tank.position = from.position.lerp(to: state.position, frame.t).cgPoint
            tank.heading = CGFloat(lerpAngle(from.heading, state.heading, frame.t))
            tank.turretAngle = CGFloat(lerpAngle(from.turret, state.turret, frame.t))
            tank.showHealth(Double(state.health))
            leaveTracks(tank, moved: tank.position.distance(to: before))
        }
    }

    private func addMirroredEnemy(_ state: EnemyTankSnapshot) -> EnemyTank {
        let origin = level.map.grid(state.position.cgPoint)
        let tank = EnemyTank(spawn: EnemyTankSpawn(position: origin, patrol: [origin]), difficulty: Difficulty(level: levelNumber))
        tank.netID = state.id
        tank.position = state.position.cgPoint
        tank.heading = CGFloat(state.heading)
        worldNode.addChild(tank)
        enemies.append(tank)
        return tank
    }

    private func mirrorSoldiers(_ frame: SnapshotBuffer.Frame) {
        let live = Set(frame.to.soldiers.map(\.id))
        for soldier in infantry where !live.contains(soldier.netID) {
            soldier.removeAllActions()
            soldier.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
        infantry.removeAll { !live.contains($0.netID) }
        for state in frame.to.soldiers {
            let soldier = infantry.first { $0.netID == state.id } ?? addMirroredSoldier(state)
            soldier.position = state.position.cgPoint
            soldier.zRotation = CGFloat(state.facing)
        }
    }

    private func addMirroredSoldier(_ state: SoldierSnapshot) -> InfantryNode {
        let soldier = InfantryNode(spawn: InfantrySpawn(kind: state.kind, buildingID: 0), initialDelay: 0)
        soldier.netID = state.id
        soldier.position = state.position.cgPoint
        soldier.run(.fadeIn(withDuration: 0.15))
        worldNode.addChild(soldier)
        infantry.append(soldier)
        return soldier
    }

    private func mirrorShots(_ frame: SnapshotBuffer.Frame, dt: Double) {
        guard let world = guestWorld else { return }
        let live = Set(frame.to.shots.map(\.id))
        for (id, shot) in world.shots where !live.contains(id) {
            shot.removeFromParent()
            world.shots[id] = nil
        }
        for state in frame.to.shots {
            let from = frame.from.shots.first { $0.id == state.id } ?? state
            let shot = world.shots[state.id] ?? addMirroredShot(state)
            shot.position = from.position.lerp(to: state.position, frame.t).cgPoint
            if state.weapon == .bazooka {
                shot.smokeTimer -= dt
                if shot.smokeTimer <= 0 {
                    effects.smokePuff(at: shot.position)
                    shot.smokeTimer = 0.03
                }
            }
        }
    }

    private func addMirroredShot(_ state: ShotSnapshot) -> Projectile {
        let shot = Projectile(weapon: state.weapon, angle: CGFloat(state.angle), shooter: .enemyTank, ownerBuilding: nil)
        shot.netID = state.id
        shot.position = state.position.cgPoint
        worldNode.addChild(shot)
        guestWorld?.shots[state.id] = shot
        return shot
    }

    private func mirrorMortars(_ frame: SnapshotBuffer.Frame) {
        guard let world = guestWorld else { return }
        let live = Set(frame.to.mortars.map(\.id))
        for (id, shell) in world.mortars where !live.contains(id) {
            shell.marker.removeFromParent()
            shell.removeFromParent()
            world.mortars[id] = nil
        }
        for state in frame.to.mortars {
            let from = frame.from.mortars.first { $0.id == state.id } ?? state
            let shell = world.mortars[state.id] ?? addMirroredMortar(state)
            shell.show(progress: CGFloat(from.progress + (state.progress - from.progress) * Float(frame.t)))
        }
    }

    private func addMirroredMortar(_ state: MortarSnapshot) -> MortarShell {
        let shell = MortarShell(from: state.start.cgPoint, to: state.target.cgPoint)
        shell.netID = state.id
        worldNode.addChild(shell.marker)
        worldNode.addChild(shell)
        guestWorld?.mortars[state.id] = shell
        return shell
    }
}
