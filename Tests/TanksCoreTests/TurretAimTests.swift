import Testing
@testable import TanksCore

private let origin = WorldPoint(0, 0)
private let farTank = TargetCandidate(id: 1, position: WorldPoint(600, 0), isTank: true)
private let nearTank = TargetCandidate(id: 2, position: WorldPoint(300, 0), isTank: true)
private let nearSoldier = TargetCandidate(id: 3, position: WorldPoint(100, 0), isTank: false)
private let farSoldier = TargetCandidate(id: 4, position: WorldPoint(400, 0), isTank: false)

@Test func tanksOutrankSoldiersThenDistance() {
    let ordered = TargetSelector.prioritized([farSoldier, nearSoldier, farTank, nearTank], from: origin)
    #expect(ordered.map(\.id) == [2, 1, 3, 4])
}

@Test func autoTargetKeepsCurrentLockWhileValid() {
    let all = [farTank, nearTank]
    #expect(TargetSelector.autoTarget(current: 1, candidates: all, from: origin)?.id == 1)
}

@Test func autoTargetPicksBestWhenLockIsLost() {
    #expect(TargetSelector.autoTarget(current: 99, candidates: [nearSoldier, farTank], from: origin)?.id == 1)
    #expect(TargetSelector.autoTarget(current: nil, candidates: [nearSoldier], from: origin)?.id == 3)
    #expect(TargetSelector.autoTarget(current: 1, candidates: [], from: origin) == nil)
}

@Test func cyclingWalksThePriorityOrderAndWraps() {
    let all = [nearSoldier, farTank, nearTank]   // priority order: 2, 1, 3
    #expect(TargetSelector.next(after: nil, candidates: all, from: origin)?.id == 2)
    #expect(TargetSelector.next(after: 2, candidates: all, from: origin)?.id == 1)
    #expect(TargetSelector.next(after: 1, candidates: all, from: origin)?.id == 3)
    #expect(TargetSelector.next(after: 3, candidates: all, from: origin)?.id == 2)
    #expect(TargetSelector.next(after: 99, candidates: all, from: origin)?.id == 2)
    #expect(TargetSelector.next(after: 2, candidates: [], from: origin) == nil)
}

@Test func aimStartsInAutoMode() {
    #expect(TurretAim().mode == .auto)
}

@Test func manualInputOverridesThenReturnsToAuto() {
    var aim = TurretAim()
    aim.manualInput()
    #expect(aim.mode == .manual)
    aim.update(dt: 10, manualHeld: true)            // holding Q/E never times out
    #expect(aim.mode == .manual)
    aim.update(dt: TurretAim.manualHold - 0.1, manualHeld: false)
    #expect(aim.mode == .manual)
    aim.update(dt: 0.2, manualHeld: false)
    #expect(aim.mode == .auto)
}

@Test func cyclingTargetsReturnsToAuto() {
    var aim = TurretAim()
    aim.manualInput()
    #expect(aim.mode == .manual)
    aim.cycleTarget()
    #expect(aim.mode == .auto)
}
