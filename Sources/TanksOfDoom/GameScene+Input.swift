#if canImport(AppKit)
import AppKit
import SpriteKit
#else
import LinuxSpriteKit
#endif

extension GameScene {
    func handleKeyPress(_ code: UInt16) {
        switch code {
        case 46: hud.toggleMinimap()   // M
        case 53: togglePause()         // Esc
        case 15: abandonTank()         // R
        case 48: cycleTarget()         // Tab
        case 12, 14: turretAim.manualInput()   // Q, E
        default: break
        }
    }

    func setKey(_ code: UInt16, down: Bool) {
        switch code {
        case 13, 126: input.forward = down    // W, up arrow
        case 1, 125: input.backward = down    // S, down arrow
        case 0, 123: input.left = down        // A, left arrow
        case 2, 124: input.right = down       // D, right arrow
        case 49: input.space = down
        case 3: input.fKey = down             // F
        case 12: input.turretLeft = down      // Q
        case 14: input.turretRight = down     // E
        default: break
        }
    }
}
