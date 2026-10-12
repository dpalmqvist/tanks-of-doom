#if os(Linux)
import CSDL2

public enum SKBlendMode {
    case alpha, add
}

open class SKNode {
    public var position = CGPoint.zero
    public var zPosition: CGFloat = 0
    public var zRotation: CGFloat = 0
    public var xScale: CGFloat = 1
    public var yScale: CGFloat = 1
    public var alpha: CGFloat = 1
    public var isHidden = false
    /// Stops this node's and its descendants' actions (and particles).
    public var isPaused = false
    public var name: String?
    public private(set) weak var parent: SKNode?
    public private(set) var children: [SKNode] = []
    private var actions: [ActionInstance] = []

    public init() {}

    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    public var scene: SKScene? {
        var node: SKNode? = self
        while let current = node {
            if let scene = current as? SKScene { return scene }
            node = current.parent
        }
        return nil
    }

    public func setScale(_ scale: CGFloat) {
        xScale = scale
        yScale = scale
    }

    public func addChild(_ node: SKNode) {
        precondition(node.parent == nil, "Attempted to add a node that already has a parent")
        node.parent = self
        children.append(node)
    }

    public func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        self.parent = nil
    }

    public func removeAllChildren() {
        for child in children { child.parent = nil }
        children.removeAll()
    }

    public func run(_ action: SKAction) {
        actions.append(ActionInstance(action))
    }

    public func removeAllActions() {
        actions.removeAll()
    }

    public func hasActions() -> Bool { !actions.isEmpty }

    // Input, delivered to the presented scene (NSResponder's role on macOS).
    open func keyDown(with event: NSEvent) {}
    open func keyUp(with event: NSEvent) {}
    open func mouseDown(with event: NSEvent) {}

    // MARK: Frame processing

    /// Runs actions (and particle simulation) for this subtree unless paused.
    func evaluateActions(dt: Double) {
        guard !isPaused else { return }
        if !actions.isEmpty {
            let running = actions
            actions.removeAll()
            var remaining: [ActionInstance] = []
            for action in running where action.advance(self, dt) == nil {
                remaining.append(action)
            }
            // Keep actions started while evaluating (e.g. from a run block), unless removeAllActions ran.
            actions = remaining + actions
        }
        simulate(dt: dt)
        for child in children { child.evaluateActions(dt: dt) }
    }

    func simulate(dt: Double) {}

    var localTransform: Affine {
        Affine(position: position, rotation: zRotation, xScale: xScale, yScale: yScale)
    }

    /// Whether this node draws anything itself (containers don't).
    var hasContent: Bool { false }

    func render(in context: RenderContext, transform: Affine, alpha: CGFloat) {}

    func collectDraws(into items: inout [DrawItem], transform parent: Affine, alpha parentAlpha: CGFloat, z parentZ: CGFloat) {
        guard !isHidden else { return }
        let alpha = parentAlpha * self.alpha
        guard alpha > 0.001 else { return }
        let transform = parent.concatenating(localTransform)
        let z = parentZ + zPosition
        if hasContent {
            items.append(DrawItem(node: self, transform: transform, alpha: alpha, z: z, order: items.count))
        }
        for child in children {
            child.collectDraws(into: &items, transform: transform, alpha: alpha, z: z)
        }
    }
}

struct DrawItem {
    let node: SKNode
    let transform: Affine
    let alpha: CGFloat
    let z: CGFloat
    let order: Int
}

/// A 2D affine transform: x' = a·x + c·y + tx, y' = b·x + d·y + ty.
struct Affine {
    var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat

    init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    init(position: CGPoint, rotation: CGFloat, xScale: CGFloat, yScale: CGFloat) {
        let cosine = rotation == 0 ? 1 : cos(rotation)
        let sine = rotation == 0 ? 0 : sin(rotation)
        self.init(a: cosine * xScale, b: sine * xScale, c: -sine * yScale, d: cosine * yScale, tx: position.x, ty: position.y)
    }

    /// Applies `inner` first, then `self`.
    func concatenating(_ m: Affine) -> Affine {
        Affine(a: a * m.a + c * m.b, b: b * m.a + d * m.b, c: a * m.c + c * m.d, d: b * m.c + d * m.d,
               tx: a * m.tx + c * m.ty + tx, ty: b * m.tx + d * m.ty + ty)
    }

    func apply(_ p: CGPoint) -> CGPoint {
        CGPoint(x: a * p.x + c * p.y + tx, y: b * p.x + d * p.y + ty)
    }

