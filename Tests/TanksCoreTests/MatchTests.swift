import Testing
@testable import TanksCore

@Test func slotsKnowTheirOpponentAndBase() {
    #expect(PlayerSlot.host.opponent == .guest)
    #expect(PlayerSlot.guest.opponent == .host)
    #expect(PlayerSlot.host.baseIndex == 0)
    #expect(PlayerSlot.guest.baseIndex == 1)
}

@Test func intensityMapsToCampaignDifficulty() {
    #expect(AIIntensity.allCases.map(\.difficultyLevel) == [1, 3, 6])
    #expect(AIIntensity.allCases.map(\.name) == ["LIGHT", "NORMAL", "HEAVY"])
}

@Test func settingsClampLivesAndWrapIntensity() {
    var s = MatchSettings(lives: 42, seed: 1)
    #expect(s.lives == 9)
    #expect(MatchSettings(lives: 0).lives == 1)
    #expect(MatchSettings().lives == 3)
    #expect(MatchSettings().aiIntensity == .normal)
    s.changeLives(by: 1)
    #expect(s.lives == 9)
    s.changeLives(by: -3)
    #expect(s.lives == 6)
    s.changeIntensity(by: 1)
    #expect(s.aiIntensity == .heavy)
    s.changeIntensity(by: 1)
    #expect(s.aiIntensity == .light)
    s.changeIntensity(by: -1)
    #expect(s.aiIntensity == .heavy)
}

@Test func killFeedNamesAreFromTheViewersPointOfView() {
    #expect(KillFeed.line(killer: .player(.host), victim: .guest, viewer: .host) == "You destroyed Opponent")
    #expect(KillFeed.line(killer: .player(.host), victim: .guest, viewer: .guest) == "Opponent destroyed You")
    #expect(KillFeed.line(killer: .infantry(.bazooka), victim: .host, viewer: .host) == "Bazooka destroyed You")
    #expect(KillFeed.line(killer: .enemyTank, victim: .host, viewer: .guest) == "Rust Brigade tank destroyed Opponent")
    #expect(KillFeed.line(killer: nil, victim: .guest, viewer: .guest) == "You abandoned your tank")
}

@Test func deathCostsALifeAndStartsARespawn() {
    var m = MatchState(settings: MatchSettings(lives: 3))
    m.playerDied(.host, killer: .enemyTank)
    #expect(m.lives[.host] == 2)
    #expect(m.kills[.guest] == 0)            // AI kills credit nobody
    #expect(m.isRespawning(.host))
    #expect(m.respawnRemaining(.host) == MatchState.respawnDelay)
    m.playerDied(.host, killer: .enemyTank)  // already dead: ignored
    #expect(m.lives[.host] == 2)
}

@Test func opponentKillsAreCredited() {
    var m = MatchState(settings: MatchSettings(lives: 3))
    m.playerDied(.guest, killer: .player(.host))
    #expect(m.kills[.host] == 1)
}

@Test func respawnHappensAfterTheDelayWithInvulnerability() {
    var m = MatchState(settings: MatchSettings(lives: 3))
    m.playerDied(.guest, killer: nil)
    #expect(m.tick(dt: 2.9).isEmpty)
    #expect(m.tick(dt: 0.2) == [.guest])
    #expect(!m.isRespawning(.guest))
    #expect(m.isInvulnerable(.guest))
    #expect(m.tick(dt: 2.9).isEmpty)
    #expect(m.isInvulnerable(.guest))
    _ = m.tick(dt: 0.2)
    #expect(!m.isInvulnerable(.guest))
}

@Test func firingEndsInvulnerability() {
    var m = MatchState(settings: MatchSettings(lives: 3))
    m.playerDied(.host, killer: nil)
    _ = m.tick(dt: 3.1)
    #expect(m.isInvulnerable(.host))
    m.playerFired(.host)
    #expect(!m.isInvulnerable(.host))
}

@Test func losingTheLastLifeEndsTheMatch() {
    var m = MatchState(settings: MatchSettings(lives: 1))
    m.playerDied(.host, killer: .player(.guest))
    #expect(m.isOver)
    #expect(m.winner == .guest)
    #expect(m.lives[.host] == 0)
    #expect(!m.isRespawning(.host))
    #expect(m.tick(dt: 10).isEmpty)
}

@Test func simultaneousLastLifeDeathsKeepTheFirstWinner() {
    var m = MatchState(settings: MatchSettings(lives: 1))
    m.playerDied(.host, killer: .infantry(.mortar))
    m.playerDied(.guest, killer: .infantry(.mortar))
    #expect(m.winner == .guest)
    #expect(m.lives[.guest] == 1)
    #expect(m.lives[.host] == 0)
}

@Test func leavingHandsTheWinToTheOpponent() {
    var m = MatchState(settings: MatchSettings(lives: 3))
    m.playerLeft(.guest)
    #expect(m.winner == .host)
    m.playerLeft(.host)
    #expect(m.winner == .host)
}
