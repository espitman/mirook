import Foundation
import PDFKit

@MainActor
final class PDFDocumentStore: ObservableObject {
    @Published private(set) var document: PDFDocument?
    @Published private(set) var documentURL: URL?
    @Published var currentPageIndex: Int = 0 {
        didSet {
            guard oldValue != currentPageIndex, pageCount > 0 else { return }
            pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
            renderedPage = nil
            translatedPage = nil
            translatedRenderedPage = nil
        }
    }
    @Published var zoomScale: CGFloat = 1.0
    @Published var pageSelection: PDFPageSelection = .firstPage
    @Published private(set) var renderedPage: RenderedPage?
    @Published private(set) var isRenderingPage = false
    @Published private(set) var translatedPage: TranslatedPage?
    @Published private(set) var isTranslatingPage = false
    @Published private(set) var translatedRenderedPage: TranslatedRenderedPage?
    @Published private(set) var isRenderingTranslatedPage = false
    @Published var lastErrorMessage: String?

    private let pageRenderer = PDFPageRenderer(scale: 2.0)
    private let translatedPageRenderer = TranslatedPageRenderer()
    private let keychainService = KeychainService()

    private enum SettingsKey {
        static let openAIAPIKeyAccount = "openai-api-key"
        static let defaultTargetLanguage = "defaultTargetLanguage"
        static let defaultModelName = "defaultModelName"
        static let fallbackTargetLanguage = "Persian"
        static let fallbackModelName = "gpt-5.2"
    }

