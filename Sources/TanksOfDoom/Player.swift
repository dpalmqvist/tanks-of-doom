import AppKit
import TanksCore

/// A human-driven tank and everything its driver controls: held keys, turret aim mode and target lock.
final class Player {
    let slot: PlayerSlot
    let tank: PlayerTank
    var input = InputState()
    var turretAim = TurretAim()
    var lockedTargetID: Int?
    var inBase = false

    init(slot: PlayerSlot) {
        self.slot = slot
        tank = PlayerTank(slot: slot)
    }
}

extension PlayerSlot {
    /// Matches the tank paint: olive for the host, steel blue for the guest.
    var color: NSColor {
        switch self {
        case .host: return NSColor(calibratedRed: 0.6, green: 0.75, blue: 0.3, alpha: 1)
        case .guest: return NSColor(calibratedRed: 0.45, green: 0.65, blue: 0.95, alpha: 1)
        }
    }
}
