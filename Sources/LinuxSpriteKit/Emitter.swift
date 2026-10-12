#if os(Linux)

public final class SKKeyframeSequence {
    private let colors: [CGColor]
    private let times: [CGFloat]

    public init(keyframeValues values: [Any], times: [NSNumber]) {
        colors = values.map { ($0 as? NSColor)?.cgColor ?? CGColor(gray: 1, alpha: 1) }
        self.times = times.map { CGFloat($0.doubleValue) }
    }

    func color(at t: CGFloat) -> CGColor {
        CGGradient(colors: colors, locations: times).color(at: t)
    }
}

/// A particle emitter: particles live in the emitter's own coordinate space.
public final class SKEmitterNode: SKNode {
    public var particleTexture: SKTexture?
    public var particleBirthRate: CGFloat = 0
    public var numParticlesToEmit = 0
    public var particleLifetime: CGFloat = 0
    public var particleLifetimeRange: CGFloat = 0
    public var particleSpeed: CGFloat = 0
    public var particleSpeedRange: CGFloat = 0
    public var emissionAngle: CGFloat = 0
    public var emissionAngleRange: CGFloat = 0
    public var particleScale: CGFloat = 1
    public var particleScaleRange: CGFloat = 0
    public var particleScaleSpeed: CGFloat = 0
    public var particleAlpha: CGFloat = 1
    public var particleAlphaSpeed: CGFloat = 0
    public var particleColor = NSColor.white
    public var particleColorBlendFactor: CGFloat = 0
    public var particleColorSequence: SKKeyframeSequence?
    public var particleBlendMode = SKBlendMode.alpha

    private struct Particle {
        var position: CGPoint
        var velocity: CGVector
        var age: CGFloat
        var lifetime: CGFloat
        var scale: CGFloat
        var alpha: CGFloat
    }

    private var particles: [Particle] = []
    private var emitted = 0
    private var pendingBirths: CGFloat = 0

    public override init() { super.init() }
    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func spread(_ value: CGFloat, _ range: CGFloat) -> CGFloat {
        range > 0 ? value + .random(in: -range / 2...range / 2) : value
    }

    override func simulate(dt: Double) {
        let dt = CGFloat(dt)
        var alive = 0
        for i in particles.indices {
            var p = particles[i]
            p.age += dt
            guard p.age < p.lifetime else { continue }
            p.position.x += p.velocity.dx * dt
            p.position.y += p.velocity.dy * dt
            p.scale = max(0, p.scale + particleScaleSpeed * dt)
            p.alpha += particleAlphaSpeed * dt
            particles[alive] = p
            alive += 1
        }
        particles.removeLast(particles.count - alive)

        pendingBirths += particleBirthRate * dt
        while pendingBirths >= 1 && (numParticlesToEmit == 0 || emitted < numParticlesToEmit) {
            pendingBirths -= 1
            emitted += 1
            let angle = Self.spread(emissionAngle, emissionAngleRange)
            let speed = Self.spread(particleSpeed, particleSpeedRange)
            particles.append(Particle(position: .zero, velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed), age: 0,
                                      lifetime: max(0.01, Self.spread(particleLifetime, particleLifetimeRange)),
                                      scale: max(0, Self.spread(particleScale, particleScaleRange)), alpha: particleAlpha))
        }
        if numParticlesToEmit > 0 && emitted >= numParticlesToEmit { pendingBirths = 0 }
    }

    override var hasContent: Bool { !particles.isEmpty }

    override func render(in context: RenderContext, transform: Affine, alpha: CGFloat) {
        let size = particleTexture?.size() ?? CGSize(width: 8, height: 8)
        let f = particleColorBlendFactor
        for p in particles {
            let base = particleColorSequence?.color(at: p.age / p.lifetime) ?? particleColor.cgColor
            let a = max(0, min(1, p.alpha)) * base.alpha * alpha
            guard a > 0.004 else { continue }
            let color = CGColor(srgbRed: 1 + (base.red - 1) * f, green: 1 + (base.green - 1) * f, blue: 1 + (base.blue - 1) * f, alpha: a)
            let w = size.width * p.scale, h = size.height * p.scale
            context.drawQuad(particleTexture, rect: CGRect(x: p.position.x - w / 2, y: p.position.y - h / 2, width: w, height: h),
                             transform: transform, color: color, blendMode: particleBlendMode)
        }
    }
}
#endif
