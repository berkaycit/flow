import SwiftUI

struct ItemListView: View {
    @Environment(DigestViewModel.self) private var viewModel
    @State private var showingDeleteConfirm = false

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                if viewModel.showingNotebooks {
                    ContentUnavailableView(
                        "Notebook Yok",
                        systemImage: "book.closed",
                        description: Text("Henuz notebook olusturulmamis.")
                    )
                } else {
                    ContentUnavailableView(
                        "İçerik Yok",
                        systemImage: "tray",
                        description: Text("Bu tarih için içerik bulunamadı.\nDigest scriptlerini çalıştırarak yeni içerik çekin.")
                    )
                }
            } else {
                List(viewModel.items, selection: Binding(
                    get: { viewModel.selectedItem?.id },
                    set: { id in
                        if let id, let item = viewModel.itemsById[id] {
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
        .toolbar {
            if !viewModel.showingNotebooks && !viewModel.items.isEmpty {
                ToolbarItem {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Tarihi Sil", systemImage: "trash")
                    }
                    .help("Bu tarihin tüm verilerini sil")
                }
            }
        }
        .alert("Verileri Sil", isPresented: $showingDeleteConfirm) {
            Button("Sil", role: .destructive) {
                viewModel.deleteCurrentDate()
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("\(navigationTitle) tarihindeki tüm veriler silinecek. Bu işlemi geri alamazsınız.")
        }
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private var navigationTitle: String {
        if viewModel.showingNotebooks {
            return "Notebooks"
        }
        return Self.titleFormatter.string(from: viewModel.selectedDate)
    }
}
