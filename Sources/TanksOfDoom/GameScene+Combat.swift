import AppKit
import SpriteKit
import TanksCore

extension GameScene {
    enum Impact {
        case hostile(Hostile)
        case player
        case building(Int)
        case solid
    }

    func fire(_ weapon: WeaponKind, from origin: CGPoint, angle: CGFloat, byPlayer: Bool, ownerBuilding: Int? = nil) {
        let projectile = Projectile(weapon: weapon, angle: angle, byPlayer: byPlayer, ownerBuilding: ownerBuilding)
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
        worldNode.addChild(shell.marker)
        worldNode.addChild(shell)
        mortars.append(shell)
        playSound(.cannon, at: origin, volume: 0.4)
    }

    func updatePlayerWeapons(dt: Double) {
        guard !playerTank.isDestroyed else { return }
        playerTank.mainCooldown -= dt
        playerTank.machineGunCooldown -= dt

        if input.firePrimary && playerTank.mainCooldown <= 0 {
            if playerTank.stats.consumeShell() {
                fire(.mainGun, from: playerTank.muzzlePosition, angle: playerTank.turretAngle, byPlayer: true)
                playerTank.mainCooldown = Combat.spec(.mainGun).reload
                shake(4, duration: 0.15)
            } else {
                playerTank.mainCooldown = 0.5
                Audio.shared.play(.empty)
                effects.floatingText("NO SHELLS", at: playerTank.position + CGPoint(x: 0, y: 40), color: .systemYellow)
            }
        }

        if input.fireSecondary && playerTank.machineGunCooldown <= 0 {
            if playerTank.stats.consumeRound() {
                let side = CGPoint(angle: playerTank.turretAngle - .pi / 2, length: 7)
                let origin = playerTank.position + CGPoint(angle: playerTank.turretAngle, length: 30) + side
                fire(.machineGun, from: origin, angle: playerTank.turretAngle + .random(in: -0.04...0.04), byPlayer: true)
                playerTank.machineGunCooldown = Combat.spec(.machineGun).reload
            } else {
                playerTank.machineGunCooldown = 0.5
                Audio.shared.play(.empty)
                effects.floatingText("NO MG AMMO", at: playerTank.position + CGPoint(x: 0, y: 40), color: .systemYellow)
            }
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
        if projectile.byPlayer {
            if let target = hostiles.first(where: { $0.canBeHit && $0.position.distance(to: point) < $0.hitRadius }) {
                return .hostile(target)
            }
        } else if !playerTank.isDestroyed && playerTank.position.distance(to: point) < TankNode.radius {
            return .player
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
        case .hostile(let target):
            direct = target
            let damage = Combat.damage(projectile.weapon, to: target.targetKind, distance: 0)
            if damage > 0 { target.applyDamage(damage, in: self) }
        case .player:
            direct = playerTank
            damagePlayer(Combat.damage(projectile.weapon, to: .tank, distance: 0))
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
        applySplash(projectile.weapon, at: point, byPlayer: projectile.byPlayer, excluding: direct)
        let heavy = projectile.weapon == .mainGun || projectile.weapon == .enemyShell
        effects.explosion(at: point, scale: heavy ? 1.0 : 0.7)
        playSound(.explosion, at: point, volume: 0.7)
        removeProjectile(projectile)
    }

    /// Splash damage around an impact; `excluding` already took the direct hit.
    func applySplash(_ weapon: WeaponKind, at point: CGPoint, byPlayer: Bool, excluding: AnyObject?) {
        if byPlayer {
            for target in hostiles where target.canBeHit && target !== excluding {
                let damage = Combat.damage(weapon, to: target.targetKind, distance: Double(target.position.distance(to: point)))
                if damage > 0 { target.applyDamage(damage, in: self) }
            }
        } else if excluding !== playerTank && !playerTank.isDestroyed {
            let damage = Combat.damage(weapon, to: .tank, distance: Double(playerTank.position.distance(to: point)))
            if damage > 0 { damagePlayer(damage) }
        }
    }

    private func removeProjectile(_ projectile: Projectile) {
        projectile.removeFromParent()
        projectiles.removeAll { $0 === projectile }
    }

    func updateMortars(dt: Double) {
        for shell in mortars {
            guard shell.advance(dt: dt) else { continue }
            applySplash(.mortar, at: shell.target, byPlayer: false, excluding: nil)
            effects.explosion(at: shell.target, scale: 0.9)
            playSound(.explosion, at: shell.target, volume: 0.8)
            shell.marker.removeFromParent()
            shell.removeFromParent()
            mortars.removeAll { $0 === shell }
        }
    }

    func damagePlayer(_ amount: Int) {
        guard amount > 0, !playerTank.isDestroyed else { return }
        playerTank.stats.takeDamage(amount)
        effects.floatingText("-\(amount)", at: playerTank.position + CGPoint(x: 0, y: 36), color: .systemRed)
        Audio.shared.play(.hit, volume: 0.8)
        shake(min(14, 3 + CGFloat(amount) * 0.5), duration: 0.25)
        if playerTank.isDestroyed {
            effects.explosion(at: playerTank.position, scale: 2.2)
            playSound(.bigExplosion, at: playerTank.position)
            playerTank.showWreck()
            shake(20, duration: 0.6)
        }
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
    }
}
