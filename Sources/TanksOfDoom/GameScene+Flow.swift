import AppKit
import SpriteKit
import TanksCore

extension GameScene {
    func togglePause() {
        guard endTimer == nil else { return }
        isGamePaused.toggle()
        worldNode.isPaused = isGamePaused
        input = InputState()
        hud.setPaused(isGamePaused)
    }

    /// Lets a player stranded without fuel end the run instead of being soft-locked.
    func abandonTank() {
        guard !isGamePaused, endTimer == nil, !playerTank.isDestroyed, playerTank.stats.fuel <= 0 else { return }
        damagePlayer(Int(playerTank.stats.armor.rounded(.up)))
    }

    func checkLevelEnd(dt: Double) {
        guard !levelOver else { return }
        if let remaining = endTimer {
            endTimer = remaining - dt
            if remaining - dt <= 0 { finishLevel() }
            return
        }
        if playerTank.isDestroyed {
            victory = false
            endTimer = 2.5
            hud.flash("TANK DESTROYED", color: .systemRed, duration: 2.5)
        } else if enemies.isEmpty {
            victory = true
            endTimer = 2.0
            hud.flash("LEVEL CLEAR!", color: .systemGreen, duration: 2)
        }
    }

    private func finishLevel() {
        levelOver = true
        guard let view else { return }
        if victory {
            runStats.levelsCleared += 1
            view.presentScene(MenuScene.levelComplete(size: size, runStats: runStats, level: levelNumber),
                              transition: .fade(withDuration: 0.8))
        } else {
            let newBest = HighScores.record(runStats)
            view.presentScene(MenuScene.gameOver(size: size, runStats: runStats, newBest: newBest),
                              transition: .fade(withDuration: 0.8))
        }
    }
}
