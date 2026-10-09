import AppKit
import SpriteKit
import TanksCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Tanks of Doom"
        window.minSize = NSSize(width: 800, height: 500)

        let view = GameView(frame: frame)
        view.ignoresSiblingOrder = true
        window.contentView = view
        window.center()
        window.makeFirstResponder(view)
        let env = ProcessInfo.processInfo.environment
        // Developer shortcut: TANKS_START_LEVEL=<n> skips the title screen and opens the
        // window in the background without taking keyboard focus.
        if let level = env["TANKS_START_LEVEL"].flatMap(Int.init), level > 0 {
            window.orderFront(nil)
            view.presentScene(GameScene(size: frame.size, levelNumber: level, runStats: RunStats()))
        } else if env["TANKS_HOTSEAT"] == "1" {
            // Developer shortcut: a versus match with both players on this keyboard.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            let settings = MatchSettings(lives: 3, aiIntensity: .normal, seed: .random(in: 0...UInt64.max))
            view.presentScene(GameScene(size: frame.size, versus: settings, role: .hotSeat))
        } else if QuickMatch.start(in: view) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            view.presentScene(MenuScene.title(size: frame.size))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Tanks of Doom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
