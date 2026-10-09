import SpriteKit
import TanksCore
import TanksNet

extension GameScene {
    func spawnInfantry() {
        var rng = SeededRandom(seed: level.seed ^ 0x5EED)
        for building in level.buildings { buildingWindows[building.id] = windows(of: building) }
        for spawn in level.infantry {
            addSoldier(spawn, initialDelay: Double.random(in: 0...3, using: &rng))
        }
    }

    func addSoldier(_ spawn: InfantrySpawn, initialDelay: Double) {
        let soldier = InfantryNode(spawn: spawn, initialDelay: initialDelay)
        soldier.netID = makeNetID()
        soldier.position = level.buildings[spawn.buildingID].worldCenter
        worldNode.addChild(soldier)
        infantry.append(soldier)
    }

    /// Perimeter tiles of a building — where a soldier can appear.
    private func windows(of building: Building) -> [GridPoint] {
        let own = Set(building.tiles)
        return building.tiles.filter { t in
            [GridPoint(t.x + 1, t.y), GridPoint(t.x - 1, t.y), GridPoint(t.x, t.y + 1), GridPoint(t.x, t.y - 1)]
                .contains { !own.contains($0) }
        }
    }

    func updateInfantry(dt: Double) {
        let map = level.map
        for soldier in infantry {
            guard let windows = buildingWindows[soldier.buildingID], !windows.isEmpty else { continue }
            let aim = aiTarget(from: level.buildings[soldier.buildingID].worldCenter, sightRange: soldier.brain.range)?.position
            let window = aim.map { p in
                windows.min { map.center($0).distance(to: p) < map.center($1).distance(to: p) }!
            } ?? windows[0]
            let windowPoint = map.center(window)
            let distance = aim.map { Double(windowPoint.distance(to: $0)) } ?? .infinity
            let visible = aim.map { distance <= soldier.brain.range
                && LineOfSight.isClear(in: map, from: window, to: map.grid($0), ignoringBuilding: soldier.buildingID) } ?? false

            switch soldier.brain.update(dt: dt, playerVisible: visible, distance: distance) {
            case .expose:
                soldier.position = windowPoint + CGPoint(angle: windowPoint.angle(to: aim ?? windowPoint), length: tileSize * 0.45)
                soldier.post = window
                soldier.removeAllActions()
                soldier.run(.fadeIn(withDuration: 0.15))
                soldier.cooldown = 0.4   // aim before the first shot
            case .hide:
                soldier.removeAllActions()
                soldier.run(.fadeOut(withDuration: 0.25))
            case nil:
                break
            }

            guard soldier.isExposed, let aim else { continue }
            soldier.zRotation = soldier.position.angle(to: aim)
            soldier.cooldown -= dt
            guard soldier.cooldown <= 0 else { continue }
            let weapon = soldier.kind.weapon
            soldier.cooldown = Combat.spec(weapon).reload
            if weapon == .mortar {
                fireMortar(from: soldier.position, at: aim + CGPoint(x: .random(in: -50...50), y: .random(in: -50...50)))
            } else if let post = soldier.post,
                      LineOfSight.isClear(in: map, from: post, to: map.grid(aim)) {
                // Fire only along a clear line from where the soldier actually stands; their own
                // building blocks too (the post tile itself is an endpoint and never blocks).
                fire(weapon, from: soldier.position, angle: soldier.zRotation + .random(in: -0.07...0.07),
                     shooter: .infantry(soldier.kind), ownerBuilding: soldier.buildingID)
            }
        }
    }

    func infantryKilled(_ soldier: InfantryNode) {
        runStats.infantryKilled += 1
        if isVersus {
            infantryQueue.schedule(InfantrySpawn(kind: soldier.kind, buildingID: soldier.buildingID),
                                   after: VersusTimings.infantryRespawn)
        }
        if soldier.alpha > 0 { fx(.dust(at: soldier.position.vec)) }
        soldier.removeFromParent()
        infantry.removeAll { $0 === soldier }
    }

    func killOccupants(of buildingID: Int) {
        for soldier in infantry where soldier.buildingID == buildingID {
            infantryKilled(soldier)
        }
    }
}
