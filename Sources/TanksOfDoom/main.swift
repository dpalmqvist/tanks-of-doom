#if canImport(AppKit)
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
#else
import Foundation
import LinuxSpriteKit

// Linux: an SDL window standing in for AppDelegate's NSWindow + SKView.
let size = CGSize(width: 1280, height: 800)
guard let view = SKView(title: "Tanks of Doom", size: size, minimumSize: CGSize(width: 800, height: 500)) else { exit(1) }
// Synthesize the sound effects now rather than mid-game on the first shot.
_ = Audio.shared
// Developer shortcut: TANKS_START_LEVEL=<n> skips the title screen.
if let level = ProcessInfo.processInfo.environment["TANKS_START_LEVEL"].flatMap(Int.init), level > 0 {
    view.presentScene(GameScene(size: view.bounds, levelNumber: level, runStats: RunStats()))
} else {
    view.presentScene(MenuScene.title(size: view.bounds))
}
view.run()
#endif
