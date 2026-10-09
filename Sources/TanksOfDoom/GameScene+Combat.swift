import AppKit
import SpriteKit
import TanksCore

extension GameScene {
    enum Impact {
        case target(Hostile)
        case building(Int)
        case solid
    }

    func fire(_ weapon: WeaponKind, from origin: CGPoint, angle: CGFloat, shooter: Combatant, ownerBuilding: Int? = nil) {
        let projectile = Projectile(weapon: weapon, angle: angle, shooter: shooter, ownerBuilding: ownerBuilding)
        projectile.netID = makeNetID()
        projectile.position = origin
        worldNode.addChild(projectile)
        projectiles.append(projectile)
        switch weapon {
        case .mainGun, .enemyShell:
            effects.muzzleFlash(at: origin, angle: angle, big: true)
            playSound(.cannon, at: origin)
        case .bazooka:
            playSound(.rocket, at: origin)
        default:
            effects.muzzleFlash(at: origin, angle: angle, big: false)
            playSound(.machineGun, at: origin, volume: 0.5)
        }
    }

    func fireMortar(from origin: CGPoint, at target: CGPoint) {
        let shell = MortarShell(from: origin, to: target)
        shell.netID = makeNetID()
        worldNode.addChild(shell.marker)
        worldNode.addChild(shell)
        mortars.append(shell)
        playSound(.cannon, at: origin, volume: 0.4)
    }

    func updateWeapons(for player: Player, dt: Double) {
        let tank = player.tank
        guard !tank.isDestroyed, !tank.isHidden else { return }
        let isLocal = player === localPlayer
        tank.mainCooldown -= dt
        tank.machineGunCooldown -= dt

        if player.input.firePrimary && tank.mainCooldown <= 0 {
            if tank.stats.consumeShell() {
                fire(.mainGun, from: tank.muzzlePosition, angle: tank.turretAngle, shooter: .player(player.slot))
                tank.mainCooldown = Combat.spec(.mainGun).reload
                if isLocal { shake(4, duration: 0.15) }
            } else {
                tank.mainCooldown = 0.5
                if isLocal {
                    Audio.shared.play(.empty)
                    effects.floatingText("NO SHELLS", at: tank.position + CGPoint(x: 0, y: 40), color: .systemYellow)
                }
            }
        }

        if player.input.fireSecondary && tank.machineGunCooldown <= 0 {
            if tank.stats.consumeRound() {
                let side = CGPoint(angle: tank.turretAngle - .pi / 2, length: 7)
                let origin = tank.position + CGPoint(angle: tank.turretAngle, length: 30) + side
                fire(.machineGun, from: origin, angle: tank.turretAngle + .random(in: -0.04...0.04), shooter: .player(player.slot))
                tank.machineGunCooldown = Combat.spec(.machineGun).reload
            } else {
                tank.machineGunCooldown = 0.5
                if isLocal {
                    Audio.shared.play(.empty)
                    effects.floatingText("NO MG AMMO", at: tank.position + CGPoint(x: 0, y: 40), color: .systemYellow)
                }
            }
        }
    }

    /// What a shot can hurt: players hit the AI and each other; the AI hits players only.
    func targets(of shooter: Combatant) -> [Hostile] {
        switch shooter {
        case .player(let slot):
            return (enemies as [Hostile]) + (infantry as [Hostile]) + players.filter { $0.slot != slot }.map(\.tank)
        case .enemyTank, .infantry:
            return players.map(\.tank)
        }
    }

    /// Moves every projectile in ≤16 pt sub-steps so fast shots can't tunnel through buildings.
    func updateProjectiles(dt: Double) {
        for projectile in projectiles {
            let start = projectile.position
            let step = CGPoint(x: projectile.velocity.dx * dt, y: projectile.velocity.dy * dt)
            let length = step.length
            let substeps = max(1, Int((length / 16).rounded(.up)))
            var impact: (Impact, CGPoint)?
            for i in 1...substeps {
                let point = start + step * (CGFloat(i) / CGFloat(substeps))
                if let hit = collision(for: projectile, at: point) {
                    impact = (hit, point)
                    break
                }
            }
            if let (hit, point) = impact {
                resolve(hit, projectile: projectile, at: point)
                continue
            }
            projectile.position = start + step
            projectile.remainingRange -= length
            if projectile.weapon == .bazooka {
                projectile.smokeTimer -= dt
                if projectile.smokeTimer <= 0 {
                    effects.smokePuff(at: projectile.position)
                    projectile.smokeTimer = 0.03
                }
            }
            if projectile.remainingRange <= 0 {
                if Combat.spec(projectile.weapon).splashRadius > 0 {
                    detonate(projectile, at: projectile.position, direct: nil)
                } else {
                    removeProjectile(projectile)
                }
            }
        }
    }

