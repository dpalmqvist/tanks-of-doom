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

    private func targetID(_ hostile: Hostile) -> Int { ObjectIdentifier(hostile).hashValue }

    /// Hittable hostiles within main-gun range and in clear line of sight of the player.
    private func targetCandidates() -> [(candidate: TargetCandidate, node: Hostile)] {
        hostiles.compactMap { hostile in
            guard hostile.canBeHit,
                  hostile.position.distance(to: playerTank.position) <= Self.autoAimRange,
                  hasLineOfSight(from: playerTank.position, to: hostile.position) else { return nil }
            let candidate = TargetCandidate(id: targetID(hostile), position: hostile.position.world, isTank: hostile is EnemyTank)
            return (candidate, hostile)
        }
    }

    var lockedTarget: Hostile? {
        guard turretAim.mode == .auto, let id = lockedTargetID else { return nil }
        return hostiles.first { targetID($0) == id }
    }

    /// Tab: switch to the next visible target (and back to auto-aim).
    func cycleTarget() {
        turretAim.cycleTarget()
        let found = targetCandidates()
        lockedTargetID = TargetSelector.next(after: lockedTargetID, candidates: found.map(\.candidate), from: playerTank.position.world)?.id
    }

    func updateTurret(dt: Double) {
        turretAim.update(dt: dt, manualHeld: input.turretManualHeld)
        let maxStep = PlayerTank.turretTurnRate * CGFloat(dt)
        switch turretAim.mode {
        case .manual:
            var direction: CGFloat = 0
            if input.turretLeft { direction += 1 }
            if input.turretRight { direction -= 1 }
            playerTank.turretAngle += direction * Self.manualTurretRate * CGFloat(dt)
        case .auto:
            let found = targetCandidates()
            lockedTargetID = TargetSelector.autoTarget(current: lockedTargetID, candidates: found.map(\.candidate),
                                                       from: playerTank.position.world)?.id
            // With nothing to track, the turret settles back over the hull's nose.
            let aim = lockedTarget.map { playerTank.position.angle(to: $0.position) } ?? playerTank.heading
            playerTank.turretAngle = rotateAngle(playerTank.turretAngle, toward: aim, maxStep: maxStep)
        }
        if let target = lockedTarget {
            targetMarker.isHidden = false
            targetMarker.position = target.position
        } else {
            targetMarker.isHidden = true
        }
    }
}
