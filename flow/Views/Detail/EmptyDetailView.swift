import SwiftUI

struct EmptyDetailView: View {
    var body: some View {
        ContentUnavailableView(
            "No Selection",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Select an item to see its details.")
        )
    }
}
