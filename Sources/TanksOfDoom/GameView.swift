import AppKit
import SpriteKit

/// SKView that forwards keyboard events and clicks (used by the menus) straight to the
/// presented scene.
final class GameView: SKView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) { scene?.keyDown(with: event) }
    override func keyUp(with event: NSEvent) { scene?.keyUp(with: event) }
    override func mouseDown(with event: NSEvent) { scene?.mouseDown(with: event) }
}
