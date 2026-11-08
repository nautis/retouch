import Foundation

/// One scale of the image pyramid used during healing.
struct PyramidLevel {
    var img: [Float]
    var hole: [Bool]
    let w: Int
    let h: Int
}
