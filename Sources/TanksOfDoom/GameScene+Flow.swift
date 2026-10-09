import AppKit
import SpriteKit
import TanksCore

extension GameScene {
    func togglePause() {
        guard endTimer == nil, versusRole?.link == nil else { return }
        isGamePaused.toggle()
        worldNode.isPaused = isGamePaused
        localPlayer.input = InputState()
        hud.setPaused(isGamePaused)
    }

    /// Lets a player stranded without fuel give up the tank instead of being soft-locked.
    func abandonTank(_ player: Player) {
        let tank = player.tank
        guard !isGamePaused, endTimer == nil, !tank.isDestroyed, !tank.isHidden, tank.stats.fuel <= 0 else { return }
        damagePlayer(tank, Int(tank.stats.armor.rounded(.up)), from: nil)
    }

    func checkLevelEnd(dt: Double) {
        guard !levelOver else { return }
        if let remaining = endTimer {
            endTimer = remaining - dt
            if remaining - dt <= 0 { finishLevel() }
            return
        }
        guard !isVersus else { return }   // versus ends through the match rules
        if localPlayer.tank.isDestroyed {
            victory = false
            endTimer = 2.5
            hud.flash("TANK DESTROYED", color: .systemRed, duration: 2.5)
        } else if enemies.isEmpty {
            victory = true
            endTimer = 2.0
            hud.flash("LEVEL CLEAR!", color: .systemGreen, duration: 2)
        }
    }

    /// Quit a networked match from the leave prompt; the opponent is told and wins.
    func leaveMatch() {
        guard let link = versusRole?.link, let view else { return }
        link.send(.leave)
        link.close()
        levelOver = true
        view.presentScene(MenuScene.title(size: size), transition: .fade(withDuration: 0.6))
    }

    private func finishLevel() {
        levelOver = true
        guard let view else { return }
        if isVersus {
            if let link = versusRole?.link {
                let result = VersusResultScene(size: size, result: versusResult(), link: link,
                                               settings: match?.settings ?? MatchSettings(), isHost: versusRole?.isHost == true,
                                               opponentWantsRematch: opponentRequestedRematch, opponentLeft: opponentLeft)
                view.presentScene(result, transition: .fade(withDuration: 0.8))
            } else {
                view.presentScene(MenuScene.versusResult(size: size, result: versusResult()), transition: .fade(withDuration: 0.8))
            }
            return
        }
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
