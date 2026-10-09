import AppKit
import SpriteKit
import TanksCore

final class GameScene: SKScene {
    let levelNumber: Int
    var runStats: RunStats
    var level: Level

    let worldNode = SKNode()
    let cameraNode = SKCameraNode()
    var renderer: WorldRenderer!
    var effects: Effects!
    var hud: HUD!
    /// Every human-driven tank. The campaign has one.
    let players: [Player]
    /// The player at this keyboard: the camera, HUD and sound follow them.
    let localPlayer: Player
    var pickups: [PickupNode] = []
    var projectiles: [Projectile] = []
    var mortars: [MortarShell] = []
    var enemies: [EnemyTank] = []
    var infantry: [InfantryNode] = []
    var buildingWindows: [Int: [GridPoint]] = [:]
    /// Ids 1–16 are reserved for player tanks; every other networked thing counts up from here.
    private var lastNetID: UInt32 = 16

    var lastUpdate: TimeInterval = 0
    var cameraBase = CGPoint.zero
    var shakeTime: Double = 0
    var shakeMagnitude: CGFloat = 0
    let targetMarker = TargetMarker()
    var isGamePaused = false
    var endTimer: Double?
    var victory = false
    var levelOver = false
    private var isSetUp = false
    private var resignObserver: NSObjectProtocol?

    init(size: CGSize, levelNumber: Int, runStats: RunStats) {
        self.levelNumber = levelNumber
        self.runStats = runStats
        self.level = CityGenerator.generate(seed: .random(in: 0...UInt64.max), level: levelNumber)
        let player = Player(slot: .host)
        players = [player]
        localPlayer = player
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        guard !isSetUp else { return }
        isSetUp = true
        buildWorld()
        // Keys released while the window is in the background never arrive; forget them.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: view.window, queue: .main) { [weak self] _ in
            self?.localPlayer.input = InputState()
        }
    }

    override func willMove(from view: SKView) {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func buildWorld() {
        addChild(worldNode)
        renderer = WorldRenderer(level: level)
        worldNode.addChild(renderer.root)
        effects = Effects(layer: worldNode)

        let baseLabel = SKLabelNode.make("BASE", size: 40, color: NSColor(white: 1, alpha: 0.35))
        baseLabel.position = level.map.center(level.baseCenter) - CGPoint(x: tileSize / 2, y: tileSize / 2)
        baseLabel.zPosition = Z.tracks
        worldNode.addChild(baseLabel)

        for cache in level.caches {
            let pickup = PickupNode(cache: cache)
            pickup.position = level.map.center(cache.position)
            worldNode.addChild(pickup)
            pickups.append(pickup)
        }

        for player in players {
            placeAtBase(player)
            worldNode.addChild(player.tank)
        }
        spawnEnemies()
        spawnInfantry()

        addChild(cameraNode)
        camera = cameraNode
        cameraBase = localPlayer.tank.position
        cameraNode.position = cameraBase
        worldNode.addChild(targetMarker)
        setUpHUD()
    }

    /// Starts a player at their own base, facing the middle of the city.
    func placeAtBase(_ player: Player) {
        let tank = player.tank
        tank.position = level.map.center(level.bases[player.slot.baseIndex].center)
        let middle = CGPoint(x: CGFloat(level.map.width) * tileSize / 2, y: CGFloat(level.map.height) * tileSize / 2)
        tank.heading = tank.position.angle(to: middle)
        tank.turretAngle = tank.heading
    }

    /// A fresh id for a networked thing (AI tank, soldier, projectile, mortar).
    func makeNetID() -> UInt32 {
        lastNetID += 1
        return lastNetID
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(currentTime - lastUpdate, 1.0 / 30)
        lastUpdate = currentTime
        guard !isGamePaused, !levelOver else { return }
        updatePlayers(dt: dt)
        updateEnemies(dt: dt)
        updateInfantry(dt: dt)
        updateProjectiles(dt: dt)
        updateMortars(dt: dt)
        updateTargetMarker()
        updateCamera(dt: dt)
        updateHUD()
        checkLevelEnd(dt: dt)
    }

    func shake(_ magnitude: CGFloat, duration: Double) {
        guard magnitude >= shakeMagnitude || shakeTime <= 0 else { return }
        shakeMagnitude = magnitude
        shakeTime = duration
    }

    func updateCamera(dt: Double) {
        let follow = CGFloat(min(1, 6 * dt))
        var p = cameraBase + (localPlayer.tank.position - cameraBase) * follow
        p.x = clampCamera(p.x, half: size.width / 2, extent: CGFloat(level.map.width) * tileSize)
        p.y = clampCamera(p.y, half: size.height / 2, extent: CGFloat(level.map.height) * tileSize)
        cameraBase = p
        var offset = CGPoint.zero
        if shakeTime > 0 {
            shakeTime -= dt
            offset = CGPoint(x: .random(in: -shakeMagnitude...shakeMagnitude), y: .random(in: -shakeMagnitude...shakeMagnitude))
            if shakeTime <= 0 { shakeMagnitude = 0 }
        }
        cameraNode.position = p + offset
    }

    /// Keeps the view inside the map; centres the map when the view is larger than it.
    private func clampCamera(_ value: CGFloat, half: CGFloat, extent: CGFloat) -> CGFloat {
        if extent <= half * 2 { return extent / 2 }
        return min(max(value, half), extent - half)
    }

    func playSound(_ sound: Audio.Sound, at point: CGPoint, volume: Float = 1) {
        let distance = Float(point.distance(to: localPlayer.tank.position))
        Audio.shared.play(sound, volume: volume * max(0, 1 - distance / 1400))
    }
}
