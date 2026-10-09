import CoreGraphics
import SpriteKit
import TanksNet

/// Guest-side state: buffered snapshots from the host, the shot and mortar nodes standing in for
/// what they describe, and the keys on their way to the host.
final class GuestWorld {
    static let correctionTime = 0.1
    static let ignoreDistance: CGFloat = 2
    static let snapDistance: CGFloat = 64
    static let headingIgnore: CGFloat = 0.02
    static let headingSnap: CGFloat = 0.5

    /// Local inputs the host hasn't confirmed, for replay after each snapshot.
    var history = InputHistory<InputState>()
    /// What's left of the last correction, eased in over `correctionTime`.
    var correction = CGPoint.zero
    /// What's left of the last heading correction, eased in over `correctionTime`.
    var headingCorrection: CGFloat = 0
    /// Local stand-ins for the guns' reload, so firing looks and sounds instant.
    var mainCooldown = 0.0
    var machineGunCooldown = 0.0

    var buffer = SnapshotBuffer()
    var shots: [UInt32: Projectile] = [:]
    var mortars: [UInt32: MortarShell] = [:]
    var inputTimer = 0.0
    var inputSeq: UInt32 = 0
    /// One-shot keys (Tab, Q/E, R) waiting for the next input frame.
    var presses: UInt8 = 0

    func takePresses() -> UInt8 {
        defer { presses = 0 }
        return presses
    }
}
