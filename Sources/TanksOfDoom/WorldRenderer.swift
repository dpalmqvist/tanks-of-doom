import SpriteKit
import TanksCore

/// Draws the ground tile map and one sprite per building, and keeps them in sync with damage.
final class WorldRenderer {
    let root = SKNode()
    private let ground: SKTileMapNode
    private let groups: [String: SKTileGroup]
    private var buildingNodes: [Int: SKSpriteNode] = [:]

    init(level: Level) {
        let textures: [String: SKTexture] = [
            "road": Textures.road, "park": Textures.park, "rubble": Textures.rubble,
            "crater": Textures.crater, "base": Textures.base, "wall": Textures.wall,
        ]
        let tile = CGSize(width: tileSize, height: tileSize)
        var groups: [String: SKTileGroup] = [:]
        for (name, texture) in textures {
            let group = SKTileGroup(tileDefinition: SKTileDefinition(texture: texture, size: tile))
            group.name = name
            groups[name] = group
        }
        self.groups = groups
        let map = level.map
        ground = SKTileMapNode(tileSet: SKTileSet(tileGroups: Array(groups.values)), columns: map.width, rows: map.height, tileSize: tile)
        ground.anchorPoint = .zero
        ground.zPosition = Z.ground
        root.addChild(ground)
        for y in 0..<map.height {
            for x in 0..<map.width { setTile(GridPoint(x, y), map[x: x, y: y]) }
        }
        for building in level.buildings { addBuilding(building) }
    }

    func update(_ building: Building) {
        guard let node = buildingNodes[building.id] else { return }
        if building.isDestroyed {
            node.removeFromParent()
            buildingNodes[building.id] = nil
            for tile in building.tiles { setTile(tile, .rubble) }
        } else {
            node.texture = Textures.building(width: building.rect.width, height: building.rect.height,
                                             variant: building.id, stage: building.damageStage)
        }
    }

    private func setTile(_ p: GridPoint, _ tile: Tile) {
        ground.setTileGroup(groups[Self.groupName(for: tile)], forColumn: p.x, row: p.y)
    }

    private static func groupName(for tile: Tile) -> String {
        switch tile {
        case .road: return "road"
        case .park: return "park"
        case .rubble, .building: return "rubble"   // rubble shows once a building collapses
        case .crater: return "crater"
        case .base: return "base"
        case .wall: return "wall"
        }
    }

    private func addBuilding(_ building: Building) {
        let r = building.rect
        let node = SKSpriteNode(texture: Textures.building(width: r.width, height: r.height, variant: building.id, stage: building.damageStage))
        node.anchorPoint = .zero
        node.size = CGSize(width: CGFloat(r.width) * tileSize, height: CGFloat(r.height) * tileSize)
        node.position = CGPoint(x: CGFloat(r.minX) * tileSize, y: CGFloat(r.minY) * tileSize)
        node.zPosition = Z.buildings
        let shadow = SKSpriteNode(color: NSColor(white: 0, alpha: 0.35), size: node.size)
        shadow.anchorPoint = .zero
        shadow.position = CGPoint(x: 8, y: -8)
        shadow.zPosition = -0.5
        node.addChild(shadow)
        root.addChild(node)
        buildingNodes[building.id] = node
    }
}
