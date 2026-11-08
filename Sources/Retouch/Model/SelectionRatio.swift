import Foundation

/// Fixed aspect ratios for the rectangle selection (width : height).
enum SelectionRatio: String, CaseIterable, Identifiable {
    case free, square, threeTwo, twoThree, fourThree, threeFour, fourFive, sixteenNine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Free"
        case .square: "1 : 1"
        case .threeTwo: "3 : 2"
        case .twoThree: "2 : 3"
        case .fourThree: "4 : 3"
        case .threeFour: "3 : 4"
        case .fourFive: "4 : 5"
        case .sixteenNine: "16 : 9"
        }
    }

    /// width / height, or nil for free.
    var value: Double? {
        switch self {
        case .free: nil
        case .square: 1
        case .threeTwo: 3.0 / 2
        case .twoThree: 2.0 / 3
        case .fourThree: 4.0 / 3
        case .threeFour: 3.0 / 4
        case .fourFive: 4.0 / 5
        case .sixteenNine: 16.0 / 9
        }
    }
}
