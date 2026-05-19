import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mirook")
                    .font(.title2.weight(.semibold))
                Text("PDF translation workspace")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                openPDF()
            } label: {
                Label("Open PDF", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)

            if documentStore.document != nil {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Document")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(documentStore.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(documentStore.pageCount) pages")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            documentStore.openPDF(from: url)
        }
    }
}