    var inverted: Affine {
        let det = a * d - b * c
        guard det != 0 else { return self }
        return Affine(a: d / det, b: -b / det, c: -c / det, d: a / det,
                      tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
    }
}

public enum SKSceneScaleMode {
    case fill, aspectFill, aspectFit, resizeFill
}

open class SKScene: SKNode {
    public var size: CGSize {
        didSet { if size != oldValue { didChangeSize(oldValue) } }
    }
    public var scaleMode: SKSceneScaleMode = .fill
    public var backgroundColor = NSColor(white: 0.15, alpha: 1)
    public weak var camera: SKCameraNode?
    public internal(set) weak var view: SKView?

    public init(size: CGSize) {
        self.size = size
        super.init()
    }

    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    open func update(_ currentTime: TimeInterval) {}
    open func didMove(to view: SKView) {}
    open func willMove(from view: SKView) {}
    open func didChangeSize(_ oldSize: CGSize) {}

    /// Scene points to window pixels: y flips, and the camera (if any) sits at the window centre.
    func viewTransform(pixelSize: CGSize, scale: CGFloat) -> Affine {
        if let camera {
            return Affine(a: scale, b: 0, c: 0, d: -scale,
                          tx: pixelSize.width / 2 - camera.position.x * scale, ty: pixelSize.height / 2 + camera.position.y * scale)
        }
        return Affine(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: pixelSize.height)
    }

    func render(in context: RenderContext) {
        var items: [DrawItem] = []
        items.reserveCapacity(512)
        let root = viewTransform(pixelSize: context.pixelSize, scale: context.scale)
        for child in children {
            child.collectDraws(into: &items, transform: root, alpha: 1, z: 0)
        }
        items.sort { $0.z != $1.z ? $0.z < $1.z : $0.order < $1.order }
        for item in items {
            item.node.render(in: context, transform: item.transform, alpha: item.alpha)
        }
    }
}

public final class SKCameraNode: SKNode {
    public override init() { super.init() }
    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - Sprites

open class SKSpriteNode: SKNode {
    public var texture: SKTexture?
    public var color: NSColor
    public var colorBlendFactor: CGFloat = 0
    public var size: CGSize
    public var anchorPoint = CGPoint(x: 0.5, y: 0.5)
    public var blendMode = SKBlendMode.alpha

    public init(texture: SKTexture?, color: NSColor, size: CGSize) {
        self.texture = texture
        self.color = color
        self.size = size
        super.init()
    }

    public convenience init(texture: SKTexture?) {
        self.init(texture: texture, color: .white, size: texture?.size() ?? .zero)
    }

    public convenience init(texture: SKTexture?, size: CGSize) {
        self.init(texture: texture, color: .white, size: size)
    }

    public convenience init(color: NSColor, size: CGSize) {
        self.init(texture: nil, color: color, size: size)
    }

    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var hasContent: Bool { true }

    override func render(in context: RenderContext, transform: Affine, alpha: CGFloat) {
        let rect = CGRect(x: -anchorPoint.x * size.width, y: -anchorPoint.y * size.height, width: size.width, height: size.height)
        if let texture {
            // Tinting: blend the texture's colour toward `color` by `colorBlendFactor`.
            let f = colorBlendFactor, c = color.cgColor
            let tint = CGColor(srgbRed: 1 + (c.red - 1) * f, green: 1 + (c.green - 1) * f, blue: 1 + (c.blue - 1) * f, alpha: alpha)
            context.drawQuad(texture, rect: rect, transform: transform, color: tint, blendMode: blendMode)
        } else {
            var c = color.cgColor
            c.alpha *= alpha
            context.drawQuad(nil, rect: rect, transform: transform, color: c, blendMode: blendMode)
        }
    }
}

// MARK: - Shapes

/// Rasterized (antialiased) into a texture whenever its geometry or colours change.
open class SKShapeNode: SKNode {
    public var path: CGPath? { didSet { cached = nil } }
    public var fillColor = NSColor.clear { didSet { cached = nil } }
    public var strokeColor = NSColor.white { didSet { cached = nil } }
    public var lineWidth: CGFloat = 1 { didSet { cached = nil } }
    private var circleRadius: CGFloat?
    private var cached: (texture: SKTexture, rect: CGRect)?

    public override init() { super.init() }

    public convenience init(circleOfRadius radius: CGFloat) {
        self.init()
        circleRadius = radius
    }

    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var hasContent: Bool { true }

    private var shapeBounds: CGRect? {
        if let r = circleRadius { return CGRect(x: -r, y: -r, width: r * 2, height: r * 2) }
        guard let path, !path.isEmpty else { return nil }
        return path.boundingBox
    }

