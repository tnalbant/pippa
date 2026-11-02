import AppKit
import PippaCore
import SwiftUI

/// A PDF or images Pippa prepared: name, pages, size, and where to find it.
struct PreparedFilesCardView: View {
    var card: PreparedFilesCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(T("Your PDF is ready", table: "App"), systemImage: "doc.richtext")
                .font(.scaled(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(T("%lld pages · %@", table: "App", card.pageCount, ByteCountFormatter.string(fromByteCount: card.totalBytes, countStyle: .file)))
                .font(.scaled(size: 12)).foregroundStyle(Theme.ink2)
            ForEach(card.files, id: \.self) { file in
                HStack(spacing: 12) {
                    Text(verbatim: file.lastPathComponent).font(.scaled(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(T("Open", table: "App")) { NSWorkspace.shared.open(file) }
                    Button(T("Show in Finder", table: "App")) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                }
            }
        }
        .padding(12)
        .background(Theme.chatCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.chatBorder))
    }
}
