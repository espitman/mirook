import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Rectangle()
                .fill(MirookTheme.separator)
                .frame(height: 1)

            Group {
                if let document = documentStore.document {
                    PDFKitView(
                        document: document,
                        currentPageIndex: $documentStore.currentPageIndex,
                        zoomScale: $documentStore.zoomScale,
                        translatedTextPagesByIndex: documentStore.translatedTextPagesByIndex
                    )
                } else {
                    EmptyReaderState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MirookTheme.readerBackground)
        }
        .background(MirookTheme.panelBackground)
    }

    private var pageNumberBinding: Binding<Int> {
        Binding {
            max(documentStore.currentPageNumber, 1)
        } set: { newValue in
            documentStore.goToPage(number: newValue)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(documentStore.document == nil ? "Mirook" : documentStore.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MirookTheme.ink)
                    .lineLimit(1)
                Text(documentStore.document == nil ? "Open a PDF to begin" : "\(documentStore.pageCount) pages")
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
            }
            .frame(width: 220, alignment: .leading)

            Spacer(minLength: 8)

            Button {
                documentStore.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(MirookIconButtonStyle())
            .help("Previous page")
            .disabled(documentStore.currentPageIndex == 0)

            Button {
                documentStore.goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(MirookIconButtonStyle())
            .help("Next page")
            .disabled(documentStore.currentPageIndex + 1 >= documentStore.pageCount)

            HStack(spacing: 6) {
                MirookNumberField(
                    placeholder: "Page",
                    value: pageNumberBinding,
                    range: 1...max(documentStore.pageCount, 1)
                )
                    .frame(width: 54)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(MirookTheme.controlFill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(MirookTheme.border, lineWidth: 1)
                    }

                Text("of \(max(documentStore.pageCount, 1))")
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
            }
            .disabled(documentStore.document == nil)

            Spacer(minLength: 8)

            Button {
                documentStore.isReadingMode = true
            } label: {
                Image(systemName: "book")
            }
            .buttonStyle(MirookIconButtonStyle())
            .help("Reading mode")
            .disabled(documentStore.document == nil)

            Button {
                documentStore.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(MirookIconButtonStyle())
            .help("Zoom out")
            .disabled(documentStore.document == nil)

            Button {
                documentStore.resetZoom()
            } label: {
                Text("\(Int(documentStore.zoomScale * 100))%")
                    .monospacedDigit()
                    .frame(width: 48)
            }
            .buttonStyle(MirookSecondaryButtonStyle())
            .help("Reset zoom")
            .disabled(documentStore.document == nil)

            Button {
                documentStore.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(MirookIconButtonStyle())
            .help("Zoom in")
            .disabled(documentStore.document == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MirookTheme.panelBackground)
    }
}
