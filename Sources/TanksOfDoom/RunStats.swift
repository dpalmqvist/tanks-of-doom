import Foundation

struct RunStats {
    var levelsCleared = 0
    var tanksDestroyed = 0
    var infantryKilled = 0

    var kills: Int { tanksDestroyed + infantryKilled }
}

/// Best run, ranked by levels cleared, then kills.
enum HighScores {
    private static let defaults = UserDefaults.standard

    static var bestLevels: Int { defaults.integer(forKey: "bestLevels") }
    static var bestKills: Int { defaults.integer(forKey: "bestKills") }

    @discardableResult
    static func record(_ run: RunStats) -> Bool {
        let better = run.levelsCleared > bestLevels || (run.levelsCleared == bestLevels && run.kills > bestKills)
        if better {
            defaults.set(run.levelsCleared, forKey: "bestLevels")
            defaults.set(run.kills, forKey: "bestKills")
        }
        return better
    }
}
