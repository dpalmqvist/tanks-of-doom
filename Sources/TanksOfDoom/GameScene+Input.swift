import AppKit
import SpriteKit

extension GameScene {
    override func keyDown(with event: NSEvent) {
        setKey(event.keyCode, down: true)
        if !event.isARepeat { handleKeyPress(event.keyCode) }
    }

    func handleKeyPress(_ code: UInt16) {
        switch code {
        case 46: hud.toggleMinimap()                   // M
        case 53: togglePause()                         // Esc
        case 15: abandonTank(localPlayer)              // R
        case 48: cycleTarget(for: localPlayer)         // Tab
        case 12, 14: localPlayer.turretAim.manualInput()   // Q, E
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
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
}
