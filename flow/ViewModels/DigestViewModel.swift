import Foundation
import GRDB

@Observable
final class DigestViewModel {
    var selectedSource: DigestSource = .yt
    var selectedDate: Date = .now
    var selectedItem: DigestItem?
    var items: [DigestItem] = []
    var datesWithContent: Set<String> = []
    var errorMessage: String?

    private let db: DatabaseService
    private var itemsCancellable: AnyDatabaseCancellable?
    private var datesCancellable: AnyDatabaseCancellable?

    init(db: DatabaseService) {
        self.db = db
        startObserving()
    }

    var selectedDateString: String {
        DatabaseService.dateFormatter.string(from: selectedDate)
    }

    // MARK: - Observation

    func startObserving() {
        observeItems()
        observeDates()
    }

    private func observeItems() {
        itemsCancellable?.cancel()
        let observation = db.observeItems(source: selectedSource, date: selectedDateString)
        itemsCancellable = observation.start(in: db.dbPool, onError: { [weak self] (error: any Error) in
            self?.errorMessage = error.localizedDescription
        }, onChange: { [weak self] (items: [DigestItem]) in
            self?.items = items
            // Keep selectedItem in sync with updated data
            if let selectedId = self?.selectedItem?.id {
                self?.selectedItem = items.first { $0.id == selectedId }
            }
        })
    }

    private func observeDates() {
        datesCancellable?.cancel()
        let observation = db.observeDatesWithContent(source: selectedSource)
        datesCancellable = observation.start(in: db.dbPool, onError: { [weak self] (error: any Error) in
            self?.errorMessage = error.localizedDescription
        }, onChange: { [weak self] (dates: Set<String>) in
            self?.datesWithContent = dates
        })
    }

    func sourceChanged() {
        selectedItem = nil
        observeItems()
        observeDates()
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        selectedItem = nil
        observeItems()
    }

    // MARK: - User Actions

    func selectItem(_ item: DigestItem) {
        selectedItem = item
        guard let id = item.id, !item.isRead else { return }
        try? db.markRead(itemId: id)
    }

    func toggleBookmark() {
        guard let item = selectedItem, let id = item.id else { return }
        try? db.toggleBookmark(itemId: id)
    }

    func deleteCurrentDate() {
        try? db.deleteItems(forDate: selectedDateString)
        selectedItem = nil
    }

    func dateHasContent(_ date: Date) -> Bool {
        datesWithContent.contains(DatabaseService.dateFormatter.string(from: date))
    }
}
