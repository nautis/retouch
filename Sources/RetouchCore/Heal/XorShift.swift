import Foundation

/// Small, fast pseudo-random generator for PatchMatch's random search (deterministic per heal).
struct XorShift {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    /// Uniform integer in 0..<n.
    @inline(__always) mutating func next(_ n: Int) -> Int {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Int(state % UInt64(n))
    }
}
