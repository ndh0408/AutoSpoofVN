import Foundation

/// Random number generator có thể tái tạo — quan trọng cho QA.
/// Khi seed != nil, mọi giá trị random trong simulation ra giống nhau mỗi lần chạy.
struct DeterministicRandom {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    /// xoshiro64* — fast, reproducible
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return z
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
    }

    mutating func nextInt(in range: Range<Int>) -> Int {
        let span = UInt64(range.count)
        guard span > 0 else { return range.lowerBound }
        return range.lowerBound + Int(next() % span)
    }
}

/// Configuration cho deterministic simulation.
struct SimulationSeedConfig: Codable {
    var seed: UInt64?
    var isDeterministic: Bool { seed != nil }

    static let random = SimulationSeedConfig(seed: nil)
    static func fixed(_ seed: UInt64) -> SimulationSeedConfig { SimulationSeedConfig(seed: seed) }
}