    private func rasterize() -> (texture: SKTexture, rect: CGRect)? {
        guard let bounds = shapeBounds else { return nil }
        let margin = lineWidth / 2 + 1
        let rect = bounds.insetBy(dx: -margin, dy: -margin)
        let stroke = strokeColor.cgColor, fill = fillColor.cgColor, circleRadius = circleRadius, path = path
        let lineWidth = lineWidth
        let texture = SKTexture(size: rect.size) { ctx, _ in
            ctx.translation = CGPoint(x: -rect.minX, y: -rect.minY)
            ctx.setLineWidth(lineWidth)
            ctx.setFillColor(fill)
            ctx.setStrokeColor(stroke)
            if let r = circleRadius {
                let circle = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
                if fill.alpha > 0 { ctx.fillEllipse(in: circle) }
                if stroke.alpha > 0 && lineWidth > 0 { ctx.strokeEllipse(in: circle) }
            } else if let path {
                if fill.alpha > 0 { ctx.addPath(path); ctx.fillPath() }
                if stroke.alpha > 0 && lineWidth > 0 { ctx.addPath(path); ctx.strokePath() }
            }
        }
        return (texture, rect)
    }

    override func render(in context: RenderContext, transform: Affine, alpha: CGFloat) {
        if cached == nil { cached = rasterize() }
        guard let cached else { return }
        context.drawQuad(cached.texture, rect: cached.rect, transform: transform,
                         color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha), blendMode: .alpha)
    }
}

// MARK: - Labels

public enum SKLabelHorizontalAlignmentMode {
    case center, left, right
}

public enum SKLabelVerticalAlignmentMode {
    case baseline, center, top, bottom
}

open class SKLabelNode: SKNode {
    public var text: String?
    public var fontName: String?
    public var fontSize: CGFloat = 32
    public var fontColor: NSColor? = .white
    public var horizontalAlignmentMode = SKLabelHorizontalAlignmentMode.center
    public var verticalAlignmentMode = SKLabelVerticalAlignmentMode.baseline
    private var rendered: (key: String, texture: SKTexture, descent: CGFloat)?

    public init(fontNamed fontName: String?) {
        self.fontName = fontName
        super.init()
    }

    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var hasContent: Bool { !(text ?? "").isEmpty }

    override func render(in context: RenderContext, transform: Affine, alpha: CGFloat) {
        guard let text, !text.isEmpty else { return }
        let pixelSize = Int32((fontSize * context.scale).rounded())
        let key = "\(fontName ?? "")|\(pixelSize)|\(text)"
        if rendered?.key != key {
            rendered = Fonts.render(text, fontName: fontName, pixelSize: pixelSize, scale: context.scale).map { (key, $0.texture, $0.descent) }
        }
        guard let rendered else { return }
        let size = rendered.texture.size()
        let x: CGFloat
        switch horizontalAlignmentMode {
        case .left: x = 0
        case .center: x = -size.width / 2
        case .right: x = -size.width
        }
        let y: CGFloat
        switch verticalAlignmentMode {
        case .baseline: y = -rendered.descent
        case .center: y = -size.height / 2
        case .top: y = -size.height
        case .bottom: y = 0
        }
        var color = (fontColor ?? .white).cgColor
        color.alpha *= alpha
        context.drawQuad(rendered.texture, rect: CGRect(x: x, y: y, width: size.width, height: size.height),
                         transform: transform, color: color, blendMode: .alpha)
    }
}

// MARK: - Tile maps

public final class SKTileDefinition {
    let texture: SKTexture
    let size: CGSize

    public init(texture: SKTexture, size: CGSize) {
        self.texture = texture
        self.size = size
    }
}

public final class SKTileGroup {
    public var name: String?
    let definition: SKTileDefinition

    public init(tileDefinition: SKTileDefinition) {
        definition = tileDefinition
    }
}

public final class SKTileSet {
    public init(tileGroups: [SKTileGroup]) {}
}

/// Draws only the tiles inside the window.
open class SKTileMapNode: SKNode {
    public let numberOfColumns: Int
    public let numberOfRows: Int
    public let tileSize: CGSize
    public var anchorPoint = CGPoint(x: 0.5, y: 0.5)
    private var tiles: [SKTileGroup?]

    public init(tileSet: SKTileSet, columns: Int, rows: Int, tileSize: CGSize) {
        numberOfColumns = columns
        numberOfRows = rows
        self.tileSize = tileSize
        tiles = Array(repeating: nil, count: columns * rows)
        super.init()
    }

    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func setTileGroup(_ group: SKTileGroup?, forColumn column: Int, row: Int) {
        guard column >= 0, column < numberOfColumns, row >= 0, row < numberOfRows else { return }
        tiles[row * numberOfColumns + column] = group
    }

