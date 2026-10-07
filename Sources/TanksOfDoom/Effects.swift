import AppKit
import SpriteKit

/// Short-lived visual effects added to the world layer.
final class Effects {
    private unowned let layer: SKNode

    init(layer: SKNode) {
        self.layer = layer
    }

    func explosion(at point: CGPoint, scale: CGFloat) {
        let fire = emitter(count: Int(50 * scale), lifetime: 0.5, speed: 130 * scale, size: 1.4 * scale,
                           colors: [.white, .yellow, .orange, NSColor(red: 0.3, green: 0.1, blue: 0.05, alpha: 1)], additive: true)
        fire.position = point
        fire.zPosition = Z.effects
        let smoke = emitter(count: Int(24 * scale), lifetime: 1.6, speed: 45 * scale, size: 2.0 * scale,
                            colors: [NSColor(white: 0.35, alpha: 0.8), NSColor(white: 0.15, alpha: 0)], additive: false)
        smoke.particleScaleSpeed = 1.0
        smoke.position = point
        smoke.zPosition = Z.effects - 0.5
        let scorch = SKSpriteNode(texture: Textures.scorch, size: CGSize(width: 90 * scale, height: 90 * scale))
        scorch.position = point
        scorch.zPosition = Z.tracks
        scorch.run(.sequence([.wait(forDuration: 15), .fadeOut(withDuration: 5), .removeFromParent()]))
        fire.run(.sequence([.wait(forDuration: 2.5), .removeFromParent()]))
        smoke.run(.sequence([.wait(forDuration: 2.5), .removeFromParent()]))
        layer.addChild(scorch)
        layer.addChild(smoke)
        layer.addChild(fire)
    }

    func spark(at point: CGPoint) {
        let sparks = emitter(count: 8, lifetime: 0.2, speed: 90, size: 0.4, colors: [.white, .yellow], additive: true)
        sparks.position = point
        sparks.zPosition = Z.effects
        sparks.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
        layer.addChild(sparks)
    }

    func dustPuff(at point: CGPoint) {
        let dust = emitter(count: 14, lifetime: 0.6, speed: 50, size: 0.9,
                           colors: [NSColor(white: 0.6, alpha: 0.8), NSColor(white: 0.4, alpha: 0)], additive: false)
        dust.position = point
        dust.zPosition = Z.effects
        dust.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
        layer.addChild(dust)
    }

    func muzzleFlash(at point: CGPoint, angle: CGFloat, big: Bool) {
        let flash = SKSpriteNode(texture: Textures.spark)
        flash.color = .yellow
        flash.colorBlendFactor = 0.6
        flash.blendMode = .add
        flash.size = big ? CGSize(width: 46, height: 26) : CGSize(width: 16, height: 9)
        flash.position = point
        flash.zRotation = angle
        flash.zPosition = Z.effects
        flash.run(.sequence([.fadeOut(withDuration: big ? 0.12 : 0.05), .removeFromParent()]))
        layer.addChild(flash)
    }

    func smokePuff(at point: CGPoint) {
        let puff = SKSpriteNode(texture: Textures.spark)
        puff.color = .gray
        puff.colorBlendFactor = 1
        puff.alpha = 0.5
        puff.size = CGSize(width: 10, height: 10)
        puff.position = point
        puff.zPosition = Z.projectiles - 0.5
        puff.run(.sequence([.group([.scale(to: 2.5, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        layer.addChild(puff)
    }

    func trackMark(at point: CGPoint, angle: CGFloat) {
        let mark = SKSpriteNode(texture: Textures.trackMark)
        mark.position = point
        mark.zRotation = angle
        mark.zPosition = Z.tracks
        mark.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 2), .removeFromParent()]))
        layer.addChild(mark)
    }

    func floatingText(_ text: String, at point: CGPoint, color: NSColor) {
        let label = SKLabelNode.make(text, size: 18, color: color, font: "Menlo-Bold")
        label.position = point
        label.zPosition = Z.effects + 1
        label.run(.sequence([.group([.moveBy(x: 0, y: 40, duration: 1), .fadeOut(withDuration: 1)]), .removeFromParent()]))
        layer.addChild(label)
    }

    private func emitter(count: Int, lifetime: CGFloat, speed: CGFloat, size: CGFloat, colors: [NSColor], additive: Bool) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Textures.spark
        e.particleBirthRate = 4000
        e.numParticlesToEmit = max(1, count)
        e.particleLifetime = lifetime
        e.particleLifetimeRange = lifetime * 0.5
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.7
        e.emissionAngleRange = .pi * 2
        e.particleScale = size
        e.particleScaleRange = size * 0.4
        e.particleAlphaSpeed = -1 / lifetime
        e.particleColorBlendFactor = 1
        let times = colors.indices.map { NSNumber(value: Double($0) / Double(max(1, colors.count - 1))) }
        e.particleColorSequence = SKKeyframeSequence(keyframeValues: colors, times: times)
        e.particleBlendMode = additive ? .add : .alpha
        return e
    }
}
