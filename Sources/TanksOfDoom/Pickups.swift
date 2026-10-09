import SpriteKit
import TanksCore

final class PickupNode: SKSpriteNode {
    let kind: CacheKind
    /// Collected pickups stay in the scene, hidden, so versus can bring them back (and indices stay stable for the guest).
    var isAvailable = true {
        didSet { isHidden = !isAvailable }
    }

    init(cache: Cache) {
        kind = cache.kind
        let texture = cache.kind == .gas ? Textures.gasCan : Textures.ammoCrate
        super.init(texture: texture, color: .clear, size: texture.size())
        zPosition = Z.pickups
        run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.6), .scale(to: 1.0, duration: 0.6)])))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}
