import SwiftUI

struct ItemRowView: View {
    let item: DigestItem

    var body: some View {
        HStack(spacing: 8) {
            PriorityBadge(priority: item.priorityLevel)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if !item.isRead {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                    }
                    Text(item.title)
                        .font(.system(size: 13, weight: item.isRead ? .regular : .semibold))
                        .lineLimit(2)
                }

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if item.isBookmarked {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}
