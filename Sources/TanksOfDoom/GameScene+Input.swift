import AppKit
import SpriteKit

extension GameScene {
    override func keyDown(with event: NSEvent) {
        setKey(event.keyCode, down: true)
        if !event.isARepeat { handleKeyPress(event.keyCode) }
    }

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

    override func keyUp(with event: NSEvent) {
        setKey(event.keyCode, down: false)
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

    override func mouseDown(with event: NSEvent) { input.leftMouse = true; trackMouse(event, used: true) }
    override func mouseUp(with event: NSEvent) { input.leftMouse = false }
    override func mouseDragged(with event: NSEvent) { trackMouse(event) }
    override func rightMouseDown(with event: NSEvent) { input.rightMouse = true; trackMouse(event, used: true) }
    override func rightMouseUp(with event: NSEvent) { input.rightMouse = false }
    override func rightMouseDragged(with event: NSEvent) { trackMouse(event) }
    override func mouseMoved(with event: NSEvent) { trackMouse(event) }

    /// Stored in camera space so the aim stays correct while the camera moves. A click or a
    /// deliberate movement (not jitter) hands turret control to the mouse.
    func trackMouse(_ event: NSEvent, used: Bool = false) {
        mouseInCamera = event.location(in: cameraNode)
        if used || hypot(event.deltaX, event.deltaY) > 3 { turretAim.mouseUsed() }
    }
}
