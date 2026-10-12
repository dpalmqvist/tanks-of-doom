#if os(Linux)
import CSDL2

/// A key or mouse event. `keyCode` uses macOS virtual key codes, so game code matches on the same numbers.
public final class NSEvent {
    public let keyCode: UInt16
    public let isARepeat: Bool

    init(keyCode: UInt16, isARepeat: Bool) {
        self.keyCode = keyCode
        self.isARepeat = isARepeat
    }

    /// SDL scancodes (physical key positions) to macOS virtual key codes (also positional).
    static func macKeyCode(_ scancode: SDL_Scancode) -> UInt16? {
        let letters: [UInt16] = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6]   // A...Z
        let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]   // 1...9, 0
        let raw = scancode.rawValue
        if raw >= SDL_SCANCODE_A.rawValue && raw <= SDL_SCANCODE_Z.rawValue { return letters[Int(raw - SDL_SCANCODE_A.rawValue)] }
        if raw >= SDL_SCANCODE_1.rawValue && raw <= SDL_SCANCODE_0.rawValue { return digits[Int(raw - SDL_SCANCODE_1.rawValue)] }
        switch scancode {
        case SDL_SCANCODE_RETURN: return 36
        case SDL_SCANCODE_TAB: return 48
        case SDL_SCANCODE_SPACE: return 49
        case SDL_SCANCODE_BACKSPACE: return 51
        case SDL_SCANCODE_ESCAPE: return 53
        case SDL_SCANCODE_KP_ENTER: return 76
        case SDL_SCANCODE_LEFT: return 123
        case SDL_SCANCODE_RIGHT: return 124
        case SDL_SCANCODE_DOWN: return 125
        case SDL_SCANCODE_UP: return 126
        default: return nil
        }
    }
}

/// The game window: owns the SDL window and renderer, runs the frame loop and presents scenes.
open class SKView {
    public private(set) var scene: SKScene?
    public var ignoresSiblingOrder = false
    private let window: OpaquePointer
    private let renderer: OpaquePointer
    private var heldKeys: Set<UInt16> = []
    private var running = true
    private var transition: (incoming: SKScene, duration: Double, elapsed: Double, switched: Bool)?

