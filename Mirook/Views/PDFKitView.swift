import PDFKit
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    @Binding var zoomScale: CGFloat
    let translatedTextPagesByIndex: [Int: TranslatedTextPage]

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentPageIndex: $currentPageIndex,
            translatedTextPagesByIndex: translatedTextPagesByIndex
        )
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = HoverPDFView()
        pdfView.delegate = context.coordinator
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor(calibratedRed: 0.94, green: 0.92, blue: 0.88, alpha: 1)
        pdfView.document = document
        pdfView.onMouseMovedInView = { [weak coordinator = context.coordinator] point in
            coordinator?.showTranslationIfNeeded(at: point)
        }

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

        context.coordinator.translatedTextPagesByIndex = translatedTextPagesByIndex
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.closeTranslationPopover()
    }

    final class Coordinator: NSObject, PDFViewDelegate {
        @Binding private var currentPageIndex: Int
        var translatedTextPagesByIndex: [Int: TranslatedTextPage]
        weak var pdfView: PDFView?
        private var translationPopover: NSPopover?
        private var visibleParagraphID: String?

        init(
            currentPageIndex: Binding<Int>,
            translatedTextPagesByIndex: [Int: TranslatedTextPage]
        ) {
            _currentPageIndex = currentPageIndex
            self.translatedTextPagesByIndex = translatedTextPagesByIndex
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

        @MainActor
        func showTranslationIfNeeded(at viewPoint: NSPoint) {
            guard let pdfView,
                  let document = pdfView.document,
                  let page = pdfView.page(for: viewPoint, nearest: false) else {
                closeTranslationPopover()
                return
            }

            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound,
                  let translatedTextPage = translatedTextPagesByIndex[pageIndex],
                  !translatedTextPage.paragraphBlocks.isEmpty else {
                closeTranslationPopover()
                return
            }

            let pagePoint = pdfView.convert(viewPoint, to: page)
            guard let paragraphBlock = translatedTextPage.paragraphBlocks.first(where: { block in
                block.pdfBounds.cgRect.insetBy(dx: -3, dy: -3).contains(pagePoint)
            }) else {
                closeTranslationPopover()
                return
            }

            guard visibleParagraphID != paragraphBlock.id else {
                return
            }

            closeTranslationPopover()

            let popover = NSPopover()
            popover.animates = false
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 340, height: 190)
            popover.contentViewController = NSHostingController(
                rootView: ParagraphTranslationPopoverView(block: paragraphBlock)
            )

            let sourceRectInView = pdfView.convert(paragraphBlock.pdfBounds.cgRect, from: page)
                .insetBy(dx: -2, dy: -2)
            popover.show(relativeTo: sourceRectInView, of: pdfView, preferredEdge: .maxY)
            translationPopover = popover
            visibleParagraphID = paragraphBlock.id
        }

        @MainActor
        func closeTranslationPopover() {
            translationPopover?.close()
            translationPopover = nil
            visibleParagraphID = nil
        }
    }
}

private final class HoverPDFView: PDFView {
    var onMouseMovedInView: ((NSPoint) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMovedInView?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
    }
}

private struct ParagraphTranslationPopoverView: View {
    let block: TranslatedTextParagraphBlock

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Spacer()

                Text("ترجمه")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MirookTheme.mutedInk)
            }

            ScrollView(.vertical) {
                Text(block.translatedText)
                    .font(MirookFontRegistrar.vazirmatnFont(size: 15))
                    .foregroundStyle(MirookTheme.ink)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(width: 340, height: 190)
        .background(MirookTheme.panelBackground)
        .environment(\.layoutDirection, .rightToLeft)
    }
}
