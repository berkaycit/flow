import SwiftUI

struct ItemListView: View {
    @Environment(DigestViewModel.self) private var viewModel

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "tray",
                    description: Text("No digest items for this date.\nRun the digest scripts to fetch new content.")
                )
            } else {
                List(viewModel.items, selection: Binding(
                    get: { viewModel.selectedItem?.id },
                    set: { id in
                        if let id, let item = viewModel.items.first(where: { $0.id == id }) {
                            viewModel.selectItem(item)
                        }
                    }
                )) { item in
                    ItemRowView(item: item)
                        .tag(item.id)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(navigationTitle)
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private var navigationTitle: String {
        Self.titleFormatter.string(from: viewModel.selectedDate)
    }
}
