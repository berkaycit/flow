import SwiftUI

struct BookmarkButton: View {
    let isBookmarked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isBookmarked ? "star.fill" : "star")
                .foregroundStyle(isBookmarked ? .orange : .secondary)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .help(isBookmarked ? "Remove Bookmark" : "Bookmark")
    }
}
