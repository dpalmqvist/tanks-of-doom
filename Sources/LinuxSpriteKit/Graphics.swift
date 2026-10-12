#if os(Linux)
@_exported import Foundation

// The Core Graphics and AppKit drawing types the game uses, backed by a small software rasterizer.
// Coordinates follow Core Graphics: origin at the bottom left, y up.

public struct CGVector {
    public var dx: CGFloat
    public var dy: CGFloat
    public init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }
}

/// An sRGB colour with straight (non-premultiplied) alpha.
public struct CGColor {
    public var red, green, blue, alpha: CGFloat

    public init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(gray: CGFloat, alpha: CGFloat) {
        self.init(srgbRed: gray, green: gray, blue: gray, alpha: alpha)
    }
}

public struct NSColor {
    public var cgColor: CGColor

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        cgColor = CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public init(calibratedRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    public init(white: CGFloat, alpha: CGFloat) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    public func withAlphaComponent(_ alpha: CGFloat) -> NSColor {
        NSColor(red: cgColor.red, green: cgColor.green, blue: cgColor.blue, alpha: alpha)
    }

    public static let clear = NSColor(white: 0, alpha: 0)
    public static let black = NSColor(white: 0, alpha: 1)
    public static let white = NSColor(white: 1, alpha: 1)
    public static let gray = NSColor(white: 0.5, alpha: 1)
    public static let lightGray = NSColor(white: 2.0 / 3.0, alpha: 1)
    public static let yellow = NSColor(red: 1, green: 1, blue: 0, alpha: 1)
    public static let orange = NSColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    // macOS dark-appearance system colours.
    public static let systemRed = NSColor(red: 1, green: 0.27, blue: 0.23, alpha: 1)
    public static let systemGreen = NSColor(red: 0.2, green: 0.84, blue: 0.29, alpha: 1)
    public static let systemOrange = NSColor(red: 1, green: 0.62, blue: 0.04, alpha: 1)
    public static let systemYellow = NSColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)
}

public final class CGColorSpace {
    public static let sRGB = "sRGB"
    public init?(name: String) {}
}

public enum CGImageAlphaInfo: UInt32 {
    case premultipliedLast = 1
}

public final class CGGradient {
    let colors: [CGColor]
    let locations: [CGFloat]

    public init(colors: [CGColor], locations: [CGFloat]) {
        self.colors = colors
        self.locations = locations
    }

    func color(at t: CGFloat) -> CGColor {
        guard let last = locations.indices.last else { return CGColor(gray: 0, alpha: 0) }
        if t <= locations[0] { return colors[0] }
        for i in 1...last where t <= locations[i] {
            let f = (t - locations[i - 1]) / max(locations[i] - locations[i - 1], 1e-9)
            let a = colors[i - 1], b = colors[i]
            return CGColor(srgbRed: a.red + (b.red - a.red) * f, green: a.green + (b.green - a.green) * f,
                           blue: a.blue + (b.blue - a.blue) * f, alpha: a.alpha + (b.alpha - a.alpha) * f)
        }
        return colors[last]
    }
}

/// A path made of straight-line subpaths. Curves are flattened when they are added.
public class CGPath {
    struct Subpath {
        var points: [CGPoint]
        var closed: Bool
    }

    var subpaths: [Subpath] = []

    public init() {}

