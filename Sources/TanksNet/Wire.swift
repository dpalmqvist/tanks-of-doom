import Foundation

public enum WireError: Error, Equatable {
    case truncated
    case badValue(String)
    case trailingBytes
}

/// A world position or direction on the wire (Float is plenty for a 5120 pt map).
public struct Vec2: Equatable, Sendable {
    public var x: Float
    public var y: Float

    public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }
}

/// Appends little-endian values to a byte array.
public struct ByteWriter {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func u8(_ v: UInt8) { bytes.append(v) }
    public mutating func bool(_ v: Bool) { u8(v ? 1 : 0) }
    public mutating func u16(_ v: UInt16) { append(v) }
    public mutating func u32(_ v: UInt32) { append(v) }
    public mutating func u64(_ v: UInt64) { append(v) }
    public mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    public mutating func f32(_ v: Float) { u32(v.bitPattern) }
    public mutating func f64(_ v: Double) { u64(v.bitPattern) }

    /// UTF-8 with a 16-bit length, cut to `ByteReader.maxStringLength` bytes.
    public mutating func string(_ s: String) {
        let utf8 = Array(s.utf8.prefix(ByteReader.maxStringLength))
        u16(UInt16(utf8.count))
        bytes.append(contentsOf: utf8)
    }

    public mutating func vec(_ v: Vec2) {
        f32(v.x)
        f32(v.y)
    }

    private mutating func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }
}

/// Reads what `ByteWriter` wrote. Every read checks bounds and throws instead of trapping, because
/// the bytes come from the network.
public struct ByteReader {
    public static let maxStringLength = 256

    private let bytes: [UInt8]
    private var offset = 0

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    public var isAtEnd: Bool { offset == bytes.count }

    public mutating func u8() throws -> UInt8 { try take(1)[0] }
    public mutating func u16() throws -> UInt16 { try little() }
    public mutating func u32() throws -> UInt32 { try little() }
    public mutating func u64() throws -> UInt64 { try little() }
    public mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }

    public mutating func bool() throws -> Bool {
        switch try u8() {
        case 0: return false
        case 1: return true
        default: throw WireError.badValue("bool")
        }
    }

    public mutating func f32() throws -> Float {
        let value = Float(bitPattern: try u32())
        guard value.isFinite else { throw WireError.badValue("float") }
        return value
    }

    public mutating func f64() throws -> Double {
        let value = Double(bitPattern: try u64())
        guard value.isFinite else { throw WireError.badValue("float") }
        return value
    }

    public mutating func string() throws -> String {
        let length = Int(try u16())
        guard length <= Self.maxStringLength else { throw WireError.badValue("string length") }
        return String(decoding: try take(length), as: UTF8.self)
    }

    public mutating func vec() throws -> Vec2 {
        Vec2(try f32(), try f32())
    }

    /// An array length, capped so a hostile length can't make us allocate a huge buffer.
    public mutating func count(max: Int) throws -> Int {
        let n = Int(try u16())
        guard n <= max else { throw WireError.badValue("count") }
        return n
    }

    public mutating func raw<E: RawRepresentable>(_ type: E.Type) throws -> E where E.RawValue == UInt8 {
        guard let value = E(rawValue: try u8()) else { throw WireError.badValue("\(E.self)") }
        return value
    }

    /// Call after reading a whole message: leftovers mean the sender and receiver disagree about the format.
    public func finish() throws {
        guard isAtEnd else { throw WireError.trailingBytes }
    }

    private mutating func take(_ n: Int) throws -> [UInt8] {
        guard bytes.count - offset >= n else { throw WireError.truncated }
        defer { offset += n }
        return Array(bytes[offset..<(offset + n)])
    }

    private mutating func little<T: FixedWidthInteger>() throws -> T {
        var value: T = 0
        for (index, byte) in try take(MemoryLayout<T>.size).enumerated() {
            value |= T(byte) << (8 * index)
        }
        return value
    }
}
