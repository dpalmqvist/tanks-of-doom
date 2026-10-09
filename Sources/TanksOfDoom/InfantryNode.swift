import SpriteKit
import TanksCore

/// A soldier inside a building. Invisible and unhittable unless exposed at a window.
final class InfantryNode: SKSpriteNode, Hostile {
    static let hitPoints = 12

    let buildingID: Int
    var brain: InfantryBrain
    var hp = InfantryNode.hitPoints
    var cooldown: Double = 0
    /// The window tile the soldier is currently exposed at.
    var post: GridPoint?
    var netID: UInt32 = 0
    var kind: InfantryKind { brain.kind }

    var isExposed: Bool { brain.state == .exposed }
    var hitRadius: CGFloat { 16 }
    var targetKind: TargetKind { .infantry }
    var canBeHit: Bool { isExposed && hp > 0 }

    init(spawn: InfantrySpawn, initialDelay: Double) {
        buildingID = spawn.buildingID
        brain = InfantryBrain(kind: spawn.kind, initialDelay: initialDelay)
        let texture = Textures.infantry(spawn.kind)
        super.init(texture: texture, color: .clear, size: texture.size())
        zPosition = Z.infantry
        alpha = 0
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyDamage(_ amount: Int, from shooter: Combatant, in scene: GameScene) {
        guard hp > 0 else { return }
        hp -= amount
        if hp <= 0 { scene.infantryKilled(self) }
    }
}