    /// Opens the window. Returns nil (after printing why) if no display is available.
    public init?(title: String, size: CGSize, minimumSize: CGSize) {
        SDL_SetHint(SDL_HINT_APP_NAME, title)
        SDL_SetHint("SDL_VIDEO_WAYLAND_WMCLASS", "tanks-of-doom")
        SDL_SetHint("SDL_VIDEO_X11_WMCLASS", "tanks-of-doom")
        guard SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) == 0 else {
            Self.fail("could not initialise video")
            return nil
        }
        let flags = SDL_WINDOW_RESIZABLE.rawValue | SDL_WINDOW_ALLOW_HIGHDPI.rawValue
        guard let window = SDL_CreateWindow(title, Int32(SDL_WINDOWPOS_CENTERED_MASK), Int32(SDL_WINDOWPOS_CENTERED_MASK),
                                            Int32(size.width), Int32(size.height), flags) else {
            Self.fail("could not open a window")
            return nil
        }
        guard let renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED.rawValue | SDL_RENDERER_PRESENTVSYNC.rawValue)
                ?? SDL_CreateRenderer(window, -1, 0) else {
            Self.fail("could not create a renderer")
            SDL_DestroyWindow(window)
            return nil
        }
        SDL_SetWindowMinimumSize(window, Int32(minimumSize.width), Int32(minimumSize.height))
        self.window = window
        self.renderer = renderer
        Display.renderer = renderer
        updatePixelScale()
    }

    private static func fail(_ what: String) {
        let reason = String(cString: SDL_GetError())
        FileHandle.standardError.write("Tanks of Doom: \(what): \(reason)\n".data(using: .utf8)!)
    }

    /// The window's size in points.
    public var bounds: CGSize {
        var w: Int32 = 0, h: Int32 = 0
        SDL_GetWindowSize(window, &w, &h)
        return CGSize(width: Int(w), height: Int(h))
    }

    private var pixelSize: CGSize {
        var w: Int32 = 0, h: Int32 = 0
        SDL_GetRendererOutputSize(renderer, &w, &h)
        return CGSize(width: Int(w), height: Int(h))
    }

    private func updatePixelScale() {
        let points = bounds.width
        Display.pixelScale = points > 0 ? max(1, pixelSize.width / points) : 1
    }

    public func presentScene(_ scene: SKScene) {
        if let old = self.scene {
            old.willMove(from: self)
            old.view = nil
        }
        self.scene = scene
        scene.view = self
        if scene.scaleMode == .resizeFill { scene.size = bounds }
        scene.didMove(to: self)
    }

    public func presentScene(_ scene: SKScene, transition: SKTransition) {
        guard self.scene != nil, transition.duration > 0 else {
            presentScene(scene)
            return
        }
        self.transition = (scene, transition.duration, 0, false)
    }

    /// Runs the event and frame loop until the window is closed.
    public func run() {
        let frequency = Double(SDL_GetPerformanceFrequency())
        var info = SDL_RendererInfo()
        SDL_GetRendererInfo(renderer, &info)
        let hasVSync = info.flags & SDL_RENDERER_PRESENTVSYNC.rawValue != 0
        var last = Double(SDL_GetPerformanceCounter()) / frequency
        while running {
            let frameStart = Double(SDL_GetPerformanceCounter()) / frequency
            pollEvents()
            let now = Double(SDL_GetPerformanceCounter()) / frequency
            let dt = min(now - last, 0.1)
            last = now
            step(currentTime: now, dt: dt)
            draw()
            if !hasVSync {
                let spent = Double(SDL_GetPerformanceCounter()) / frequency - frameStart
                if spent < 1.0 / 120 { SDL_Delay(UInt32((1.0 / 120 - spent) * 1000)) }
            }
        }
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(window)
        SDL_Quit()
    }

    private func step(currentTime: Double, dt: Double) {
        if var t = transition {
            // Scenes are paused while the transition plays.
            t.elapsed += dt
            if !t.switched && t.elapsed >= t.duration / 2 {
                t.switched = true
                presentScene(t.incoming)
            }
            transition = t.elapsed >= t.duration ? nil : t
            return
        }
        guard let scene else { return }
        scene.update(currentTime)
        scene.evaluateActions(dt: dt)
    }

    private func draw() {
        let background = scene?.backgroundColor.cgColor ?? CGColor(gray: 0, alpha: 1)
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, v * 255))) }
        SDL_SetRenderDrawColor(renderer, byte(background.red), byte(background.green), byte(background.blue), 255)
        SDL_RenderClear(renderer)
        let size = pixelSize
        if let scene {
            scene.render(in: RenderContext(renderer: renderer, pixelSize: size, scale: Display.pixelScale))
        }
        if let t = transition {
            let half = t.duration / 2
            let darkness = t.switched ? 1 - (t.elapsed - half) / half : t.elapsed / half
            SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
            SDL_SetRenderDrawColor(renderer, 0, 0, 0, byte(CGFloat(max(0, min(1, darkness)))))
            var rect = SDL_Rect(x: 0, y: 0, w: Int32(size.width), h: Int32(size.height))
            SDL_RenderFillRect(renderer, &rect)
        }
        SDL_RenderPresent(renderer)
    }

    private func pollEvents() {
        var event = SDL_Event()
        while SDL_PollEvent(&event) != 0 {
            switch SDL_EventType(event.type) {
            case SDL_QUIT:
                running = false
            case SDL_KEYDOWN:
                let key = event.key.keysym
                let ctrl = UInt32(key.mod) & UInt32(KMOD_CTRL.rawValue) != 0
                if ctrl && key.scancode == SDL_SCANCODE_Q {
                    running = false
                } else if key.scancode == SDL_SCANCODE_F11 && event.key.repeat == 0 {
                    toggleFullscreen()
                } else if let code = NSEvent.macKeyCode(key.scancode) {
                    heldKeys.insert(code)
                    scene?.keyDown(with: NSEvent(keyCode: code, isARepeat: event.key.repeat != 0))
                }
            case SDL_KEYUP:
                if let code = NSEvent.macKeyCode(event.key.keysym.scancode) {
                    heldKeys.remove(code)
                    scene?.keyUp(with: NSEvent(keyCode: code, isARepeat: false))
                }
            case SDL_MOUSEBUTTONDOWN:
                scene?.mouseDown(with: NSEvent(keyCode: 0, isARepeat: false))
            case SDL_WINDOWEVENT:
                switch SDL_WindowEventID(UInt32(event.window.event)) {
                case SDL_WINDOWEVENT_SIZE_CHANGED, SDL_WINDOWEVENT_RESIZED:
                    updatePixelScale()
                    if let scene, scene.scaleMode == .resizeFill { scene.size = bounds }
                case SDL_WINDOWEVENT_FOCUS_LOST:
                    // Keys released while the window is in the background never arrive; release them now.
                    for code in heldKeys { scene?.keyUp(with: NSEvent(keyCode: code, isARepeat: false)) }
                    heldKeys.removeAll()
                default:
                    break
                }
            default:
                break
            }
        }
    }

    private func toggleFullscreen() {
        let fullscreen = SDL_GetWindowFlags(window) & SDL_WINDOW_FULLSCREEN_DESKTOP.rawValue == SDL_WINDOW_FULLSCREEN_DESKTOP.rawValue
        SDL_SetWindowFullscreen(window, fullscreen ? 0 : SDL_WINDOW_FULLSCREEN_DESKTOP.rawValue)
    }
}
#endif
