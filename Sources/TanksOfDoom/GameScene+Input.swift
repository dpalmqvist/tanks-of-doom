import AppKit
import SpriteKit
import TanksNet

extension GameScene {
    override func keyDown(with event: NSEvent) {
        if setHotSeatKey(event.keyCode, down: true, isRepeat: event.isARepeat) { return }
        setKey(event.keyCode, down: true)
        if !event.isARepeat { handleKeyPress(event.keyCode) }
    }

    func handleKeyPress(_ code: UInt16) {
        switch code {
        case 46: hud.toggleMinimap()                   // M
        case 53: togglePause()                         // Esc
        case 15: press(InputFrame.abandon) { abandonTank(localPlayer) }            // R
        case 48: press(InputFrame.cycleTarget) { cycleTarget(for: localPlayer) }   // Tab
        case 12, 14: press(InputFrame.manualTurret) { localPlayer.turretAim.manualInput() }   // Q, E
        default: break
        }
    }

    /// One-shot keys: a guest sends them to the host; everyone else acts on them here.
    private func press(_ bit: UInt8, otherwise act: () -> Void) {
        if let world = guestWorld {
            world.presses |= bit
        } else {
            act()
        }
    }

    override func keyUp(with event: NSEvent) {
        if setHotSeatKey(event.keyCode, down: false, isRepeat: false) { return }
        setKey(event.keyCode, down: false)
    }

    func setKey(_ code: UInt16, down: Bool) {
        switch code {
        case 13, 126: localPlayer.input.forward = down    // W, up arrow
        case 1, 125: localPlayer.input.backward = down    // S, down arrow
        case 0, 123: localPlayer.input.left = down        // A, left arrow
        case 2, 124: localPlayer.input.right = down       // D, right arrow
        case 49: localPlayer.input.space = down
        case 3: localPlayer.input.fKey = down             // F
        case 12: localPlayer.input.turretLeft = down      // Q
        case 14: localPlayer.input.turretRight = down     // E
        default: break
        }
    }

    /// Debug hot-seat: the second player drives with I/J/K/L, turns the turret with U/O,
    /// fires with N (main gun) and B (MG), and H picks the next target.
    private func setHotSeatKey(_ code: UInt16, down: Bool, isRepeat: Bool) -> Bool {
        guard case .versus(.hotSeat) = mode else { return false }
        let second = player(.guest)
        switch code {
        case 34: second.input.forward = down        // I
        case 40: second.input.backward = down       // K
        case 38: second.input.left = down           // J
        case 37: second.input.right = down          // L
        case 32:                                    // U
            second.input.turretLeft = down
            if down { second.turretAim.manualInput() }
        case 31:                                    // O
            second.input.turretRight = down
            if down { second.turretAim.manualInput() }
        case 45: second.input.space = down          // N
        case 11: second.input.fKey = down           // B
        case 4: if down && !isRepeat { cycleTarget(for: second) }   // H
        default: return false
        }
        return true
    }
}
