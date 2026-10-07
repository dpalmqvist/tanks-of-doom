import Foundation

/// A tile coordinate. Row 0 is the bottom of the map.
public struct GridPoint: Hashable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public var description: String { "(\(x),\(y))" }

    public func distance(to other: GridPoint) -> Double {
        let dx = Double(x - other.x)
        let dy = Double(y - other.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Deterministic SplitMix64 generator so a seed always produces the same city.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    public mutating func double() -> Double {
        Double.random(in: 0..<1, using: &self)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        double() < probability
    }
}