    override var hasContent: Bool { true }

    override func render(in context: RenderContext, transform: Affine, alpha: CGFloat) {
        let origin = CGPoint(x: -anchorPoint.x * CGFloat(numberOfColumns) * tileSize.width,
                             y: -anchorPoint.y * CGFloat(numberOfRows) * tileSize.height)
        // The window's corners in this node's space bound the visible columns and rows.
        let inverse = transform.inverted
        let corners = [CGPoint.zero, CGPoint(x: context.pixelSize.width, y: 0),
                       CGPoint(x: 0, y: context.pixelSize.height), CGPoint(x: context.pixelSize.width, y: context.pixelSize.height)]
            .map(inverse.apply)
        let minX = corners.map(\.x).min()!, maxX = corners.map(\.x).max()!
        let minY = corners.map(\.y).min()!, maxY = corners.map(\.y).max()!
        let col0 = max(0, Int(((minX - origin.x) / tileSize.width).rounded(.down)))
        let col1 = min(numberOfColumns - 1, Int(((maxX - origin.x) / tileSize.width).rounded(.down)))
        let row0 = max(0, Int(((minY - origin.y) / tileSize.height).rounded(.down)))
        let row1 = min(numberOfRows - 1, Int(((maxY - origin.y) / tileSize.height).rounded(.down)))
        guard col0 <= col1, row0 <= row1 else { return }
        let color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
        for row in row0...row1 {
            for column in col0...col1 {
                guard let group = tiles[row * numberOfColumns + column] else { continue }
                let rect = CGRect(x: origin.x + CGFloat(column) * tileSize.width, y: origin.y + CGFloat(row) * tileSize.height,
                                  width: tileSize.width, height: tileSize.height)
                context.drawQuad(group.definition.texture, rect: rect, transform: transform, color: color, blendMode: .alpha)
            }
        }
    }
}

// MARK: - Drawing

/// Draws textured quads with SDL's geometry API (batched by SDL).
final class RenderContext {
    let renderer: OpaquePointer
    let pixelSize: CGSize
    let scale: CGFloat
    private var vertices = [SDL_Vertex](repeating: SDL_Vertex(), count: 4)
    private static let indices: [Int32] = [0, 1, 2, 0, 2, 3]

    init(renderer: OpaquePointer, pixelSize: CGSize, scale: CGFloat) {
        self.renderer = renderer
        self.pixelSize = pixelSize
        self.scale = scale
    }

    /// `rect` is in the node's space; the texture is stretched over it, upright with y up.
    func drawQuad(_ texture: SKTexture?, rect: CGRect, transform: Affine, color: CGColor, blendMode: SKBlendMode) {
        let corners = [transform.apply(CGPoint(x: rect.minX, y: rect.minY)), transform.apply(CGPoint(x: rect.maxX, y: rect.minY)),
                       transform.apply(CGPoint(x: rect.maxX, y: rect.maxY)), transform.apply(CGPoint(x: rect.minX, y: rect.maxY))]
        var minX = corners[0].x, maxX = minX, minY = corners[0].y, maxY = minY
        for p in corners {
            minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        guard maxX >= 0, maxY >= 0, minX <= pixelSize.width, minY <= pixelSize.height else { return }

        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        let sdlColor = SDL_Color(r: byte(color.red), g: byte(color.green), b: byte(color.blue), a: byte(color.alpha))
        guard sdlColor.a > 0 else { return }
        let uv: [(Float, Float)] = [(0, 1), (1, 1), (1, 0), (0, 0)]
        for i in 0..<4 {
            vertices[i] = SDL_Vertex(position: SDL_FPoint(x: Float(corners[i].x), y: Float(corners[i].y)), color: sdlColor,
                                     tex_coord: SDL_FPoint(x: uv[i].0, y: uv[i].1))
        }
        let mode = blendMode == .add ? SDL_BLENDMODE_ADD : SDL_BLENDMODE_BLEND
        var sdlTexture: OpaquePointer?
        if let texture {
            guard let t = texture.sdlTexture else { return }
            SDL_SetTextureBlendMode(t, mode)
            sdlTexture = t
        } else {
            SDL_SetRenderDrawBlendMode(renderer, mode)
        }
        Self.indices.withUnsafeBufferPointer { indices in
            _ = SDL_RenderGeometry(renderer, sdlTexture, vertices, 4, indices.baseAddress, 6)
        }
    }
}
#endif
