import PDFKit
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    @Binding var zoomScale: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPageIndex: $currentPageIndex)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.delegate = context.coordinator
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .textBackgroundColor
        pdfView.document = document

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
            pdfView.autoScales = true
        }

        if let targetPage = document.page(at: currentPageIndex), pdfView.currentPage !== targetPage {
            pdfView.go(to: targetPage)
        }

        if abs(pdfView.scaleFactor - zoomScale) > 0.01 {
            pdfView.scaleFactor = zoomScale
        }
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject, PDFViewDelegate {
        @Binding private var currentPageIndex: Int
        weak var pdfView: PDFView?

        init(currentPageIndex: Binding<Int>) {
            _currentPageIndex = currentPageIndex
        }

        @MainActor
        @objc func pageChanged(_ notification: Notification) {
            guard
                let pdfView = notification.object as? PDFView,
                let document = pdfView.document,
                let page = pdfView.currentPage
            else {
                return
            }

            let index = document.index(for: page)
            if index != NSNotFound, index != currentPageIndex {
                currentPageIndex = index
            }
        }
    }
}
