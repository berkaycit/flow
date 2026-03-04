import Foundation

enum DigestSource: String, CaseIterable, Identifiable, Sendable {
    case yt
    case hn
    case reddit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yt: "YouTube"
        case .hn: "Hacker News"
        case .reddit: "Reddit"
        }
    }

    var iconName: String {
        switch self {
        case .yt: "play.rectangle.fill"
        case .hn: "newspaper.fill"
        case .reddit: "bubble.left.and.text.bubble.right.fill"
        }
    }
}
