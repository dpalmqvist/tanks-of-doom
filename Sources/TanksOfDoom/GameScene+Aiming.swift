import AppKit
import SpriteKit
import TanksCore

/// Red corner brackets drawn around the auto-aim target.
final class TargetMarker: SKShapeNode {
    override init() {
        super.init()
        let half: CGFloat = 30
        let arm: CGFloat = 12
        let p = CGMutablePath()
        for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] as [(CGFloat, CGFloat)] {
            let corner = CGPoint(x: sx * half, y: sy * half)
            p.move(to: CGPoint(x: corner.x - sx * arm, y: corner.y))
            p.addLine(to: corner)
            p.addLine(to: CGPoint(x: corner.x, y: corner.y - sy * arm))
        }
        path = p
        strokeColor = .systemRed
        lineWidth = 3
        zPosition = Z.effects + 2
        isHidden = true
        run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.4), .scale(to: 1.0, duration: 0.4)])))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}

extension GameScene {
    static let autoAimRange: CGFloat = 750
    static let manualTurretRate: CGFloat = 2.5

    /// Everything `player` may shoot at: the AI and any other player's tank.
    func hostiles(for player: Player) -> [Hostile] {
        targets(of: .player(player.slot))
    }

    /// Hittable hostiles within main-gun range and in clear line of sight of the player.
    private func targetCandidates(for player: Player) -> [TargetCandidate] {
        let origin = player.tank.position
        return hostiles(for: player).compactMap { hostile in
            guard hostile.canBeHit,
                  hostile.position.distance(to: origin) <= Self.autoAimRange,
                  hasLineOfSight(from: origin, to: hostile.position) else { return nil }
            return TargetCandidate(id: Int(hostile.netID), position: hostile.position.world, isTank: hostile.targetKind == .tank)
        }
    }

    func lockedTarget(of player: Player) -> Hostile? {
        guard player.turretAim.mode == .auto, let id = player.lockedTargetID else { return nil }
        return hostiles(for: player).first { Int($0.netID) == id }
    }

    /// Tab: switch to the next visible target (and back to auto-aim).
    func cycleTarget(for player: Player) {
        player.turretAim.cycleTarget()
        player.lockedTargetID = TargetSelector.next(after: player.lockedTargetID, candidates: targetCandidates(for: player),
                                                    from: player.tank.position.world)?.id
    }

    func updateTurret(for player: Player, dt: Double) {
        let tank = player.tank
        player.turretAim.update(dt: dt, manualHeld: player.input.turretManualHeld)
        let maxStep = PlayerTank.turretTurnRate * CGFloat(dt)
        switch player.turretAim.mode {
        case .manual:
            var direction: CGFloat = 0
            if player.input.turretLeft { direction += 1 }
            if player.input.turretRight { direction -= 1 }
            tank.turretAngle += direction * Self.manualTurretRate * CGFloat(dt)
        case .auto:
            player.lockedTargetID = TargetSelector.autoTarget(current: player.lockedTargetID, candidates: targetCandidates(for: player),
                                                              from: tank.position.world)?.id
            // With nothing to track, the turret settles back over the hull's nose.
            let aim = lockedTarget(of: player).map { tank.position.angle(to: $0.position) } ?? tank.heading
            tank.turretAngle = rotateAngle(tank.turretAngle, toward: aim, maxStep: maxStep)
        }
    }

    /// Corner brackets around whatever the local player's turret is locked onto.
    func updateTargetMarker() {
        if let target = lockedTarget(of: localPlayer) {
            targetMarker.isHidden = false
            targetMarker.position = target.position
        } else {
            targetMarker.isHidden = true
        }
    }
}
