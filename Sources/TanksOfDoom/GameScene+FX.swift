import AppKit
import SpriteKit
import TanksCore
import TanksNet

/// Who should see or hear an effect.
enum Audience {
    case everyone
    case only(Player)
    case allBut(Player)

    func includes(_ player: Player) -> Bool {
        switch self {
        case .everyone: return true
        case .only(let p): return p === player
        case .allBut(let p): return p !== player
        }
    }
}

extension CGPoint {
    var vec: Vec2 { Vec2(Float(x), Float(y)) }
}

extension Vec2 {
    var cgPoint: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
}

extension FXColor {
    var nsColor: NSColor {
        switch self {
        case .white: return .white
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .orange: return .systemOrange
        }
    }
}

extension GameScene {
    /// The player on the other Mac when this one is hosting a networked match.
    var remotePlayer: Player? {
        guard let role = versusRole, role.isHost else { return nil }
        return players.first { $0 !== localPlayer }
    }

    /// Every sight and sound the simulation makes goes through here. It plays on this Mac if the local
    /// player is in the audience, and on a host it's queued for the guest's next snapshot if they are.
    func fx(_ event: GameEvent, for audience: Audience = .everyone) {
        if audience.includes(localPlayer) { playLocally(event) }
        if let remote = remotePlayer, audience.includes(remote) { outgoingEvents.append(event) }
    }

    func playLocally(_ event: GameEvent) {
        switch event {
        case let .explosion(at, scale): effects.explosion(at: at.cgPoint, scale: CGFloat(scale))
        case let .spark(at): effects.spark(at: at.cgPoint)
        case let .dust(at): effects.dustPuff(at: at.cgPoint)
        case let .muzzleFlash(at, angle, big): effects.muzzleFlash(at: at.cgPoint, angle: CGFloat(angle), big: big)
        case let .text(text, at, color): effects.floatingText(text, at: at.cgPoint, color: color.nsColor)
        case let .sound(sound, at, volume): playSound(sound, at: at.cgPoint, volume: volume)
        case let .uiSound(sound, volume): Audio.shared.play(sound, volume: volume)
        case let .shake(magnitude, duration): shake(CGFloat(magnitude), duration: Double(duration))
        case let .buildingHP(id, hp): mirrorBuildingHP(Int(id), Int(hp))
        case let .kill(killer, victim): hud.addKillFeed(KillFeed.line(killer: killer, victim: victim, viewer: localPlayer.slot))
        case let .flash(text, color, duration): hud.flash(text, color: color.nsColor, duration: Double(duration))
        case let .matchOver(winner): matchEnded(winner: winner)
        }
    }

    /// Guest side: the host reported a building's new hit points.
    func mirrorBuildingHP(_ id: Int, _ hp: Int) {
        let result = level.setBuildingHP(id, to: hp)
        guard result != .none else { return }
        renderer.update(level.buildings[id])
        if result == .destroyed { hud.minimap.refresh(map: level.map) }
    }
}
