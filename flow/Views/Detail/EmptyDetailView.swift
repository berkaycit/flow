import SwiftUI

struct EmptyDetailView: View {
    var body: some View {
        ContentUnavailableView(
            "Seçim Yok",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Detaylarını görmek için bir öğe seçin.")
        )
    }
}
