import AppKit
import SpriteKit
import TanksCore

final class GameScene: SKScene {
    let levelNumber: Int
    var runStats: RunStats
    var level: Level

    let worldNode = SKNode()
    let cameraNode = SKCameraNode()
    let crosshair = SKShapeNode(circleOfRadius: 10)
    var renderer: WorldRenderer!
    var effects: Effects!
    var hud: HUD!
    let playerTank = PlayerTank()
    var pickups: [PickupNode] = []
    var projectiles: [Projectile] = []
    var mortars: [MortarShell] = []
    var enemies: [EnemyTank] = []
    var infantry: [InfantryNode] = []
    var buildingWindows: [Int: [GridPoint]] = [:]
    /// Everything the player can shoot.
    var hostiles: [Hostile] { (enemies as [Hostile]) + (infantry as [Hostile]) }

    var input = InputState()
    var mouseInCamera = CGPoint.zero
    var lastUpdate: TimeInterval = 0
    var cameraBase = CGPoint.zero
    var shakeTime: Double = 0
    var shakeMagnitude: CGFloat = 0
    var inBase = false
    var turretAim = TurretAim()
    var lockedTargetID: Int?
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
            self?.input = InputState()
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

        playerTank.position = level.map.center(level.baseCenter)
        playerTank.heading = .pi / 4
        playerTank.turretAngle = .pi / 4
        worldNode.addChild(playerTank)
        spawnEnemies()
        spawnInfantry()

        addChild(cameraNode)
        camera = cameraNode
        cameraBase = playerTank.position
        cameraNode.position = cameraBase
        crosshair.strokeColor = .white
        crosshair.lineWidth = 2
        crosshair.zPosition = Z.hud + 10
        cameraNode.addChild(crosshair)
        worldNode.addChild(targetMarker)
        setUpHUD()
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(currentTime - lastUpdate, 1.0 / 30)
        lastUpdate = currentTime
        guard !isGamePaused, !levelOver else { return }
        updatePlayer(dt: dt)
        updatePlayerWeapons(dt: dt)
        updateEnemies(dt: dt)
        updateInfantry(dt: dt)
        updateProjectiles(dt: dt)
        updateMortars(dt: dt)
        updateCamera(dt: dt)
        updateHUD()
        checkLevelEnd(dt: dt)
    }

    var aimPoint: CGPoint { cameraNode.convert(mouseInCamera, to: worldNode) }

    func shake(_ magnitude: CGFloat, duration: Double) {
        guard magnitude >= shakeMagnitude || shakeTime <= 0 else { return }
        shakeMagnitude = magnitude
        shakeTime = duration
    }

    func updateCamera(dt: Double) {
        let follow = CGFloat(min(1, 6 * dt))
        var p = cameraBase + (playerTank.position - cameraBase) * follow
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
        crosshair.position = mouseInCamera
    }

    /// Keeps the view inside the map; centres the map when the view is larger than it.
    private func clampCamera(_ value: CGFloat, half: CGFloat, extent: CGFloat) -> CGFloat {
        if extent <= half * 2 { return extent / 2 }
        return min(max(value, half), extent - half)
    }

    func playSound(_ sound: Audio.Sound, at point: CGPoint, volume: Float = 1) {
        let distance = Float(point.distance(to: playerTank.position))
        Audio.shared.play(sound, volume: volume * max(0, 1 - distance / 1400))
    }
}
