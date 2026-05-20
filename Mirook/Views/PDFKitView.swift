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
        pdfView.onEscapePressed = { [weak coordinator = context.coordinator] in
            Task { @MainActor in
                coordinator?.closeTranslationPopover()
            }
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
        Task { @MainActor in
            coordinator.closeTranslationPopover()
        }
    }

    final class Coordinator: NSObject, PDFViewDelegate {
        @Binding private var currentPageIndex: Int
        var translatedTextPagesByIndex: [Int: TranslatedTextPage]
        weak var pdfView: PDFView?
        private var translationPopover: NSPopover?
        private weak var highlightedPage: PDFPage?
        private var highlightAnnotation: PDFAnnotation?
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
            guard translationPopover?.isShown != true else {
                return
            }

            guard let pdfView,
                  let document = pdfView.document,
                  let page = pdfView.page(for: viewPoint, nearest: false) else {
                return
            }

            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound,
                  let translatedTextPage = translatedTextPagesByIndex[pageIndex],
                  !translatedTextPage.paragraphBlocks.isEmpty else {
                return
            }

            let pagePoint = pdfView.convert(viewPoint, to: page)
            guard let paragraphBlock = translatedTextPage.paragraphBlocks.first(where: { block in
                block.pdfBounds.cgRect.insetBy(dx: -3, dy: -3).contains(pagePoint)
            }) else {
                return
            }

            guard visibleParagraphID != paragraphBlock.id else {
                return
            }

            closeTranslationPopover()
            highlightParagraph(paragraphBlock, on: page)

            let popover = NSPopover()
            popover.animates = false
            popover.behavior = .applicationDefined
            popover.contentSize = NSSize(width: 360, height: 220)
            popover.contentViewController = NSHostingController(
                rootView: ParagraphTranslationPopoverView(
                    block: paragraphBlock,
                    onClose: { [weak self] in
                        Task { @MainActor in
                            self?.closeTranslationPopover()
                        }
                    }
                )
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
            clearHighlight()
        }

        private func highlightParagraph(_ block: TranslatedTextParagraphBlock, on page: PDFPage) {
            clearHighlight()

            let annotationBounds = block.pdfBounds.cgRect.insetBy(dx: -2, dy: -2)
            let annotation = PDFAnnotation(
                bounds: annotationBounds,
                forType: .highlight,
                withProperties: nil
            )
            annotation.color = NSColor.systemYellow.withAlphaComponent(0.42)
            page.addAnnotation(annotation)

            highlightedPage = page
            highlightAnnotation = annotation
        }

        private func clearHighlight() {
            if let highlightedPage,
               let highlightAnnotation {
                highlightedPage.removeAnnotation(highlightAnnotation)
            }

            highlightedPage = nil
            highlightAnnotation = nil
        }
    }
}

private final class HoverPDFView: PDFView {
    var onMouseMovedInView: ((NSPoint) -> Void)?
    var onEscapePressed: (() -> Void)?
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscapePressed?()
            return
        }

        super.keyDown(with: event)
    }
}

private struct ParagraphTranslationPopoverView: View {
    let block: TranslatedTextParagraphBlock
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(MirookIconButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close translation")

                Text("ترجمه")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MirookTheme.mutedInk)

                Spacer()
            }

            RTLPopoverTextView(text: block.translatedText, onEscape: onClose)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(width: 360, height: 220)
        .background(MirookTheme.panelBackground)
        .environment(\.layoutDirection, .rightToLeft)
        .onExitCommand(perform: onClose)
    }
}

private struct RTLPopoverTextView: NSViewRepresentable {
    let text: String
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = false

        let textView = EscapeAwareTextView()
        textView.onEscape = onEscape
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = MirookFontRegistrar.vazirmatnRegular(size: 15)
        textView.alignment = .right
        textView.baseWritingDirection = .rightToLeft
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EscapeAwareTextView else {
            return
        }

        textView.onEscape = onEscape

        if textView.string != text {
            textView.string = text
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.baseWritingDirection = .rightToLeft

        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        textView.font = MirookFontRegistrar.vazirmatnRegular(size: 15)
        textView.alignment = .right
        textView.baseWritingDirection = .rightToLeft
        textView.setBaseWritingDirection(.rightToLeft, range: fullRange)
        textView.textStorage?.addAttributes(
            [
                .paragraphStyle: paragraphStyle,
                .font: MirookFontRegistrar.vazirmatnRegular(size: 15),
                .foregroundColor: NSColor.labelColor
            ],
            range: fullRange
        )
    }
}

private final class EscapeAwareTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}
