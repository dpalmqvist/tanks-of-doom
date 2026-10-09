import SpriteKit
import TanksNet

/// Guest-side state: buffered snapshots from the host, the shot and mortar nodes standing in for
/// what they describe, and the keys on their way to the host.
final class GuestWorld {
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
