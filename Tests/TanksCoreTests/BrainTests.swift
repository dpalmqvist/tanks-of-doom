import Testing
@testable import TanksCore

private func seeing(_ distance: Double = 300, armor: Double = 1) -> EnemyPerception {
    EnemyPerception(canSeePlayer: true, distanceToPlayer: distance, armorFraction: armor, reachedSearchPoint: false)
}

private func blind(armor: Double = 1, reached: Bool = false) -> EnemyPerception {
    EnemyPerception(canSeePlayer: false, distanceToPlayer: 2000, armorFraction: armor, reachedSearchPoint: reached)
}

@Test func tankPatrolsUntilPlayerSeen() {
    var brain = EnemyTankBrain()
    let r1 = brain.update(blind(), dt: 1)
    #expect(r1 == .patrol)
    let r2 = brain.update(seeing(), dt: 0.1)
    #expect(r2 == .attack)
}

@Test func tankIgnoresPlayerBeyondSightRange() {
    var brain = EnemyTankBrain()
    let r3 = brain.update(seeing(EnemyTankBrain.sightRange + 1), dt: 0.1)
    #expect(r3 == .patrol)
}

@Test func tankSearchesLastKnownPositionThenPatrols() {
    var brain = EnemyTankBrain()
    brain.update(seeing(), dt: 0.1)
    let r4 = brain.update(blind(), dt: 0.1)
    #expect(r4 == .search)
    let r5 = brain.update(blind(), dt: 0.1)
    #expect(r5 == .search)
    let r6 = brain.update(blind(reached: true), dt: 0.1)
    #expect(r6 == .patrol)
}

@Test func tankSearchTimesOut() {
    var brain = EnemyTankBrain()
    brain.update(seeing(), dt: 0.1)
    brain.update(blind(), dt: 0.1)
    let r7 = brain.update(blind(), dt: EnemyTankBrain.searchTimeout)
    #expect(r7 == .patrol)
}

@Test func tankReacquiresDuringSearch() {
    var brain = EnemyTankBrain()
    brain.update(seeing(), dt: 0.1)
    brain.update(blind(), dt: 0.1)
    let r8 = brain.update(seeing(), dt: 0.1)
    #expect(r8 == .attack)
}

@Test func badlyDamagedTankRetreatsThenRecovers() {
    var brain = EnemyTankBrain()
    brain.update(seeing(), dt: 0.1)
    let r9 = brain.update(seeing(armor: 0.2), dt: 0.1)
    #expect(r9 == .retreat)
    let stillSees = brain.update(seeing(armor: 0.2), dt: 10)   // still sees the player
    #expect(stillSees == .retreat)
    let r10 = brain.update(blind(armor: 0.2), dt: EnemyTankBrain.retreatDuration)
    #expect(r10 == .patrol)
    let r11 = brain.update(seeing(armor: 0.2), dt: 0.1)
    #expect(r11 == .retreat)
}

@Test func timeInStateResetsOnTransition() {
    var brain = EnemyTankBrain()
    brain.update(blind(), dt: 3)
    #expect(brain.timeInState == 3)
    brain.update(seeing(), dt: 0.1)
    #expect(brain.timeInState == 0)
    brain.update(seeing(), dt: 0.5)
    #expect(brain.timeInState == 0.5)
}

@Test func infantryWaitsForInitialDelay() {
    var brain = InfantryBrain(kind: .rifleman, initialDelay: 1)
    let r12 = brain.update(dt: 0.5, playerVisible: true, distance: 100)
    #expect(r12 == nil)
    let r13 = brain.update(dt: 0.6, playerVisible: true, distance: 100)
    #expect(r13 == .expose)
    #expect(brain.state == .exposed)
}

@Test func infantryStaysHiddenWithoutSightOrOutOfRange() {
    var brain = InfantryBrain(kind: .rifleman, initialDelay: 0)
    let r14 = brain.update(dt: 0.1, playerVisible: false, distance: 100)
    #expect(r14 == nil)
    let r15 = brain.update(dt: 0.1, playerVisible: true, distance: brain.range + 1)
    #expect(r15 == nil)
    #expect(brain.state == .hidden)
}

@Test func infantryHidesAfterExposureThenWaits() {
    var brain = InfantryBrain(kind: .bazooka, initialDelay: 0)
    let r16 = brain.update(dt: 0.1, playerVisible: true, distance: 100)
    #expect(r16 == .expose)
    let r17 = brain.update(dt: brain.exposedDuration, playerVisible: true, distance: 100)
    #expect(r17 == .hide)
    #expect(brain.state == .hidden)
    let r18 = brain.update(dt: 0.1, playerVisible: true, distance: 100)
    #expect(r18 == nil)
    let r19 = brain.update(dt: brain.hiddenDuration, playerVisible: true, distance: 100)
    #expect(r19 == .expose)
}

@Test func mortarFiresWithoutLineOfSight() {
    var brain = InfantryBrain(kind: .mortar, initialDelay: 0)
    #expect(!brain.needsLineOfSight)
    let r20 = brain.update(dt: 0.1, playerVisible: false, distance: 300)
    #expect(r20 == .expose)
}