    private func collision(for projectile: Projectile, at point: CGPoint) -> Impact? {
        if let target = targets(of: projectile.shooter).first(where: { $0.canBeHit && $0.position.distance(to: point) < $0.hitRadius }) {
            return .target(target)
        }
        let tile = level.map[level.map.grid(point)]
        if let id = tile.buildingID {
            return id == projectile.ownerBuilding ? nil : .building(id)
        }
        return tile == .wall ? .solid : nil
    }

    private func resolve(_ impact: Impact, projectile: Projectile, at point: CGPoint) {
        var direct: AnyObject?
        switch impact {
        case .target(let target):
            direct = target
            let damage = Combat.damage(projectile.weapon, to: target.targetKind, distance: 0)
            if damage > 0 { target.applyDamage(damage, from: projectile.shooter, in: self) }
        case .building(let id):
            let damage = Combat.damage(projectile.weapon, to: .building, distance: 0)
            if damage > 0 { damageBuilding(id, amount: damage) }
        case .solid:
            break
        }
        if Combat.spec(projectile.weapon).splashRadius > 0 {
            detonate(projectile, at: point, direct: direct)
        } else {
            effects.spark(at: point)
            removeProjectile(projectile)
        }
    }

    private func detonate(_ projectile: Projectile, at point: CGPoint, direct: AnyObject?) {
        applySplash(projectile.weapon, at: point, from: projectile.shooter, excluding: direct)
        let heavy = projectile.weapon == .mainGun || projectile.weapon == .enemyShell
        effects.explosion(at: point, scale: heavy ? 1.0 : 0.7)
        playSound(.explosion, at: point, volume: 0.7)
        removeProjectile(projectile)
    }

    /// Splash damage around an impact; `excluding` already took the direct hit.
    func applySplash(_ weapon: WeaponKind, at point: CGPoint, from shooter: Combatant, excluding: AnyObject?) {
        for target in targets(of: shooter) where target.canBeHit && target !== excluding {
            let damage = Combat.damage(weapon, to: target.targetKind, distance: Double(target.position.distance(to: point)))
            if damage > 0 { target.applyDamage(damage, from: shooter, in: self) }
        }
    }

    private func removeProjectile(_ projectile: Projectile) {
        projectile.removeFromParent()
        projectiles.removeAll { $0 === projectile }
    }

    func updateMortars(dt: Double) {
        for shell in mortars {
            guard shell.advance(dt: dt) else { continue }
            applySplash(.mortar, at: shell.target, from: .infantry(.mortar), excluding: nil)
            effects.explosion(at: shell.target, scale: 0.9)
            playSound(.explosion, at: shell.target, volume: 0.8)
            shell.marker.removeFromParent()
            shell.removeFromParent()
            mortars.removeAll { $0 === shell }
        }
    }

    /// `shooter` is nil when the player abandons their own tank.
    func damagePlayer(_ tank: PlayerTank, _ amount: Int, from shooter: Combatant?) {
        guard amount > 0, !tank.isDestroyed, !tank.isInvulnerable else { return }
        tank.stats.takeDamage(amount)
        effects.floatingText("-\(amount)", at: tank.position + CGPoint(x: 0, y: 36), color: .systemRed)
        let isLocal = tank === localPlayer.tank
        if isLocal {
            Audio.shared.play(.hit, volume: 0.8)
            shake(min(14, 3 + CGFloat(amount) * 0.5), duration: 0.25)
        }
        guard tank.isDestroyed else { return }
        effects.explosion(at: tank.position, scale: 2.2)
        playSound(.bigExplosion, at: tank.position)
        tank.showWreck()
        if isLocal { shake(20, duration: 0.6) }
    }

    func damageBuilding(_ id: Int, amount: Int) {
        let result = level.damageBuilding(id, by: amount)
        guard result != .none else { return }
        renderer.update(level.buildings[id])
        if result == .destroyed { buildingDestroyed(id) }
    }

    func buildingDestroyed(_ id: Int) {
        killOccupants(of: id)
        let center = level.buildings[id].worldCenter
        effects.explosion(at: center, scale: 2.0)
        effects.dustPuff(at: center)
        playSound(.bigExplosion, at: center)
        shake(10, duration: 0.4)
        hud.minimap.refresh(map: level.map)
    }
}
