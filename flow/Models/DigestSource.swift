import Foundation

enum DigestSource: String, CaseIterable, Identifiable, Sendable {
    case yt
    case hn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yt: "YouTube"
        case .hn: "Hacker News"
        }
    }

    var iconName: String {
        switch self {
        case .yt: "play.rectangle.fill"
        case .hn: "newspaper.fill"
        }
    }
}
