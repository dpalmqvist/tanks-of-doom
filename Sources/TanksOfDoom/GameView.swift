import AppKit
import SpriteKit

/// SKView that forwards every keyboard and mouse event (including mouse-moved and right
/// mouse) straight to the presented scene.
final class GameView: SKView {
    private var mouseTracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTracking { removeTrackingArea(mouseTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        mouseTracking = area
    }

    override func keyDown(with event: NSEvent) { scene?.keyDown(with: event) }
    override func keyUp(with event: NSEvent) { scene?.keyUp(with: event) }
    override func mouseDown(with event: NSEvent) { scene?.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { scene?.mouseUp(with: event) }
    override func mouseDragged(with event: NSEvent) { scene?.mouseDragged(with: event) }
    override func mouseMoved(with event: NSEvent) { scene?.mouseMoved(with: event) }
    override func rightMouseDown(with event: NSEvent) { scene?.rightMouseDown(with: event) }
    override func rightMouseUp(with event: NSEvent) { scene?.rightMouseUp(with: event) }
    override func rightMouseDragged(with event: NSEvent) { scene?.rightMouseDragged(with: event) }
}
