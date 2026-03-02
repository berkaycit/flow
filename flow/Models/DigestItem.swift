import Foundation
import GRDB

struct DigestItem: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "digest_items"

    var id: Int64?
    var source: String
    var digestDate: String
    var externalId: String
    var title: String
    var url: String
    var priority: String
    var summary: String?
    var summaryEn: String?
    var reason: String?
    var reasonEn: String?
    var titleTr: String?
    // YT-specific
    var channelName: String?
    var channelId: String?
    var publishedAt: String?
    // HN-specific
    var points: Int?
    var numComments: Int?
    var author: String?
    var hnUrl: String?
    // User state
    var isRead: Bool
    var isBookmarked: Bool
    var notebookUrl: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case source
        case digestDate = "digest_date"
        case externalId = "external_id"
        case title
        case url
        case priority
        case summary
        case summaryEn = "summary_en"
        case reason
        case reasonEn = "reason_en"
        case titleTr = "title_tr"
        case channelName = "channel_name"
        case channelId = "channel_id"
        case publishedAt = "published_at"
        case points
        case numComments = "num_comments"
        case author
        case hnUrl = "hn_url"
        case isRead = "is_read"
        case isBookmarked = "is_bookmarked"
        case notebookUrl = "notebook_url"
        case createdAt = "created_at"
    }

    var displayTitle: String {
        titleTr ?? title
    }

    var digestSource: DigestSource {
        DigestSource(rawValue: source) ?? .yt
    }

    var priorityLevel: Priority {
        Priority(rawValue: priority) ?? .low
    }

    var itemURL: URL? {
        URL(string: url)
    }

    var discussionURL: URL? {
        guard let hnUrl else { return nil }
        return URL(string: hnUrl)
    }

    var subtitle: String {
        switch digestSource {
        case .yt:
            return channelName ?? ""
        case .hn:
            let pts = points ?? 0
            let comments = numComments ?? 0
            return "\(pts) pts · \(comments) comments"
        }
    }
}
