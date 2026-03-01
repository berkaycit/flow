import SwiftUI

enum Priority: String, CaseIterable, Identifiable, Sendable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high: "Yüksek"
        case .medium: "Orta"
        case .low: "Düşük"
        }
    }

    var color: Color {
        switch self {
        case .high: .red
        case .medium: .yellow
        case .low: .green
        }
    }

    var sortOrder: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }
}
