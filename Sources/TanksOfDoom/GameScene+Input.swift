import AppKit
import SpriteKit

extension GameScene {
    override func keyDown(with event: NSEvent) {
        setKey(event.keyCode, down: true)
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
        default: break
        }
    }

    override func mouseDown(with event: NSEvent) { input.leftMouse = true; trackMouse(event) }
    override func mouseUp(with event: NSEvent) { input.leftMouse = false }
    override func mouseDragged(with event: NSEvent) { trackMouse(event) }
    override func rightMouseDown(with event: NSEvent) { input.rightMouse = true; trackMouse(event) }
    override func rightMouseUp(with event: NSEvent) { input.rightMouse = false }
    override func rightMouseDragged(with event: NSEvent) { trackMouse(event) }
    override func mouseMoved(with event: NSEvent) { trackMouse(event) }

    /// Stored in camera space so the aim stays correct while the camera moves.
    func trackMouse(_ event: NSEvent) {
        mouseInCamera = event.location(in: cameraNode)
    }
}
