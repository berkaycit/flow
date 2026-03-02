import Foundation
import GRDB

@Observable
final class DatabaseService: Sendable {
    nonisolated let dbPool: DatabasePool

    nonisolated init() throws {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Flow")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbPath = dir.appending(path: "flow.db").path(percentEncoded: false)
        dbPool = try DatabasePool(path: dbPath)

        try migrator.migrate(dbPool)
    }

    private nonisolated var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS digest_items (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    source          TEXT NOT NULL CHECK(source IN ('yt', 'hn')),
                    digest_date     TEXT NOT NULL,
                    external_id     TEXT NOT NULL,
                    title           TEXT NOT NULL,
                    url             TEXT NOT NULL,
                    priority        TEXT NOT NULL,
                    summary         TEXT,
                    reason          TEXT,
                    channel_name    TEXT,
                    channel_id      TEXT,
                    published_at    TEXT,
                    points          INTEGER,
                    num_comments    INTEGER,
                    author          TEXT,
                    hn_url          TEXT,
                    is_read         INTEGER NOT NULL DEFAULT 0,
                    is_bookmarked   INTEGER NOT NULL DEFAULT 0,
                    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
                    UNIQUE(source, external_id)
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_items_source_date
                    ON digest_items(source, digest_date)
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_items_bookmarked
                    ON digest_items(is_bookmarked) WHERE is_bookmarked = 1
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS digest_runs (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    source          TEXT NOT NULL CHECK(source IN ('yt', 'hn')),
                    started_at      TEXT NOT NULL DEFAULT (datetime('now')),
                    finished_at     TEXT,
                    status          TEXT NOT NULL DEFAULT 'running',
                    items_added     INTEGER DEFAULT 0,
                    error_message   TEXT
                )
            """)
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: "ALTER TABLE digest_items ADD COLUMN title_tr TEXT")
            try db.execute(sql: "ALTER TABLE digest_items ADD COLUMN summary_en TEXT")
            try db.execute(sql: "ALTER TABLE digest_items ADD COLUMN reason_en TEXT")
        }
        migrator.registerMigration("v3") { db in
            try db.execute(sql: "ALTER TABLE digest_items ADD COLUMN notebook_url TEXT")
        }
        return migrator
    }

    // MARK: - Shared Formatter

    nonisolated static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Queries

    nonisolated private static let priorityOrderSQL = "CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 END"

    nonisolated func items(source: DigestSource, date: String) throws -> [DigestItem] {
        try dbPool.read { db in
            try DigestItem
                .filter(DigestItem.CodingKeys.source == source.rawValue)
                .filter(DigestItem.CodingKeys.digestDate == date)
                .order(sql: Self.priorityOrderSQL)
                .fetchAll(db)
        }
    }

    nonisolated func datesWithContent(source: DigestSource) throws -> Set<String> {
        try dbPool.read { db in
            let rows = try String.fetchAll(db, sql:
                "SELECT DISTINCT digest_date FROM digest_items WHERE source = ?",
                arguments: [source.rawValue]
            )
            return Set(rows)
        }
    }

    nonisolated func markRead(itemId: Int64) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE digest_items SET is_read = 1 WHERE id = ?",
                arguments: [itemId]
            )
        }
    }

    nonisolated func toggleBookmark(itemId: Int64) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE digest_items SET is_bookmarked = CASE WHEN is_bookmarked = 0 THEN 1 ELSE 0 END WHERE id = ?",
                arguments: [itemId]
            )
        }
    }

    nonisolated func saveNotebookURL(itemId: Int64, url: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE digest_items SET notebook_url = ? WHERE id = ?",
                arguments: [url, itemId]
            )
        }
    }

    nonisolated func fetchItem(id: Int64) throws -> DigestItem? {
        try dbPool.read { db in
            try DigestItem.fetchOne(db, key: id)
        }
    }

    nonisolated func cleanupOld(retentionDays: Int = 30) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now)!
        let cutoff = Self.dateFormatter.string(from: cutoffDate)
        try dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM digest_items WHERE digest_date < ? AND is_bookmarked = 0",
                arguments: [cutoff]
            )
            try db.execute(
                sql: "DELETE FROM digest_runs WHERE started_at < ?",
                arguments: [cutoff]
            )
        }
    }

    nonisolated func deleteData(forDate date: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM digest_items WHERE digest_date = ?",
                arguments: [date]
            )
            try db.execute(
                sql: "DELETE FROM digest_runs WHERE date(started_at) = ?",
                arguments: [date]
            )
        }
    }

    // MARK: - ValueObservation

    nonisolated func observeItems(
        source: DigestSource,
        date: String
    ) -> ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<[DigestItem]>>> {
        ValueObservation.tracking { db in
            try DigestItem
                .filter(DigestItem.CodingKeys.source == source.rawValue)
                .filter(DigestItem.CodingKeys.digestDate == date)
                .order(sql: Self.priorityOrderSQL)
                .fetchAll(db)
        }
        .removeDuplicates()
    }

    nonisolated func observeDatesWithContent(
        source: DigestSource
    ) -> ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<Set<String>>>> {
        ValueObservation.tracking { db in
            let rows = try String.fetchAll(db, sql:
                "SELECT DISTINCT digest_date FROM digest_items WHERE source = ?",
                arguments: [source.rawValue]
            )
            return Set(rows)
        }
        .removeDuplicates()
    }
}
