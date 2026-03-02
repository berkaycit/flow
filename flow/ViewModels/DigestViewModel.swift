import Foundation
import GRDB

@Observable
final class DigestViewModel {
    var selectedSource: DigestSource = .yt
    var selectedDate: Date = .now
    var selectedItem: DigestItem?
    var items: [DigestItem] = []
    private(set) var itemsById: [Int64: DigestItem] = [:]
    var datesWithContent: Set<String> = []
    var errorMessage: String?
    var showingNotebooks: Bool = false

    private let db: DatabaseService
    private var itemsCancellable: AnyDatabaseCancellable?
    private var datesCancellable: AnyDatabaseCancellable?
    private var notebooksCancellable: AnyDatabaseCancellable?

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
            self?.applyItems(items)
        })
    }

    private func applyItems(_ items: [DigestItem]) {
        self.items = items
        var byId: [Int64: DigestItem] = Dictionary(minimumCapacity: items.count)
        for item in items {
            if let id = item.id { byId[id] = item }
        }
        self.itemsById = byId
        if let selectedId = self.selectedItem?.id {
            self.selectedItem = byId[selectedId]
        }
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
        exitNotebookMode()
        selectedItem = nil
        observeItems()
        observeDates()
    }

    func selectDate(_ date: Date) {
        exitNotebookMode()
        selectedDate = date
        selectedItem = nil
        observeItems()
    }

    func toggleNotebooks() {
        showingNotebooks.toggle()
        selectedItem = nil
        if showingNotebooks {
            itemsCancellable?.cancel()
            itemsCancellable = nil
            let observation = db.observeNotebookItems()
            notebooksCancellable = observation.start(in: db.dbPool, onError: { [weak self] (error: any Error) in
                self?.errorMessage = error.localizedDescription
            }, onChange: { [weak self] (items: [DigestItem]) in
                self?.applyItems(items)
            })
        } else {
            exitNotebookMode()
            observeItems()
        }
    }

    private func exitNotebookMode() {
        showingNotebooks = false
        notebooksCancellable?.cancel()
        notebooksCancellable = nil
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
        try? db.deleteData(forDate: selectedDateString)
        selectedItem = nil
    }


}
