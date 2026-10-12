#if os(Linux)

/// An immutable action description; each `run` gets its own `ActionInstance`.
open class SKAction {
    indirect enum Kind {
        case wait
        case fadeAlpha(to: CGFloat)
        case scale(to: CGFloat)
        case move(by: CGVector)
        case removeFromParent
        case block(() -> Void)
        case sequence([SKAction])
        case group([SKAction])
        case repeatForever(SKAction)
    }

    let kind: Kind
    public let duration: TimeInterval

    init(_ kind: Kind, duration: TimeInterval) {
        self.kind = kind
        self.duration = duration
    }

    public class func wait(forDuration duration: TimeInterval) -> SKAction { SKAction(.wait, duration: duration) }
    public class func fadeAlpha(to alpha: CGFloat, duration: TimeInterval) -> SKAction { SKAction(.fadeAlpha(to: alpha), duration: duration) }
    public class func fadeIn(withDuration duration: TimeInterval) -> SKAction { fadeAlpha(to: 1, duration: duration) }
    public class func fadeOut(withDuration duration: TimeInterval) -> SKAction { fadeAlpha(to: 0, duration: duration) }
    public class func scale(to scale: CGFloat, duration: TimeInterval) -> SKAction { SKAction(.scale(to: scale), duration: duration) }
    public class func moveBy(x: CGFloat, y: CGFloat, duration: TimeInterval) -> SKAction {
        SKAction(.move(by: CGVector(dx: x, dy: y)), duration: duration)
    }
    public class func removeFromParent() -> SKAction { SKAction(.removeFromParent, duration: 0) }
    public class func run(_ block: @escaping () -> Void) -> SKAction { SKAction(.block(block), duration: 0) }
    public class func sequence(_ actions: [SKAction]) -> SKAction {
        SKAction(.sequence(actions), duration: actions.reduce(0) { $0 + $1.duration })
    }
    public class func group(_ actions: [SKAction]) -> SKAction {
        SKAction(.group(actions), duration: actions.map(\.duration).max() ?? 0)
    }
    public class func repeatForever(_ action: SKAction) -> SKAction { SKAction(.repeatForever(action), duration: .infinity) }
}

/// A running action and its progress.
final class ActionInstance {
    private let action: SKAction
    private var elapsed: Double = 0
    private var started = false
    private var startAlpha: CGFloat = 0
    private var startXScale: CGFloat = 0
    private var startYScale: CGFloat = 0
    private var moved: CGFloat = 0
    private var index = 0
    private var current: ActionInstance?
    private var groupChildren: [ActionInstance?] = []

    init(_ action: SKAction) {
        self.action = action
    }

    /// Advances by `dt`. Returns the unused time once finished, or nil while still running.
    func advance(_ node: SKNode, _ dt: Double) -> Double? {
        switch action.kind {
        case .wait, .fadeAlpha, .scale, .move:
            if !started {
                started = true
                startAlpha = node.alpha
                startXScale = node.xScale
                startYScale = node.yScale
            }
            elapsed += dt
            let t = action.duration > 0 ? CGFloat(min(1, elapsed / action.duration)) : 1
            switch action.kind {
            case .fadeAlpha(let to): node.alpha = startAlpha + (to - startAlpha) * t
            case .scale(let to):
                node.xScale = startXScale + (to - startXScale) * t
                node.yScale = startYScale + (to - startYScale) * t
            case .move(let by):
                node.position.x += by.dx * (t - moved)
                node.position.y += by.dy * (t - moved)
                moved = t
            default: break
            }
            return elapsed >= action.duration ? elapsed - action.duration : nil
        case .removeFromParent:
            node.removeFromParent()
            return dt
        case .block(let block):
            block()
            return dt
        case .sequence(let actions):
            var left = dt
            while index < actions.count {
                let step = current ?? ActionInstance(actions[index])
                guard let rest = step.advance(node, left) else {
                    current = step
                    return nil
                }
                current = nil
                index += 1
                left = rest
            }
            return left
        case .group(let actions):
            if !started {
                started = true
                groupChildren = actions.map(ActionInstance.init)
            }
            var shortestLeft = Double.infinity
            for i in groupChildren.indices {
                guard let child = groupChildren[i] else { continue }
                if let rest = child.advance(node, dt) {
                    groupChildren[i] = nil
                    shortestLeft = min(shortestLeft, rest)
                }
            }
            guard groupChildren.allSatisfy({ $0 == nil }) else { return nil }
            return shortestLeft.isFinite ? shortestLeft : 0
        case .repeatForever(let inner):
            guard inner.duration > 0 else { return nil }
            var left = dt
            while true {
                let step = current ?? ActionInstance(inner)
                guard let rest = step.advance(node, left) else {
                    current = step
                    return nil
                }
                current = nil
                left = rest
            }
        }
    }
}

public final class SKTransition {
    let duration: TimeInterval

    init(duration: TimeInterval) {
        self.duration = duration
    }

    /// Fades to black, then in to the new scene.
    public class func fade(withDuration duration: TimeInterval) -> SKTransition {
        SKTransition(duration: duration)
    }
}
#endif
