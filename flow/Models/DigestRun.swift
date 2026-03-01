import Foundation
import GRDB

struct DigestRun: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "digest_runs"

    var id: Int64?
    var source: String
    var startedAt: String
    var finishedAt: String?
    var status: String
    var itemsAdded: Int?
    var errorMessage: String?

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case source
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case status
        case itemsAdded = "items_added"
        case errorMessage = "error_message"
    }
}
