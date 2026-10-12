#if os(Linux)
import CSDL2

/// Maps macOS font names to installed fonts (via fontconfig) and renders text with SDL_ttf.
enum Fonts {
    /// fontconfig patterns for the macOS fonts the game asks for.
    private static let substitutes: [String: String] = [
        "Impact": "Impact,Anton,Oswald,Bebas Neue,League Gothic,Nimbus Sans Narrow,Liberation Sans Narrow,DejaVu Sans Condensed,sans-serif:bold",
        "Menlo-Bold": "Menlo,DejaVu Sans Mono,Liberation Mono,Noto Sans Mono,monospace:bold",
        "Menlo": "Menlo,DejaVu Sans Mono,Liberation Mono,Noto Sans Mono,monospace",
    ]
    private static var paths: [String: String?] = [:]
    private static var fonts: [String: OpaquePointer] = [:]
    private static var warned = false

    static func render(_ text: String, fontName: String?, pixelSize: Int32, scale: CGFloat) -> (texture: SKTexture, descent: CGFloat)? {
        guard pixelSize > 0, let renderer = Display.renderer, let font = font(named: fontName ?? "Helvetica", pixelSize: pixelSize),
              let surface = TTF_RenderUTF8_Blended(font, text, SDL_Color(r: 255, g: 255, b: 255, a: 255)) else { return nil }
        defer { SDL_FreeSurface(surface) }
        guard let texture = SDL_CreateTextureFromSurface(renderer, surface) else { return nil }
        let size = CGSize(width: CGFloat(surface.pointee.w) / scale, height: CGFloat(surface.pointee.h) / scale)
        return (SKTexture(gpuTexture: texture, pointSize: size), CGFloat(-TTF_FontDescent(font)) / scale)
    }

    private static func font(named name: String, pixelSize: Int32) -> OpaquePointer? {
        let key = "\(name)|\(pixelSize)"
        if let font = fonts[key] { return font }
        if TTF_WasInit() == 0 && TTF_Init() != 0 { return nil }
        guard let path = path(for: name), let font = TTF_OpenFont(path, pixelSize) else {
            if !warned {
                warned = true
                FileHandle.standardError.write("Tanks of Doom: no usable font found for \(name); text will be missing.\n".data(using: .utf8)!)
            }
            return nil
        }
        fonts[key] = font
        return font
    }

    private static func path(for name: String) -> String? {
        if let cached = paths[name] { return cached }
        let pattern = substitutes[name] ?? name
        let found = fontconfigMatch(pattern) ?? fontconfigMatch("sans-serif:bold")
        paths[name] = found
        return found
    }

    private static func fontconfigMatch(_ pattern: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["fc-match", "--format=%{file}", pattern]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let path = String(data: data, encoding: .utf8), !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }
}
#endif
