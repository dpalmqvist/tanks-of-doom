import AppKit
import SpriteKit
import TanksCore

/// One pixel per tile, scaled up. Shows the player and currently spotted enemy tanks — never caches.
final class Minimap: SKNode {
    private(set) var displaySize: CGFloat = 200
    private let frameNode = SKSpriteNode(color: NSColor(white: 0, alpha: 0.7), size: .zero)
    private let mapSprite: SKSpriteNode
    private let playerDot = SKShapeNode(circleOfRadius: 3.5)
    private var enemyDots: [SKShapeNode] = []
    private let worldSize: CGSize

    init(map: TileMap) {
        worldSize = CGSize(width: CGFloat(map.width) * tileSize, height: CGFloat(map.height) * tileSize)
        mapSprite = SKSpriteNode(texture: Minimap.texture(for: map))
        super.init()
        frameNode.anchorPoint = .zero
        mapSprite.anchorPoint = .zero
        frameNode.zPosition = 0
        mapSprite.zPosition = 1
        playerDot.fillColor = .systemGreen
        playerDot.strokeColor = .white
        playerDot.lineWidth = 1
        playerDot.zPosition = 3
        addChild(frameNode)
        addChild(mapSprite)
        addChild(playerDot)
        resize()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func toggleSize() {
        displaySize = displaySize < 300 ? 400 : 200
        resize()
    }

    func refresh(map: TileMap) {
        mapSprite.texture = Minimap.texture(for: map)
    }

    func update(player: CGPoint, enemies: [CGPoint]) {
        playerDot.position = project(player)
        while enemyDots.count < enemies.count {
            let dot = SKShapeNode(circleOfRadius: 3.5)
            dot.fillColor = .systemRed
            dot.strokeColor = .clear
            dot.zPosition = 2
            addChild(dot)
            enemyDots.append(dot)
        }
        for (index, dot) in enemyDots.enumerated() {
            dot.isHidden = index >= enemies.count
            if index < enemies.count { dot.position = project(enemies[index]) }
        }
    }

    private func resize() {
        frameNode.size = CGSize(width: displaySize + 6, height: displaySize + 6)
        frameNode.position = CGPoint(x: -3, y: -3)
        mapSprite.size = CGSize(width: displaySize, height: displaySize)
    }

    private func project(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / worldSize.width * displaySize, y: p.y / worldSize.height * displaySize)
    }

    static func texture(for map: TileMap) -> SKTexture {
        let ctx = CGContext(data: nil, width: map.width, height: map.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<map.height {
            for x in 0..<map.width {
                ctx.setFillColor(color(for: map[x: x, y: y]))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let texture = SKTexture(cgImage: ctx.makeImage()!)
        texture.filteringMode = .nearest
        return texture
    }

    private static func color(for tile: Tile) -> CGColor {
        switch tile {
        case .road: return Textures.color(0.45, 0.45, 0.45)
        case .building: return Textures.color(0.22, 0.18, 0.15)
        case .rubble: return Textures.color(0.35, 0.3, 0.25)
        case .park: return Textures.color(0.25, 0.35, 0.18)
        case .crater: return Textures.color(0.28, 0.22, 0.15)
        case .base: return Textures.color(0.2, 0.45, 0.9)
        case .wall: return Textures.color(0, 0, 0)
        }
    }
}
