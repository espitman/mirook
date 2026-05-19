import AppKit
import Foundation
import PDFKit

enum PDFExportServiceError: LocalizedError {
    case noPages
    case invalidPageImage(Int)
    case cannotCreatePDFPage(Int)
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case .noPages:
            "Build at least one translated page preview before exporting."
        case .invalidPageImage(let pageNumber):
            "Mirook could not load the translated image for page \(pageNumber)."
        case .cannotCreatePDFPage(let pageNumber):
            "Mirook could not create a PDF page for translated page \(pageNumber)."
        case .cannotWrite(let url):
            "Mirook could not save the translated PDF to \(url.lastPathComponent)."
        }
    }
}

struct PDFExportService {
    func export(pages: [TranslatedRenderedPage], to url: URL) throws {
        guard !pages.isEmpty else {
            throw PDFExportServiceError.noPages
        }

        let document = PDFDocument()
        let sortedPages = pages.sorted { $0.pageIndex < $1.pageIndex }

        for (index, renderedPage) in sortedPages.enumerated() {
            guard let image = NSImage(data: renderedPage.imageData) else {
                throw PDFExportServiceError.invalidPageImage(renderedPage.pageNumber)
            }

            image.size = CGSize(width: renderedPage.width, height: renderedPage.height)

            guard let pdfPage = PDFPage(image: image) else {
                throw PDFExportServiceError.cannotCreatePDFPage(renderedPage.pageNumber)
            }

            document.insert(pdfPage, at: index)
        }

        guard document.write(to: url) else {
            throw PDFExportServiceError.cannotWrite(url)
        }
    }
}
