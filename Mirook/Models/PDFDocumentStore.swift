import Foundation
import PDFKit

@MainActor
final class PDFDocumentStore: ObservableObject {
    @Published private(set) var document: PDFDocument?
    @Published private(set) var documentURL: URL?
    @Published var currentPageIndex: Int = 0
    @Published var zoomScale: CGFloat = 1.0
    @Published var pageSelection: PDFPageSelection = .firstPage
    @Published var lastErrorMessage: String?

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    var displayName: String {
        documentURL?.deletingPathExtension().lastPathComponent ?? "Untitled PDF"
    }

    var currentPageNumber: Int {
        guard pageCount > 0 else { return 0 }
        return currentPageIndex + 1
    }

    func openPDF(from url: URL) {
        guard let loadedDocument = PDFDocument(url: url) else {
            lastErrorMessage = "The selected file could not be opened as a PDF."
            return
        }

        document = loadedDocument
        documentURL = url
        currentPageIndex = 0
        zoomScale = 1.0
        pageSelection = .firstPage
        lastErrorMessage = nil
    }

    func goToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
        pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
    }

    func goToNextPage() {
        guard currentPageIndex + 1 < pageCount else { return }
        currentPageIndex += 1
        pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
    }

    func goToPage(number: Int) {
        guard pageCount > 0 else { return }
        currentPageIndex = min(max(number - 1, 0), pageCount - 1)
        pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
    }

    func zoomIn() {
        zoomScale = min(zoomScale + 0.15, 4.0)
    }

    func zoomOut() {
        zoomScale = max(zoomScale - 0.15, 0.35)
    }

    func resetZoom() {
        zoomScale = 1.0
    }
}
