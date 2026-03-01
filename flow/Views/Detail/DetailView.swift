import SwiftUI

struct DetailView: View {
    @Environment(DigestViewModel.self) private var viewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let item = viewModel.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(alignment: .top) {
                        PriorityBadge(priority: item.priorityLevel)
                        Text(item.priorityLevel.displayName + " Priority")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        BookmarkButton(isBookmarked: item.isBookmarked) {
                            viewModel.toggleBookmark()
                        }
                    }

                    // Title
                    Text(item.title)
                        .font(.title2.bold())
                        .textSelection(.enabled)

                    // Metadata
                    metadataView(item: item)

                    Divider()

                    // Summary
                    if let summary = item.summary, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary")
                                .font(.headline)
                            Text(summary)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    // Reason
                    if let reason = item.reason, !reason.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Why")
                                .font(.headline)
                            Text(reason)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    Divider()

                    // Actions
                    HStack(spacing: 12) {
                        if let url = item.itemURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open in Browser", systemImage: "safari")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if let url = item.discussionURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label("HN Discussion", systemImage: "bubble.left.and.bubble.right")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private func metadataView(item: DigestItem) -> some View {
        switch item.digestSource {
        case .yt:
            HStack(spacing: 8) {
                if let channel = item.channelName {
                    Label(channel, systemImage: "play.rectangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let published = item.publishedAt {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(published)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .hn:
            HStack(spacing: 8) {
                if let points = item.points {
                    Label("\(points) pts", systemImage: "arrow.up")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let comments = item.numComments {
                    Label("\(comments)", systemImage: "bubble.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let author = item.author {
                    Label(author, systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