    public convenience init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: UnsafePointer<Int>?) {
        self.init()
        let rx = min(cornerWidth, rect.width / 2), ry = min(cornerHeight, rect.height / 2)
        var points: [CGPoint] = []
        let corners: [(CGFloat, CGFloat, CGFloat)] = [
            (rect.maxX - rx, rect.minY + ry, -.pi / 2), (rect.maxX - rx, rect.maxY - ry, 0),
            (rect.minX + rx, rect.maxY - ry, .pi / 2), (rect.minX + rx, rect.minY + ry, .pi),
        ]
        for (cx, cy, start) in corners {
            for step in 0...8 {
                let a = start + CGFloat(step) / 8 * .pi / 2
                points.append(CGPoint(x: cx + cos(a) * rx, y: cy + sin(a) * ry))
            }
        }
        subpaths = [Subpath(points: points, closed: true)]
    }

    var isEmpty: Bool { subpaths.isEmpty }

    var boundingBox: CGRect {
        let all = subpaths.flatMap(\.points)
        guard let first = all.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in all {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func ellipse(in rect: CGRect, segments: Int) -> [CGPoint] {
        (0..<segments).map { i in
            let a = CGFloat(i) / CGFloat(segments) * 2 * .pi
            return CGPoint(x: rect.midX + cos(a) * rect.width / 2, y: rect.midY + sin(a) * rect.height / 2)
        }
    }
}

public final class CGMutablePath: CGPath {
    public override init() { super.init() }

    public func move(to point: CGPoint) {
        subpaths.append(Subpath(points: [point], closed: false))
    }

    public func addLine(to point: CGPoint) {
        if subpaths.isEmpty { subpaths.append(Subpath(points: [.zero], closed: false)) }
        subpaths[subpaths.count - 1].points.append(point)
    }

    public func addPath(_ path: CGPath) {
        subpaths.append(contentsOf: path.subpaths)
    }

    func addEllipse(in rect: CGRect, segments: Int) {
        subpaths.append(Subpath(points: CGPath.ellipse(in: rect, segments: segments), closed: true))
    }
}

/// Straight-alpha RGBA8 pixels, rows top to bottom.
public final class CGImage {
    public let width: Int
    public let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// A bitmap context with antialiased (4× vertically supersampled, exact horizontal coverage) filling.
public final class CGContext {
    let width: Int
    let height: Int
    let scale: CGFloat
    /// Premultiplied RGBA, rows bottom to top.
    private let buffer: UnsafeMutablePointer<Float>
    private var fillColor = CGColor(gray: 0, alpha: 1)
    private var strokeColor = CGColor(gray: 0, alpha: 1)
    private var lineWidth: CGFloat = 1
    private var path = CGMutablePath()
    /// Per-row coverage: partial pixels in `cover`, runs of whole pixels as start/stop steps in `runs`.
    private let cover: UnsafeMutablePointer<Float>
    private let runs: UnsafeMutablePointer<Float>
    /// Offset (in points) added to everything drawn.
    var translation = CGPoint.zero

    /// A context for drawing in points at `scale` pixels per point.
    public init(size: CGSize, scale: CGFloat) {
        self.scale = scale
        width = max(1, Int((size.width * scale).rounded(.up)))
        height = max(1, Int((size.height * scale).rounded(.up)))
        buffer = .allocate(capacity: width * height * 4)
        buffer.initialize(repeating: 0, count: width * height * 4)
        cover = .allocate(capacity: width + 2)
        cover.initialize(repeating: 0, count: width + 2)
        runs = .allocate(capacity: width + 2)
        runs.initialize(repeating: 0, count: width + 2)
    }

    deinit {
        buffer.deallocate()
        cover.deallocate()
        runs.deallocate()
    }

    public convenience init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int,
                             space: CGColorSpace, bitmapInfo: UInt32) {
        self.init(size: CGSize(width: width, height: height), scale: 1)
    }

    public func setFillColor(_ color: CGColor) { fillColor = color }
    public func setStrokeColor(_ color: CGColor) { strokeColor = color }
    public func setLineWidth(_ width: CGFloat) { lineWidth = width }

    /// Axis-aligned, so coverage is exact: the pixel's overlap with the rectangle.
    public func fill(_ rect: CGRect) {
        let x0 = Double((rect.minX + translation.x) * scale), x1 = Double((rect.maxX + translation.x) * scale)
        let y0 = Double((rect.minY + translation.y) * scale), y1 = Double((rect.maxY + translation.y) * scale)
        let col0 = max(0, Int(x0.rounded(.down))), col1 = min(width, Int(x1.rounded(.up)))
        let row0 = max(0, Int(y0.rounded(.down))), row1 = min(height, Int(y1.rounded(.up)))
        guard col0 < col1, row0 < row1 else { return }
        for row in row0..<row1 {
            let dy = min(y1, Double(row + 1)) - max(y0, Double(row))
            for col in col0..<col1 {
                let dx = min(x1, Double(col + 1)) - max(x0, Double(col))
                blend(x: col, y: row, color: fillColor, coverage: Float(dx * dy))
            }
        }
    }

    public func stroke(_ rect: CGRect) {
        strokeSubpaths([CGPath.Subpath(points: corners(of: rect), closed: true)])
    }

    public func fillEllipse(in rect: CGRect) {
        fillPolygons([CGPath.ellipse(in: rect, segments: segments(for: rect))], color: fillColor)
    }

    public func strokeEllipse(in rect: CGRect) {
        let half = lineWidth / 2
        let outer = rect.insetBy(dx: -half, dy: -half)
        var polygons = [CGPath.ellipse(in: outer, segments: segments(for: outer))]
        let inner = rect.insetBy(dx: half, dy: half)
        if inner.width > 0 && inner.height > 0 {
            polygons.append(CGPath.ellipse(in: inner, segments: segments(for: inner)).reversed())
        }
        fillPolygons(polygons, color: strokeColor)
    }

    public func addPath(_ path: CGPath) { self.path.addPath(path) }
    public func move(to point: CGPoint) { path.move(to: point) }
    public func addLine(to point: CGPoint) { path.addLine(to: point) }

    public func fillPath() {
        fillPolygons(path.subpaths.map(\.points), color: fillColor)
        path = CGMutablePath()
    }

    public func strokePath() {
        strokeSubpaths(path.subpaths)
        path = CGMutablePath()
    }

    /// Fills the disc of `endRadius` with the gradient (no extension past either end).
    public func drawRadialGradient(_ gradient: CGGradient, startCenter: CGPoint, startRadius: CGFloat,
                                   endCenter: CGPoint, endRadius: CGFloat, options: [Int]) {
        let cx = (endCenter.x + translation.x) * scale, cy = (endCenter.y + translation.y) * scale, r = endRadius * scale
        guard r > 0 else { return }
        let x0 = max(0, Int(cx - r)), x1 = min(width - 1, Int(cx + r))
        let y0 = max(0, Int(cy - r)), y1 = min(height - 1, Int(cy + r))
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let d = hypot(CGFloat(x) + 0.5 - cx, CGFloat(y) + 0.5 - cy) / r
                guard d <= 1 else { continue }
                blend(x: x, y: y, color: gradient.color(at: d), coverage: 1)
            }
        }
    }

    public func makeImage() -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let (width, height, buffer) = (self.width, self.height, self.buffer)
        do {
            pixels.withUnsafeMutableBufferPointer { pixels in
                for y in 0..<height {
                    let src = (height - 1 - y) * width * 4
                    let dst = y * width * 4
                    for x in 0..<width {
                        let i = src + x * 4
                        let a = buffer[i + 3]
                        guard a > 0 else { continue }
                        let o = dst + x * 4
                        let k = 255 / a
                        for c in 0..<3 { pixels[o + c] = UInt8(max(0, min(255, buffer[i + c] * k + 0.5))) }
                        pixels[o + 3] = UInt8(max(0, min(255, a * 255 + 0.5)))
                    }
                }
            }
        }
        return CGImage(width: width, height: height, pixels: pixels)
    }

    // MARK: Rasterizing

    private func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    private func segments(for rect: CGRect) -> Int {
        let perimeter = .pi * (rect.width + rect.height) / 2 * scale
        return max(16, min(256, Int(perimeter / 1.5)))
    }

    /// Strokes each segment as a square-capped quad, so corners come out mitred.
    private func strokeSubpaths(_ subpaths: [CGPath.Subpath]) {
        let half = lineWidth / 2
        var quads: [[CGPoint]] = []
        for subpath in subpaths {
            var points = subpath.points
            if subpath.closed, let first = points.first { points.append(first) }
            for (a, b) in zip(points, points.dropFirst()) {
                let length = hypot(b.x - a.x, b.y - a.y)
                guard length > 0 else { continue }
                let ux = (b.x - a.x) / length * half, uy = (b.y - a.y) / length * half
                // Counter-clockwise, so overlapping quads merge under the non-zero rule.
                quads.append([CGPoint(x: a.x - ux + uy, y: a.y - uy - ux), CGPoint(x: b.x + ux + uy, y: b.y + uy - ux),
                              CGPoint(x: b.x + ux - uy, y: b.y + uy + ux), CGPoint(x: a.x - ux - uy, y: a.y - uy + ux)])
            }
        }
        fillPolygons(quads, color: strokeColor)
    }

    private struct Edge {
        var x0, y0, x1, y1: Double
        var winding: Int
    }

    /// Fills closed polygons (in points) with the non-zero winding rule.
    private func fillPolygons(_ polygons: [[CGPoint]], color: CGColor) {
        var edges: [Edge] = []
        var minY = Double.infinity, maxY = -Double.infinity, minX = Double.infinity, maxX = -Double.infinity
        for polygon in polygons where polygon.count >= 3 {
            for i in polygon.indices {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                let tx = translation.x, ty = translation.y
                let ax = Double((a.x + tx) * scale), ay = Double((a.y + ty) * scale)
                let bx = Double((b.x + tx) * scale), by = Double((b.y + ty) * scale)
                minX = min(minX, ax); maxX = max(maxX, ax); minY = min(minY, ay); maxY = max(maxY, ay)
                guard ay != by else { continue }
                edges.append(ay < by ? Edge(x0: ax, y0: ay, x1: bx, y1: by, winding: 1)
                                     : Edge(x0: bx, y0: by, x1: ax, y1: ay, winding: -1))
            }
        }
        guard !edges.isEmpty else { return }
        let rowStart = max(0, Int(minY.rounded(.down))), rowEnd = min(height, Int(maxY.rounded(.up)))
        let colStart = max(0, Int(minX.rounded(.down))), colEnd = min(width, Int(maxX.rounded(.up)) + 1)
        guard rowStart < rowEnd, colStart < colEnd else { return }
        let samples = 4
        var crossings: [(x: Double, winding: Int)] = []
        let red = Float(color.red), green = Float(color.green), blue = Float(color.blue), alpha = Float(color.alpha)
        for row in rowStart..<rowEnd {
            for x in colStart...colEnd {
                cover[x] = 0
                runs[x] = 0
            }
            for s in 0..<samples {
                let sy = Double(row) + (Double(s) + 0.5) / Double(samples)
                crossings.removeAll(keepingCapacity: true)
                for e in edges where e.y0 <= sy && sy < e.y1 {
                    crossings.append((e.x0 + (sy - e.y0) * (e.x1 - e.x0) / (e.y1 - e.y0), e.winding))
                }
                crossings.sort { $0.x < $1.x }
                var winding = 0
                var spanStart = 0.0
                for c in crossings {
                    let was = winding
                    winding += c.winding
                    if was == 0 && winding != 0 { spanStart = c.x }
                    if was != 0 && winding == 0 { addSpan(spanStart, c.x, weight: 1 / Float(samples)) }
                }
            }
            // Composite the row.
            let base = row * width * 4
            let (buffer, cover, runs) = (self.buffer, self.cover, self.runs)
            do {
                var run: Float = 0
                for x in colStart..<colEnd {
                    run += runs[x]
                    let a = alpha * min(1, cover[x] + run)
                    guard a > 0.0005 else { continue }
                    let i = base + x * 4
                    if a >= 0.9995 {
                        buffer[i] = red; buffer[i + 1] = green; buffer[i + 2] = blue; buffer[i + 3] = 1
                    } else {
                        let keep = 1 - a
                        buffer[i] = red * a + buffer[i] * keep
                        buffer[i + 1] = green * a + buffer[i + 1] * keep
                        buffer[i + 2] = blue * a + buffer[i + 2] * keep
                        buffer[i + 3] = a + buffer[i + 3] * keep
                    }
                }
            }
        }
    }

    private func addSpan(_ start: Double, _ end: Double, weight: Float) {
        let a = max(0, start), b = min(Double(width), end)
        guard a < b else { return }
        let first = Int(a), last = Int(b)
        if first == last {
            cover[first] += Float(b - a) * weight
            return
        }
        cover[first] += Float(Double(first + 1) - a) * weight
        runs[first + 1] += weight
        runs[last] -= weight
        cover[last] += Float(b - Double(last)) * weight
    }

    private func blend(x: Int, y: Int, color: CGColor, coverage: Float) {
        let a = Float(color.alpha) * coverage
        guard a > 0 else { return }
        let i = (y * width + x) * 4
        let keep = 1 - a
        buffer[i] = Float(color.red) * a + buffer[i] * keep
        buffer[i + 1] = Float(color.green) * a + buffer[i + 1] * keep
        buffer[i + 2] = Float(color.blue) * a + buffer[i + 2] * keep
        buffer[i + 3] = a + buffer[i + 3] * keep
    }
}
#endif
