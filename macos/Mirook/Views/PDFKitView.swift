import PDFKit
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    @Binding var zoomScale: CGFloat
    let translatedTextPagesByIndex: [Int: TranslatedTextPage]
    var allowsTranslationPopover = true
    var resetsScrollOnPageChange = false
    var onFileDropped: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentPageIndex: $currentPageIndex,
            translatedTextPagesByIndex: translatedTextPagesByIndex
        )
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = InteractivePDFView()
        pdfView.delegate = context.coordinator
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor(calibratedRed: 0.94, green: 0.92, blue: 0.88, alpha: 1)
        pdfView.document = document
        pdfView.onMouseClickedInView = { [weak coordinator = context.coordinator] point in
            guard coordinator?.allowsTranslationPopover == true else { return }
            coordinator?.openTranslation(at: point)
        }
        pdfView.onMouseMovedInView = { [weak coordinator = context.coordinator] point in
            guard coordinator?.allowsTranslationPopover == true else { return false }
            return coordinator?.hasTranslation(at: point) ?? false
        }
        pdfView.onEscapePressed = { [weak coordinator = context.coordinator] in
            Task { @MainActor in
                coordinator?.closeTranslationPopover()
            }
        }
        pdfView.onFileDropped = onFileDropped

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
            if resetsScrollOnPageChange {
                let bounds = targetPage.bounds(for: pdfView.displayBox)
                let destination = PDFDestination(
                    page: targetPage,
                    at: NSPoint(x: bounds.minX, y: bounds.maxY)
                )
                pdfView.go(to: destination)
            } else {
                pdfView.go(to: targetPage)
            }
        }

        if abs(pdfView.scaleFactor - zoomScale) > 0.01 {
            pdfView.scaleFactor = zoomScale
        }

        context.coordinator.translatedTextPagesByIndex = translatedTextPagesByIndex
        context.coordinator.allowsTranslationPopover = allowsTranslationPopover
        if let interactivePDFView = pdfView as? InteractivePDFView {
            interactivePDFView.onFileDropped = onFileDropped
        }
        if !allowsTranslationPopover {
            context.coordinator.closeTranslationPopover()
        }
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
        var allowsTranslationPopover = true
        weak var pdfView: PDFView?
        private var translationPopover: NSPopover?
        private weak var highlightedPage: PDFPage?
        private var highlightAnnotation: PDFAnnotation?
        private var visibleParagraphID: String?
        private var visibleParagraphPosition: ParagraphPosition?
        private var pendingParagraphPosition: ParagraphPosition?

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
        func openTranslation(at viewPoint: NSPoint) {
            guard let hit = translatedParagraphHit(at: viewPoint) else {
                closeTranslationPopover()
                return
            }

            guard visibleParagraphID != hit.block.id else {
                return
            }

            guard let position = position(for: hit.block, pageIndex: hit.pageIndex) else {
                return
            }

            showTranslationPopover(at: position, animatedScroll: false)
        }

        @MainActor
        func hasTranslation(at viewPoint: NSPoint) -> Bool {
            translatedParagraphHit(at: viewPoint) != nil
        }

        @MainActor
        func closeTranslationPopover() {
            translationPopover?.close()
            translationPopover = nil
            visibleParagraphID = nil
            visibleParagraphPosition = nil
            pendingParagraphPosition = nil
            clearHighlight()
        }

        @MainActor
        private func showAdjacentTranslation(offset: Int) {
            guard let visibleParagraphPosition,
                  let adjacentPosition = adjacentPosition(from: visibleParagraphPosition, offset: offset) else {
                return
            }

            showTranslationPopover(at: adjacentPosition, animatedScroll: true)
        }

        @MainActor
        private func showTranslationPopover(
            at position: ParagraphPosition,
            animatedScroll: Bool
        ) {
            guard let pdfView,
                  let document = pdfView.document,
                  let page = document.page(at: position.pageIndex),
                  let block = block(at: position) else {
                closeTranslationPopover()
                return
            }

            closeTranslationPopover()
            pendingParagraphPosition = position
            if pdfView.currentPage !== page {
                pdfView.go(to: page)
                currentPageIndex = position.pageIndex
                pdfView.layoutSubtreeIfNeeded()
            }
            highlightParagraph(block, on: page)

            if animatedScroll {
                scrollToParagraph(block, on: page, in: pdfView)

                Task { @MainActor [weak self, weak pdfView, weak page] in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard let self,
                          let pdfView,
                          let page,
                          self.pendingParagraphPosition == position else {
                        return
                    }

                    self.presentTranslationPopover(
                        block: block,
                        position: position,
                        page: page,
                        pdfView: pdfView
                    )
                }
                return
            }

            presentTranslationPopover(
                block: block,
                position: position,
                page: page,
                pdfView: pdfView
            )
        }

        @MainActor
        private func presentTranslationPopover(
            block: TranslatedTextParagraphBlock,
            position: ParagraphPosition,
            page: PDFPage,
            pdfView: PDFView
        ) {
            guard pendingParagraphPosition == position else {
                return
            }

            let popover = NSPopover()
            popover.animates = false
            popover.behavior = .applicationDefined
            let popoverSize = popoverContentSize(for: page, in: pdfView)
            popover.contentSize = popoverSize
            popover.contentViewController = NSHostingController(
                rootView: ParagraphTranslationPopoverView(
                    block: block,
                    width: popoverSize.width,
                    height: popoverSize.height,
                    canGoPrevious: adjacentPosition(from: position, offset: -1) != nil,
                    canGoNext: adjacentPosition(from: position, offset: 1) != nil,
                    onPrevious: { [weak self] in
                        Task { @MainActor in
                            self?.showAdjacentTranslation(offset: -1)
                        }
                    },
                    onNext: { [weak self] in
                        Task { @MainActor in
                            self?.showAdjacentTranslation(offset: 1)
                        }
                    },
                    onClose: { [weak self] in
                        Task { @MainActor in
                            self?.closeTranslationPopover()
                        }
                    }
                )
            )

            let sourceRectInView = pdfView.convert(block.pdfBounds.cgRect, from: page)
                .insetBy(dx: -2, dy: -2)
            popover.show(relativeTo: sourceRectInView, of: pdfView, preferredEdge: .maxY)
            translationPopover = popover
            visibleParagraphID = block.id
            visibleParagraphPosition = position
            pendingParagraphPosition = nil
        }

        @MainActor
        private func popoverContentSize(for page: PDFPage, in pdfView: PDFView) -> NSSize {
            let pageWidthAt100 = page.bounds(for: pdfView.displayBox).width
            let availableScreenWidth = max(480, (pdfView.window?.screen?.visibleFrame.width ?? pdfView.bounds.width) - 80)
            let width = min(max(pageWidthAt100, 480), availableScreenWidth)
            return NSSize(width: width, height: 360)
        }

        @MainActor
        private func translatedParagraphHit(
            at viewPoint: NSPoint
        ) -> (pageIndex: Int, block: TranslatedTextParagraphBlock)? {
            guard let pdfView,
                  let document = pdfView.document,
                  let page = pdfView.page(for: viewPoint, nearest: false) else {
                return nil
            }

            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound,
                  let translatedTextPage = translatedTextPagesByIndex[pageIndex],
                  !translatedTextPage.paragraphBlocks.isEmpty else {
                return nil
            }

            let pagePoint = pdfView.convert(viewPoint, to: page)
            guard let paragraphBlock = translatedTextPage.paragraphBlocks.first(where: { block in
                !block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && block.pdfBounds.cgRect.insetBy(dx: -3, dy: -3).contains(pagePoint)
            }) else {
                return nil
            }

            return (pageIndex, paragraphBlock)
        }

        private func position(
            for block: TranslatedTextParagraphBlock,
            pageIndex: Int
        ) -> ParagraphPosition? {
            guard let blockIndex = translatedTextPagesByIndex[pageIndex]?.paragraphBlocks.firstIndex(where: { $0.id == block.id }) else {
                return nil
            }

            return ParagraphPosition(pageIndex: pageIndex, blockIndex: blockIndex)
        }

        private func block(at position: ParagraphPosition) -> TranslatedTextParagraphBlock? {
            guard let page = translatedTextPagesByIndex[position.pageIndex],
                  page.paragraphBlocks.indices.contains(position.blockIndex) else {
                return nil
            }

            return page.paragraphBlocks[position.blockIndex]
        }

        private func adjacentPosition(
            from position: ParagraphPosition,
            offset: Int
        ) -> ParagraphPosition? {
            let positions = paragraphPositions()
            guard let currentIndex = positions.firstIndex(of: position) else {
                return nil
            }

            let adjacentIndex = currentIndex + offset
            guard positions.indices.contains(adjacentIndex) else {
                return nil
            }

            return positions[adjacentIndex]
        }

        private func paragraphPositions() -> [ParagraphPosition] {
            translatedTextPagesByIndex.keys.sorted().flatMap { pageIndex in
                guard let page = translatedTextPagesByIndex[pageIndex] else {
                    return [ParagraphPosition]()
                }

                return page.paragraphBlocks.indices.map { blockIndex in
                    ParagraphPosition(pageIndex: pageIndex, blockIndex: blockIndex)
                }
            }
        }

        @MainActor
        private func scrollToParagraph(
            _ block: TranslatedTextParagraphBlock,
            on page: PDFPage,
            in pdfView: PDFView
        ) {
            guard let scrollView = pdfView.firstDescendant(ofType: NSScrollView.self),
                  let documentView = scrollView.documentView else {
                let destination = PDFDestination(
                    page: page,
                    at: NSPoint(
                        x: block.pdfBounds.cgRect.midX,
                        y: block.pdfBounds.cgRect.midY
                    )
                )
                pdfView.go(to: destination)
                return
            }

            let rectInPDFView = pdfView.convert(block.pdfBounds.cgRect, from: page)
            let rectInWindow = pdfView.convert(rectInPDFView, to: nil)
            let rectInDocumentView = documentView.convert(rectInWindow, from: nil)
            let visibleBounds = scrollView.contentView.bounds
            let documentBounds = documentView.bounds

            let maxX = max(documentBounds.minX, documentBounds.maxX - visibleBounds.width)
            let maxY = max(documentBounds.minY, documentBounds.maxY - visibleBounds.height)
            let targetOrigin = NSPoint(
                x: clamp(
                    rectInDocumentView.midX - visibleBounds.width * 0.5,
                    min: documentBounds.minX,
                    max: maxX
                ),
                y: clamp(
                    rectInDocumentView.midY - visibleBounds.height * 0.46,
                    min: documentBounds.minY,
                    max: maxY
                )
            )

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.allowsImplicitAnimation = true
                scrollView.contentView.animator().setBoundsOrigin(targetOrigin)
            } completionHandler: {
                Task { @MainActor [weak scrollView] in
                    guard let scrollView else {
                        return
                    }

                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }

        private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
            Swift.min(Swift.max(value, min), max)
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

private struct ParagraphPosition: Equatable {
    let pageIndex: Int
    let blockIndex: Int
}

private extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T {
                return match
            }

            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }

        return nil
    }
}

