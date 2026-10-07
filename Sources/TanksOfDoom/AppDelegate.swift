import AppKit
import SpriteKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Tanks of Doom"
        window.minSize = NSSize(width: 800, height: 500)
        window.acceptsMouseMovedEvents = true

        let view = GameView(frame: frame)
        view.ignoresSiblingOrder = true
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate()
        // Developer shortcut: TANKS_START_LEVEL=<n> skips the title screen.
        if let level = ProcessInfo.processInfo.environment["TANKS_START_LEVEL"].flatMap(Int.init), level > 0 {
            view.presentScene(GameScene(size: frame.size, levelNumber: level, runStats: RunStats()))
        } else {
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
