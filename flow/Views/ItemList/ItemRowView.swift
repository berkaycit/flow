import SwiftUI

struct ItemRowView: View {
    let item: DigestItem

    var body: some View {
        HStack(spacing: 0) {
            PriorityBadge(priority: item.priorityLevel)
                .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: item.isRead ? .regular : .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Image(systemName: item.digestSource.iconName)
                        .font(.system(size: 10))
                        .foregroundStyle(sourceColor)

                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    if item.isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }
            }

            Spacer(minLength: 8)

            if !item.isRead {
                Circle()
                    .fill(.blue.opacity(0.7))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 4)
    }

    private var sourceColor: Color {
        switch item.digestSource {
        case .yt: .red.opacity(0.7)
        case .hn: .orange.opacity(0.7)
        }
    }
}
