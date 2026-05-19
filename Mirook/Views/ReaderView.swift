import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore
    @State private var pageInput = "1"

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            Group {
                if let document = documentStore.document {
                    PDFKitView(
                        document: document,
                        currentPageIndex: $documentStore.currentPageIndex,
                        zoomScale: $documentStore.zoomScale
                    )
                } else {
                    EmptyReaderState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .onChange(of: documentStore.currentPageIndex) { _, newValue in
            pageInput = "\(newValue + 1)"
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                documentStore.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous page")
            .disabled(documentStore.currentPageIndex == 0)

            Button {
                documentStore.goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next page")
            .disabled(documentStore.currentPageIndex + 1 >= documentStore.pageCount)

            HStack(spacing: 6) {
                TextField("Page", text: $pageInput)
                    .frame(width: 54)
                    .multilineTextAlignment(.center)
                    .onSubmit {
                        documentStore.goToPage(number: Int(pageInput) ?? documentStore.currentPageNumber)
                    }

                Text("of \(max(documentStore.pageCount, 1))")
                    .foregroundStyle(.secondary)
            }
            .disabled(documentStore.document == nil)

            Spacer()

            Button {
                documentStore.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")
            .disabled(documentStore.document == nil)

            Button {
                documentStore.resetZoom()
            } label: {
                Text("\(Int(documentStore.zoomScale * 100))%")
                    .monospacedDigit()
                    .frame(width: 48)
            }
            .help("Reset zoom")
            .disabled(documentStore.document == nil)

            Button {
                documentStore.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
            .disabled(documentStore.document == nil)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
