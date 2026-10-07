import SpriteKit
import TanksCore

extension GameScene {
    func setUpHUD() {
        hud = HUD(level: level)
        cameraNode.addChild(hud)
        hud.layout(size: size)
        hud.flash("LEVEL \(levelNumber): DESTROY \(enemies.count) ENEMY TANKS", duration: 3)
    }

    func updateHUD() {
        hud.update(stats: playerTank.stats, level: levelNumber, enemiesLeft: enemies.count, inBase: inBase)
        let spotted = enemies
            .filter { $0.position.distance(to: playerTank.position) <= 900 && hasLineOfSight(from: playerTank.position, to: $0.position) }
            .map(\.position)
        hud.minimap.update(player: playerTank.position, enemies: spotted, target: lockedTarget?.position)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        hud?.layout(size: size)
    }
}