private final class InteractivePDFView: PDFView {
    var onMouseClickedInView: ((NSPoint) -> Void)?
    var onMouseMovedInView: ((NSPoint) -> Bool)?
    var onEscapePressed: (() -> Void)?
    var onFileDropped: ((URL) -> Void)?
    private var cursorTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(MirookDropSupport.pasteboardTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(MirookDropSupport.pasteboardTypes)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onMouseClickedInView?(convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if onMouseMovedInView?(point) == true {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscapePressed?()
            return
        }

        super.keyDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        MirookDropSupport.acceptableFileURL(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        MirookDropSupport.acceptableFileURL(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = MirookDropSupport.acceptableFileURL(from: sender.draggingPasteboard) else {
            return false
        }

        onFileDropped?(url)
        return true
    }
}

private struct ParagraphTranslationPopoverView: View {
    let block: TranslatedTextParagraphBlock
    let width: CGFloat
    let height: CGFloat
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
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

                Button {
                    onPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(MirookIconButtonStyle())
                .disabled(!canGoPrevious)
                .help("Previous translated section")

                Button {
                    onNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(MirookIconButtonStyle())
                .disabled(!canGoNext)
                .help("Next translated section")
            }

            RTLPopoverTextView(text: block.translatedText, onEscape: onClose)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(width: width, height: height)
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
