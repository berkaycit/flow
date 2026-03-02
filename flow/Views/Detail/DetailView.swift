import SwiftUI

struct DetailView: View {
    @Environment(DigestViewModel.self) private var viewModel
    @Environment(NotebookLMService.self) private var notebookLMService
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let item = viewModel.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(alignment: .center) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(item.priorityLevel.color.opacity(0.85))
                            .frame(width: 3, height: 16)
                        Text(item.priorityLevel.displayName + " Öncelik")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        BookmarkButton(isBookmarked: item.isBookmarked) {
                            viewModel.toggleBookmark()
                        }
                    }

                    // Title (Turkish primary, English below)
                    Text(item.displayTitle)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    if let titleTr = item.titleTr, !titleTr.isEmpty {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    // Metadata
                    metadataView(item: item)

                    Divider()

                    bilingualSection(label: "Özet", primary: item.summary, secondary: item.summaryEn)
                    bilingualSection(label: "Neden?", primary: item.reason, secondary: item.reasonEn)

                    Divider()

                    // Actions
                    HStack(spacing: 12) {
                        if let url = item.itemURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Tarayıcıda Aç", systemImage: "safari")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if let url = item.discussionURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label("HN Tartışma", systemImage: "bubble.left.and.bubble.right")
                            }
                            .buttonStyle(.bordered)
                        }

                        if let itemURL = item.itemURL {
                            notebookLMButton(url: itemURL, item: item)
                        }
                    }

                    notebookLMStatusView()
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private func notebookLMButton(url: URL, item: DigestItem) -> some View {
        Button {
            notebookLMService.openInNotebookLM(
                url: url.absoluteString,
                title: item.displayTitle,
                itemId: item.id!
            )
        } label: {
            if notebookLMService.status.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(notebookLMService.status.isSettingUp ? "Kuruluyor..." : "NotebookLM")
            } else {
                Label("NotebookLM", systemImage: "book.and.wrench.fill")
            }
        }
        .buttonStyle(.bordered)
        .disabled(notebookLMService.status.isBusy)
    }

    @ViewBuilder
    private func notebookLMStatusView() -> some View {
        switch notebookLMService.status {
        case .authRequired:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key")
                        .foregroundStyle(.orange)
                    Text("Chrome'da notebooklm.google.com adresine giris yapin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Cookie'leri Oku") {
                    notebookLMService.login()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .loggingIn:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Chrome cookie'leri okunuyor...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .error(let msg):
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func bilingualSection(label: String, primary: String?, secondary: String?) -> some View {
        if let primary, !primary.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.headline)
                Text(primary)
                    .font(.body)
                    .textSelection(.enabled)
                if let secondary, !secondary.isEmpty {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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
