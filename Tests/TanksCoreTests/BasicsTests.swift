import Testing
@testable import TanksCore

@Test func seededRandomIsDeterministic() {
    var a = SeededRandom(seed: 42)
    var b = SeededRandom(seed: 42)
    for _ in 0..<100 { #expect(a.next() == b.next()) }
}

@Test func seededRandomDiffersBySeed() {
    var a = SeededRandom(seed: 1)
    var b = SeededRandom(seed: 2)
    let first = (0..<10).map { _ in a.next() }
    let second = (0..<10).map { _ in b.next() }
    #expect(first != second)
}

@Test func seededRandomHelpersStayInRange() {
    var rng = SeededRandom(seed: 7)
    for _ in 0..<1000 {
        let i = rng.int(3...9)
        #expect((3...9).contains(i))
        let d = rng.double()
        #expect(d >= 0 && d < 1)
    }
    let never = rng.chance(0)
    let always = rng.chance(1)
    #expect(!never)
    #expect(always)
}

@Test func gridPointDistance() {
    #expect(GridPoint(0, 0).distance(to: GridPoint(3, 4)) == 5)
}
