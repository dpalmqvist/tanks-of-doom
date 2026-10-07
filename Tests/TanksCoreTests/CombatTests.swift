import Testing
@testable import TanksCore

@Test func machineGunOnlyHurtsInfantry() {
    #expect(Combat.damage(.machineGun, to: .infantry, distance: 0) == 4)
    #expect(Combat.damage(.machineGun, to: .tank, distance: 0) == 0)
    #expect(Combat.damage(.machineGun, to: .building, distance: 0) == 0)
}

@Test func mainGunHurtsEverythingWithSplashFalloff() {
    let spec = Combat.spec(.mainGun)
    #expect(Combat.damage(.mainGun, to: .tank, distance: 0) == 40)
    #expect(Combat.damage(.mainGun, to: .building, distance: 0) == 40)
    #expect(Combat.damage(.mainGun, to: .infantry, distance: spec.splashRadius / 2) == 20)
    #expect(Combat.damage(.mainGun, to: .tank, distance: spec.splashRadius) == 0)
    #expect(Combat.damage(.mainGun, to: .tank, distance: spec.splashRadius + 50) == 0)
}

@Test func enemyWeaponsOnlyHurtThePlayer() {
    for weapon in [WeaponKind.enemyShell, .rifle, .enemyMachineGun, .bazooka, .mortar] {
        #expect(Combat.damage(weapon, to: .tank, distance: 0) > 0)
        #expect(Combat.damage(weapon, to: .building, distance: 0) == 0)
        #expect(Combat.damage(weapon, to: .infantry, distance: 0) == 0)
    }
}

@Test func bazookaIsSlowAndHeavy() {
    #expect(Combat.spec(.bazooka).projectileSpeed < Combat.spec(.rifle).projectileSpeed)
    #expect(Combat.spec(.bazooka).damage > Combat.spec(.rifle).damage)
    #expect(Combat.spec(.mainGun).reload == 1.2)
}

@Test func infantryWeapons() {
    #expect(InfantryKind.rifleman.weapon == .rifle)
    #expect(InfantryKind.machineGunner.weapon == .enemyMachineGun)
    #expect(InfantryKind.bazooka.weapon == .bazooka)
    #expect(InfantryKind.mortar.weapon == .mortar)
}

@Test func freshTankIsFullyStocked() {
    let stats = TankStats()
    #expect(stats.armor == 100 && stats.fuel == 100 && stats.shells == 20 && stats.rounds == 300)
    #expect(stats.canMove && !stats.isDestroyed)
}

@Test func fuelBurnsFasterWhileMovingAndStopsAtZero() {
    var moving = TankStats()
    var idle = TankStats()
    moving.burnFuel(seconds: 10, moving: true)
    idle.burnFuel(seconds: 10, moving: false)
    #expect(moving.fuel < idle.fuel)
    moving.burnFuel(seconds: 10_000, moving: true)
    #expect(moving.fuel == 0)
    #expect(!moving.canMove)
}

@Test func ammoRunsOut() {
    var stats = TankStats()
    stats.shells = 1
    let first = stats.consumeShell()
    let second = stats.consumeShell()
    #expect(first)
    #expect(!second)
    #expect(stats.shells == 0)
    stats.rounds = 0
    let round = stats.consumeRound()
    #expect(!round)
}

@Test func damageDestroysAtZeroArmor() {
    var stats = TankStats()
    stats.takeDamage(60)
    #expect(stats.armor == 40)
    stats.takeDamage(60)
    #expect(stats.armor == 0)
    #expect(stats.isDestroyed)
}

@Test func baseRepairsAndTopsUpToMinimumsOnly() {
    var low = TankStats()
    low.armor = 50; low.fuel = 5; low.shells = 0; low.rounds = 10
    low.applyBase(seconds: 1)
    #expect(low.armor == 58)
    #expect(low.fuel == TankStats.baseMinFuel)
    #expect(low.shells == TankStats.baseMinShells)
    #expect(low.rounds == TankStats.baseMinRounds)
    low.applyBase(seconds: 100)
    #expect(low.armor == 100)

    var full = TankStats()
    full.applyBase(seconds: 1)
    #expect(full == TankStats())   // never reduces anything
}

@Test func cachesRefillUpToMaximum() {
    var stats = TankStats()
    stats.fuel = 10; stats.shells = 2; stats.rounds = 0
    stats.collect(.gas)
    #expect(stats.fuel == 55)
    stats.collect(.ammo)
    #expect(stats.shells == 10 && stats.rounds == 120)
    stats.collect(.gas); stats.collect(.gas)
    #expect(stats.fuel == TankStats.maxFuel)
}
