#if os(Linux)
import CSDL2

public enum SKTextureFilteringMode {
    case nearest, linear
}

/// Pixel data plus its size in points; uploaded to the GPU on first use.
open class SKTexture {
    private let image: CGImage?
    private let pointSize: CGSize
    private var gpuTexture: OpaquePointer?
    public var filteringMode: SKTextureFilteringMode = .linear {
        didSet { applyScaleMode() }
    }

    public init(cgImage: CGImage) {
        image = cgImage
        pointSize = CGSize(width: cgImage.width, height: cgImage.height)
    }

    init(image: CGImage, pointSize: CGSize) {
        self.image = image
        self.pointSize = pointSize
    }

    /// Wraps an existing GPU texture (rendered text).
    init(gpuTexture: OpaquePointer, pointSize: CGSize) {
        image = nil
        self.gpuTexture = gpuTexture
        self.pointSize = pointSize
        applyScaleMode()
    }

    /// Draws with Core Graphics-style calls at the display's pixel density.
    public convenience init(size: CGSize, drawing draw: (CGContext, CGSize) -> Void) {
        let context = CGContext(size: size, scale: Display.textureScale)
        draw(context, size)
        self.init(image: context.makeImage()!, pointSize: size)
    }

    deinit {
        if let gpuTexture { SDL_DestroyTexture(gpuTexture) }
    }

    public func size() -> CGSize { pointSize }

    /// The GPU texture, created on first use.
    var sdlTexture: OpaquePointer? {
        if gpuTexture == nil, let image, let renderer = Display.renderer {
            gpuTexture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ABGR8888.rawValue, Int32(SDL_TEXTUREACCESS_STATIC.rawValue),
                                           Int32(image.width), Int32(image.height))
            if let gpuTexture {
                image.pixels.withUnsafeBytes { bytes in
                    _ = SDL_UpdateTexture(gpuTexture, nil, bytes.baseAddress, Int32(image.width * 4))
                }
                applyScaleMode()
            }
        }
        return gpuTexture
    }

    private func applyScaleMode() {
        guard let gpuTexture else { return }
        SDL_SetTextureScaleMode(gpuTexture, filteringMode == .nearest ? SDL_ScaleModeNearest : SDL_ScaleModeLinear)
    }
}

/// Shared rendering state for the single window.
enum Display {
    static var renderer: OpaquePointer?
    /// Device pixels per point.
    static var pixelScale: CGFloat = 1
    /// Pixel density for generated textures: one texel per device pixel.
    static var textureScale: CGFloat { pixelScale }
}
#endif