    private typealias TextLine = (text: String, rect: CGRect)

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
        renderedPage = nil
        translatedPage = nil
        translatedRenderedPage = nil
        lastErrorMessage = nil
    }

    func goToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
        pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
        renderedPage = nil
        translatedPage = nil
        translatedRenderedPage = nil
    }

    func goToNextPage() {
        guard currentPageIndex + 1 < pageCount else { return }
        currentPageIndex += 1
        pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
        renderedPage = nil
        translatedPage = nil
        translatedRenderedPage = nil
    }

    func goToPage(number: Int) {
        guard pageCount > 0 else { return }
        currentPageIndex = min(max(number - 1, 0), pageCount - 1)
        pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
        renderedPage = nil
        translatedPage = nil
        translatedRenderedPage = nil
    }

    func renderCurrentPage() {
        guard let document else {
            lastErrorMessage = "Open a PDF before rendering a page."
            return
        }

        isRenderingPage = true
        defer { isRenderingPage = false }

        do {
            renderedPage = try pageRenderer.render(document: document, pageIndex: currentPageIndex)
            translatedRenderedPage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func translateCurrentPage() async {
        guard document != nil else {
            lastErrorMessage = "Open a PDF before translating a page."
            return
        }

        isTranslatingPage = true
        defer { isTranslatingPage = false }

        do {
            if renderedPage == nil {
                renderCurrentPage()
            }

            guard let renderedPage else {
                throw PDFPageRendererError.missingPage
            }

            let apiKey = try keychainService.read(account: SettingsKey.openAIAPIKeyAccount) ?? ""
            let model = normalizedSetting(
                key: SettingsKey.defaultModelName,
                fallback: SettingsKey.fallbackModelName
            )
            let targetLanguage = normalizedSetting(
                key: SettingsKey.defaultTargetLanguage,
                fallback: SettingsKey.fallbackTargetLanguage
            )

            let client = OpenAIClient(apiKey: apiKey)
            translatedPage = try await client.translatePage(
                renderedPage: renderedPage,
                targetLanguage: targetLanguage,
                model: model
            )
            renderTranslatedPreview()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func renderTranslatedPreview() {
        isRenderingTranslatedPage = true
        defer { isRenderingTranslatedPage = false }

        do {
            if renderedPage == nil {
                renderCurrentPage()
            }

            guard let renderedPage else {
                throw PDFPageRendererError.missingPage
            }

            let page = if let translatedPage, !isMockTranslatedPage(translatedPage) {
                translatedPage
            } else {
                makeMockTranslatedPage(for: renderedPage)
            }
            translatedPage = page
            translatedRenderedPage = try translatedPageRenderer.render(
                renderedPage: renderedPage,
                translatedPage: page
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func makeMockTranslatedPage(for renderedPage: RenderedPage) -> TranslatedPage {
        if let page = document?.page(at: renderedPage.pageIndex),
           let textBasedPage = makeTextBasedMockTranslatedPage(for: page, renderedPage: renderedPage) {
            return textBasedPage
        }

        return makeFallbackMockTranslatedPage(for: renderedPage)
    }

    private func isMockTranslatedPage(_ page: TranslatedPage) -> Bool {
        page.blocks.allSatisfy { $0.id.hasPrefix("mock_") }
    }

    private func makeTextBasedMockTranslatedPage(for page: PDFPage, renderedPage: RenderedPage) -> TranslatedPage? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard let selection = page.selection(for: pageBounds) else {
            return nil
        }

        let lines = selection.selectionsByLine().compactMap { line -> TextLine? in
            let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let bounds = line.bounds(for: page)
            guard !text.isEmpty,
                  bounds.width > 4,
                  bounds.height > 4,
                  bounds.width < pageBounds.width * 0.96,
                  bounds.height < pageBounds.height * 0.2 else {
                return nil
            }
            return (text, bounds)
        }

        let clusters = textClusters(from: lines)
        let blocks = clusters.enumerated().compactMap { index, cluster -> TranslatedTextBlock? in
            guard !cluster.isEmpty,
                  let selectionBounds = unionRect(for: cluster) else {
                return nil
            }

            let text = cluster.map(\.text).joined(separator: " ")
            let role = inferredRole(for: cluster, bounds: selectionBounds, pageBounds: pageBounds)
            let bbox = imageBoundingBox(
                from: expandedRect(selectionBounds, in: pageBounds),
                pageBounds: pageBounds,
                scale: renderedPage.scale
            )

            return TranslatedTextBlock(
                id: "mock_pdf_text_\(index)",
                sourceText: text,
                translatedText: mockPersianText(for: text, role: role),
                bbox: bbox,
                role: role,
                confidence: 1
            )
        }

        guard !blocks.isEmpty else {
            return nil
        }

        return TranslatedPage(
            pageWidth: Double(renderedPage.width),
            pageHeight: Double(renderedPage.height),
            blocks: blocks
        )
    }

    private func textClusters(from lines: [TextLine]) -> [[TextLine]] {
        guard !lines.isEmpty else {
            return []
        }

        let sortedLines = lines.sorted {
            if abs($0.rect.midY - $1.rect.midY) > 3 {
                return $0.rect.midY > $1.rect.midY
            }
            return $0.rect.minX < $1.rect.minX
        }
        let sortedHeights = sortedLines.map(\.rect.height).sorted()
        let medianLineHeight = sortedHeights[sortedHeights.count / 2]
        let splitThreshold = max(medianLineHeight * 2.1, 18)

        var clusters: [[TextLine]] = []
        var currentCluster: [TextLine] = []
        var previousMidY: CGFloat?

        for line in sortedLines {
            if let previousMidY,
               abs(previousMidY - line.rect.midY) > splitThreshold,
               !currentCluster.isEmpty {
                clusters.append(currentCluster)
                currentCluster = [line]
            } else {
                currentCluster.append(line)
            }
            previousMidY = line.rect.midY
        }

        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        return clusters
    }

    private func unionRect(for lines: [TextLine]) -> CGRect? {
        guard var rect = lines.first?.rect else {
            return nil
        }

        for line in lines.dropFirst() {
            rect = rect.union(line.rect)
        }

        return rect
    }

    private func inferredRole(for lines: [TextLine], bounds: CGRect, pageBounds: CGRect) -> TextRole {
        let text = lines.map(\.text).joined(separator: " ")
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        let isNearTop = bounds.midY > pageBounds.maxY - pageBounds.height * 0.28
        let isShortSingleLine = lines.count == 1 && wordCount <= 10
        let lineHeight = lines.map(\.rect.height).max() ?? bounds.height

        if isNearTop, isShortSingleLine, lineHeight >= 14 {
            return .title
        }

        if isShortSingleLine, wordCount <= 6 {
            return .heading
        }

        return .paragraph
    }

    private func expandedRect(_ rect: CGRect, in pageBounds: CGRect) -> CGRect {
        let expanded = rect.insetBy(dx: -2, dy: -2)
        let clamped = expanded.intersection(pageBounds)
        return clamped.isNull || clamped.isEmpty ? rect : clamped
    }

    private func imageBoundingBox(from pdfRect: CGRect, pageBounds: CGRect, scale: CGFloat) -> BoundingBox {
        let x = (pdfRect.minX - pageBounds.minX) * scale
        let y = (pageBounds.maxY - pdfRect.maxY) * scale
        let width = pdfRect.width * scale
        let height = pdfRect.height * scale

        return BoundingBox(
            x: Double(max(0, x)),
            y: Double(max(0, y)),
            width: Double(max(1, width)),
            height: Double(max(1, height))
        )
    }

    private func mockPersianText(for sourceText: String, role: TextRole) -> String {
        let wordCount = sourceText.split(whereSeparator: \.isWhitespace).count
        if role == .title {
            if sourceText.localizedCaseInsensitiveContains("introduction") {
                return "مقدمه"
            }
            return "عنوان ترجمه‌شده"
        }

        if role == .heading || wordCount < 8 {
            return "ترجمه آزمایشی متن انتخاب‌شده"
        }

        if wordCount < 35 {
            return "این یک ترجمه آزمایشی برای متن همین صفحه است. هدف این پیش‌نمایش بررسی پوشاندن متن اصلی، چینش راست‌به‌چپ و جا شدن متن فارسی داخل همان ناحیه است."
        }

        let sentence = "این متن فارسی به‌صورت آزمایشی روی محل متن اصلی قرار گرفته است تا موتور بازسازی صفحه بررسی شود و متن انگلیسی زیر آن پوشانده شود."
        let targetWordCount = min(max(Int(Double(wordCount) * 0.7), 36), 140)
        var words: [String] = []

        while words.count < targetWordCount {
            words.append(contentsOf: sentence.split(separator: " ").map(String.init))
        }

        return words.prefix(targetWordCount).joined(separator: " ")
    }

    private func makeFallbackMockTranslatedPage(for renderedPage: RenderedPage) -> TranslatedPage {
        let width = Double(renderedPage.width)
        let height = Double(renderedPage.height)
        let leftMargin = width * 0.14
        let contentWidth = width * 0.72

        return TranslatedPage(
            pageWidth: width,
            pageHeight: height,
            blocks: [
                TranslatedTextBlock(
                    id: "mock_title",
                    sourceText: "Sample title",
                    translatedText: "عنوان نمونه برای پیش‌نمایش",
                    bbox: BoundingBox(x: leftMargin, y: height * 0.12, width: contentWidth, height: height * 0.07),
                    role: .title,
                    confidence: 1
                ),
                TranslatedTextBlock(
                    id: "mock_paragraph_1",
                    sourceText: "Sample paragraph",
                    translatedText: "این یک متن آزمایشی فارسی است که برای بررسی چینش راست‌به‌چپ، اندازه فونت و قرارگیری داخل کادر صفحه استفاده می‌شود.",
                    bbox: BoundingBox(x: leftMargin, y: height * 0.24, width: contentWidth, height: height * 0.12),
                    role: .paragraph,
                    confidence: 1
                ),
                TranslatedTextBlock(
                    id: "mock_caption",
                    sourceText: "Sample caption",
                    translatedText: "زیرنویس آزمایشی",
                    bbox: BoundingBox(x: leftMargin, y: height * 0.72, width: contentWidth, height: height * 0.05),
                    role: .caption,
                    confidence: 1
                )
            ]
        )
    }

    private func normalizedSetting(key: String, fallback: String) -> String {
        let value = UserDefaults.standard.string(forKey: key) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
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
