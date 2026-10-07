import AppKit
import SpriteKit
import TanksCore

/// All game art, drawn with Core Graphics at launch. Tanks and soldiers face +x.
enum Textures {
    static func render(_ size: CGSize, _ draw: @escaping (CGContext, CGSize) -> Void) -> SKTexture {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(ctx, size)
            return true
        }
        return SKTexture(image: image)
    }

    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    // MARK: Tanks

    static let turretAnchor = CGPoint(x: 20.0 / 64.0, y: 0.5)
    /// Distance from the turret pivot to the muzzle.
    static let muzzleOffset: CGFloat = 44

    static let playerHull = tankHull(body: color(0.36, 0.45, 0.22), dark: color(0.2, 0.26, 0.12))
    static let playerTurret = tankTurret(body: color(0.42, 0.52, 0.26), dark: color(0.2, 0.26, 0.12))
    static let enemyHull = tankHull(body: color(0.55, 0.27, 0.2), dark: color(0.3, 0.13, 0.1))
    static let enemyTurret = tankTurret(body: color(0.62, 0.32, 0.24), dark: color(0.3, 0.13, 0.1))

    static func tankHull(body: CGColor, dark: CGColor) -> SKTexture {
        render(CGSize(width: 56, height: 42)) { ctx, s in
            ctx.setFillColor(color(0.12, 0.12, 0.12))
            ctx.fill(CGRect(x: 0, y: 0, width: s.width, height: 10))
            ctx.fill(CGRect(x: 0, y: s.height - 10, width: s.width, height: 10))
            ctx.setFillColor(color(0.3, 0.3, 0.3))
            var x: CGFloat = 2
            while x < s.width {
                ctx.fill(CGRect(x: x, y: 1, width: 3, height: 8))
                ctx.fill(CGRect(x: x, y: s.height - 9, width: 3, height: 8))
                x += 6
            }
            let bodyRect = CGRect(x: 3, y: 8, width: s.width - 6, height: s.height - 16)
            ctx.setFillColor(body)
            ctx.addPath(CGPath(roundedRect: bodyRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.fillPath()
            ctx.setStrokeColor(dark)
            ctx.setLineWidth(2)
            ctx.stroke(bodyRect.insetBy(dx: 4, dy: 3))
            ctx.setFillColor(dark)
            ctx.fill(CGRect(x: s.width - 9, y: s.height / 2 - 6, width: 4, height: 12))
        }
    }

    static func tankTurret(body: CGColor, dark: CGColor) -> SKTexture {
        render(CGSize(width: 64, height: 26)) { ctx, s in
            ctx.setFillColor(dark)
            ctx.fill(CGRect(x: 28, y: s.height / 2 - 3, width: 36, height: 6))
            ctx.fill(CGRect(x: 58, y: s.height / 2 - 4, width: 6, height: 8))
            ctx.setFillColor(body)
            ctx.fillEllipse(in: CGRect(x: 7, y: 0, width: 26, height: 26))
            ctx.setStrokeColor(dark)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: 8, y: 1, width: 24, height: 24))
            ctx.setFillColor(dark)
            ctx.fillEllipse(in: CGRect(x: 14, y: 8, width: 8, height: 8))
        }
    }

    // MARK: Ground

    static func speckled(_ base: CGColor, seed: UInt64, specks: Int = 140,
                         extra: ((CGContext, inout SeededRandom) -> Void)? = nil) -> SKTexture {
        render(CGSize(width: 64, height: 64)) { ctx, s in
            var rng = SeededRandom(seed: seed)
            ctx.setFillColor(base)
            ctx.fill(CGRect(origin: .zero, size: s))
            for _ in 0..<specks {
                ctx.setFillColor(CGColor(gray: rng.chance(0.5) ? 1 : 0, alpha: 0.07))
                ctx.fill(CGRect(x: CGFloat.random(in: 0..<64, using: &rng), y: CGFloat.random(in: 0..<64, using: &rng), width: 2, height: 2))
            }
            extra?(ctx, &rng)
        }
    }

    static let road = speckled(color(0.23, 0.23, 0.24), seed: 1)

    static let park = speckled(color(0.27, 0.31, 0.17), seed: 2, specks: 220) { ctx, rng in
        ctx.setFillColor(color(0.36, 0.38, 0.2))
        for _ in 0..<14 {
            ctx.fill(CGRect(x: CGFloat.random(in: 0..<60, using: &rng), y: CGFloat.random(in: 0..<60, using: &rng), width: 3, height: 5))
        }
    }

    static let rubble = speckled(color(0.36, 0.33, 0.29), seed: 3) { ctx, rng in
        for _ in 0..<22 {
            let g = CGFloat.random(in: 0.25...0.6, using: &rng)
            ctx.setFillColor(color(g, g * 0.95, g * 0.88))
            let w = CGFloat.random(in: 4...12, using: &rng)
            let h = CGFloat.random(in: 3...9, using: &rng)
            ctx.fill(CGRect(x: CGFloat.random(in: 0..<(64 - w), using: &rng), y: CGFloat.random(in: 0..<(64 - h), using: &rng), width: w, height: h))
        }
    }

    static let crater = speckled(color(0.31, 0.26, 0.19), seed: 4) { ctx, _ in
        ctx.setFillColor(color(0.18, 0.15, 0.11))
        ctx.fillEllipse(in: CGRect(x: 10, y: 10, width: 44, height: 44))
        ctx.setFillColor(color(0.1, 0.08, 0.06))
        ctx.fillEllipse(in: CGRect(x: 20, y: 20, width: 24, height: 24))
    }

    static let base = speckled(color(0.45, 0.45, 0.43), seed: 5) { ctx, _ in
        ctx.setStrokeColor(color(0.85, 0.7, 0.1))
        ctx.setLineWidth(3)
        ctx.stroke(CGRect(x: 2, y: 2, width: 60, height: 60))
    }

    static let wall = speckled(color(0.12, 0.11, 0.1), seed: 6) { ctx, _ in
        ctx.setStrokeColor(color(0.2, 0.18, 0.16))
        ctx.setLineWidth(2)
        for row in 0..<4 {
            for col in -1..<3 {
                ctx.stroke(CGRect(x: CGFloat(col) * 32 + (row % 2 == 0 ? 0 : 16), y: CGFloat(row) * 16, width: 32, height: 16))
            }
        }
    }

    // MARK: Buildings

    private static var buildingCache: [String: SKTexture] = [:]
    private static let roofColors: [CGColor] = [
        color(0.42, 0.38, 0.34), color(0.36, 0.34, 0.33), color(0.47, 0.36, 0.28), color(0.33, 0.36, 0.38),
    ]

    /// Roof texture for a building footprint; stage 0 intact, 1 cracked, 2 heavily damaged.
    static func building(width: Int, height: Int, variant: Int, stage: Int) -> SKTexture {
        let style = variant % roofColors.count
        let key = "\(width)x\(height)-\(style)-\(stage)"
        if let cached = buildingCache[key] { return cached }
        let roof = roofColors[style]
        let texture = render(CGSize(width: CGFloat(width) * 64, height: CGFloat(height) * 64)) { ctx, s in
            var rng = SeededRandom(seed: UInt64(width * 1000 + height * 100 + style))
            let rect = CGRect(origin: .zero, size: s)
            ctx.setFillColor(color(0.15, 0.14, 0.13))
            ctx.fill(rect)
            ctx.setFillColor(roof)
            ctx.fill(rect.insetBy(dx: 5, dy: 5))
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.25))
            ctx.setLineWidth(2)
            ctx.stroke(rect.insetBy(dx: 10, dy: 10))
            for _ in 0..<(width * height / 2 + 1) {
                let w = CGFloat.random(in: 10...22, using: &rng)
                let h = CGFloat.random(in: 10...22, using: &rng)
                let unit = CGRect(x: CGFloat.random(in: 14...(s.width - 14 - w), using: &rng),
                                  y: CGFloat.random(in: 14...(s.height - 14 - h), using: &rng), width: w, height: h)
                ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
                ctx.fill(unit)
                ctx.setStrokeColor(CGColor(gray: 0.25, alpha: 1))
                ctx.setLineWidth(1.5)
                ctx.stroke(unit)
            }
            if stage >= 1 {
                drawDamage(ctx, s, rng: &rng, cracks: stage == 1 ? 4 : 10, holes: stage == 1 ? 0 : 3)
            }
        }
        buildingCache[key] = texture
        return texture
    }

    private static func drawDamage(_ ctx: CGContext, _ s: CGSize, rng: inout SeededRandom, cracks: Int, holes: Int) {
        ctx.setStrokeColor(CGColor(gray: 0.08, alpha: 0.9))
        ctx.setLineWidth(2)
        for _ in 0..<cracks {
            var p = CGPoint(x: CGFloat.random(in: 8...(s.width - 8), using: &rng), y: CGFloat.random(in: 8...(s.height - 8), using: &rng))
            ctx.move(to: p)
            for _ in 0..<4 {
                p.x += CGFloat.random(in: -18...18, using: &rng)
                p.y += CGFloat.random(in: -18...18, using: &rng)
                ctx.addLine(to: p)
            }
            ctx.strokePath()
        }
        for _ in 0..<holes {
            let r = CGFloat.random(in: 12...22, using: &rng)
            let c = CGPoint(x: CGFloat.random(in: r...(s.width - r), using: &rng), y: CGFloat.random(in: r...(s.height - r), using: &rng))
            ctx.setFillColor(CGColor(gray: 0.05, alpha: 0.6))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 1.5, y: c.y - r * 1.5, width: r * 3, height: r * 3))
            ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
    }

    // MARK: Infantry

    static func soldier(_ uniform: CGColor, weaponLength: CGFloat, weaponWidth: CGFloat) -> SKTexture {
        render(CGSize(width: 32, height: 24)) { ctx, _ in
            ctx.setFillColor(color(0.08, 0.08, 0.08))
            ctx.fill(CGRect(x: 12, y: 13, width: weaponLength, height: weaponWidth))
            ctx.setFillColor(uniform)
            ctx.fillEllipse(in: CGRect(x: 3, y: 2, width: 16, height: 20))
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
            ctx.fillEllipse(in: CGRect(x: 6, y: 7, width: 10, height: 10))
        }
    }

    static let rifleman = soldier(color(0.55, 0.5, 0.35), weaponLength: 16, weaponWidth: 3)
    static let machineGunner = soldier(color(0.3, 0.36, 0.22), weaponLength: 18, weaponWidth: 5)
    static let bazookaSoldier = soldier(color(0.45, 0.33, 0.22), weaponLength: 20, weaponWidth: 7)
    static let mortarSoldier = soldier(color(0.4, 0.4, 0.42), weaponLength: 10, weaponWidth: 9)

    static func infantry(_ kind: InfantryKind) -> SKTexture {
        switch kind {
        case .rifleman: return rifleman
        case .machineGunner: return machineGunner
        case .bazooka: return bazookaSoldier
        case .mortar: return mortarSoldier
        }
    }

    // MARK: Pickups

    static let gasCan = render(CGSize(width: 24, height: 30)) { ctx, _ in
        ctx.setFillColor(color(0.75, 0.12, 0.1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 2, y: 2, width: 20, height: 24), cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(color(0.45, 0.06, 0.05))
        ctx.fill(CGRect(x: 14, y: 24, width: 6, height: 6))
        ctx.setStrokeColor(color(0.95, 0.85, 0.2))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 6, y: 6)); ctx.addLine(to: CGPoint(x: 18, y: 22))
        ctx.move(to: CGPoint(x: 18, y: 6)); ctx.addLine(to: CGPoint(x: 6, y: 22))
        ctx.strokePath()
    }

    static let ammoCrate = render(CGSize(width: 28, height: 22)) { ctx, _ in
        ctx.setFillColor(color(0.3, 0.38, 0.2))
        ctx.fill(CGRect(x: 1, y: 1, width: 26, height: 20))
        ctx.setStrokeColor(color(0.15, 0.2, 0.1))
        ctx.setLineWidth(2)
        ctx.stroke(CGRect(x: 2, y: 2, width: 24, height: 18))
        ctx.setFillColor(color(0.95, 0.8, 0.2))
        ctx.fill(CGRect(x: 6, y: 9, width: 16, height: 4))
    }

    // MARK: Projectiles and particles

    static let shell = render(CGSize(width: 12, height: 5)) { ctx, s in
        ctx.setFillColor(color(1, 0.9, 0.5))
        ctx.fillEllipse(in: CGRect(origin: .zero, size: s))
    }

    static let bullet = render(CGSize(width: 7, height: 2)) { ctx, s in
        ctx.setFillColor(color(1, 0.95, 0.6))
        ctx.fill(CGRect(origin: .zero, size: s))
    }

    static let rocket = render(CGSize(width: 16, height: 6)) { ctx, _ in
        ctx.setFillColor(color(0.3, 0.32, 0.25))
        ctx.fill(CGRect(x: 4, y: 1, width: 12, height: 4))
        ctx.setFillColor(color(1, 0.6, 0.1))
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 6, height: 6))
    }

    static let mortarShell = render(CGSize(width: 10, height: 10)) { ctx, s in
        ctx.setFillColor(color(0.15, 0.15, 0.15))
        ctx.fillEllipse(in: CGRect(origin: .zero, size: s))
    }

    static func projectile(_ weapon: WeaponKind) -> SKTexture {
        switch weapon {
        case .mainGun, .enemyShell: return shell
        case .machineGun, .rifle, .enemyMachineGun: return bullet
        case .bazooka: return rocket
        case .mortar: return mortarShell
        }
    }

    static func radialGradient(size: CGFloat, inner: CGColor, outer: CGColor) -> SKTexture {
        render(CGSize(width: size, height: size)) { ctx, _ in
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [inner, outer] as CFArray, locations: [0, 1])!
            let c = CGPoint(x: size / 2, y: size / 2)
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size / 2, options: [])
        }
    }

    static let spark = radialGradient(size: 16, inner: color(1, 1, 1, 1), outer: color(1, 1, 1, 0))
    static let scorch = radialGradient(size: 64, inner: color(0, 0, 0, 0.55), outer: color(0, 0, 0, 0))

    /// Two track imprints, perpendicular to the direction of travel.
    static let trackMark = render(CGSize(width: 6, height: 42)) { ctx, _ in
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.28))
        ctx.fill(CGRect(x: 0, y: 1, width: 6, height: 8))
        ctx.fill(CGRect(x: 0, y: 33, width: 6, height: 8))
    }
}
