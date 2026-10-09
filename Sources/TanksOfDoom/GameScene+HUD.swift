import SpriteKit
import TanksCore

extension GameScene {
    func setUpHUD() {
        hud = HUD(level: level, versus: isVersus)
        cameraNode.addChild(hud)
        hud.layout(size: size)
        if let match {
            hud.flash("FIRST TO TAKE ALL \(match.settings.lives) OF THE OTHER'S LIVES WINS", duration: 3)
        } else if !isVersus {
            hud.flash("LEVEL \(levelNumber): DESTROY \(enemies.count) ENEMY TANKS", duration: 3)
        }
    }

    func updateHUD() {
        let tank = localPlayer.tank
        hud.update(stats: tank.stats, level: levelNumber, enemiesLeft: enemies.count, inBase: localPlayer.inBase)
        let spotted = enemies.filter { canSpot($0.position) }.map(\.position)
        let opponent = players.first { $0 !== localPlayer && !$0.tank.isHidden && canSpot($0.tank.position) }
        hud.minimap.update(player: tank.position, enemies: spotted, target: lockedTarget(of: localPlayer)?.position,
                           opponent: opponent.map { (position: $0.tank.position, color: $0.slot.color) })
        if let state = versusHUDState() { hud.updateVersus(state) }
    }

    /// The minimap shows a tank only while the local player has eyes on it.
    func canSpot(_ point: CGPoint) -> Bool {
        let eye = localPlayer.tank.position
        return point.distance(to: eye) <= 900 && hasLineOfSight(from: eye, to: point)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        hud?.layout(size: size)
    }
}
