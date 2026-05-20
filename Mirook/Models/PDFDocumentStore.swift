import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class PDFDocumentStore: ObservableObject {
    @Published private(set) var document: PDFDocument?
    @Published private(set) var documentURL: URL?
    @Published var currentPageIndex: Int = 0 {
        didSet {
            guard oldValue != currentPageIndex, pageCount > 0 else { return }
            let previousPageNumber = oldValue + 1
            if pageSelection.startPage == previousPageNumber,
               pageSelection.endPage == previousPageNumber {
                pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
            }
            renderedPage = nil
            translatedPage = nil
            translatedRenderedPage = nil
            translatedTextPage = translatedTextPagesByIndex[currentPageIndex]
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
    @Published private(set) var translatedRenderedPagesByIndex: [Int: TranslatedRenderedPage] = [:]
    @Published private(set) var translatedTextPage: TranslatedTextPage?
    @Published private(set) var translatedTextPagesByIndex: [Int: TranslatedTextPage] = [:]
    @Published private(set) var isTranslatingTextPage = false
    @Published private(set) var textTranslationProgressCurrent = 0
    @Published private(set) var textTranslationProgressTotal = 0
    @Published private(set) var textTranslationProgressPageNumber: Int?
    @Published private(set) var isExportingPDF = false
    @Published private(set) var isExportingTextPDF = false
    @Published private(set) var lastExportedPDFURL: URL?
    @Published private(set) var lastExportedTextPDFURL: URL?
    @Published private(set) var currentTranslationProject: TranslationProjectManifest?
    @Published private(set) var availableAIModels: [AIModelInfo] = []
    @Published private(set) var isLoadingAIModels = false
    @Published private(set) var lastTranslationUsage: AIUsage?
    @Published var lastErrorMessage: String?

    private let pageRenderer = PDFPageRenderer(scale: 2.0)
    private let translatedPageRenderer = TranslatedPageRenderer()
    private let pdfExportService = PDFExportService()
    private let textPDFExportService = TextPDFExportService()
    private let translationProjectStore = TranslationProjectStore()
    private let keychainService = KeychainService()

    private enum SettingsKey {
        static let openAIAPIKeyAccount = "openai-api-key"
        static let defaultAIProvider = "defaultAIProvider"
        static let defaultAIBaseURL = "defaultAIBaseURL"
        static let defaultTargetLanguage = "defaultTargetLanguage"
        static let defaultModelName = "defaultModelName"
        static let fallbackAIProvider = "responses"
        static let fallbackAIBaseURL = "https://api.openai.com/v1"
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

    var selectedPageNumbers: [Int] {
        guard let range = selectedPageRange else { return [] }
        return Array(range)
    }

    var selectedPageCount: Int {
        selectedPageNumbers.count
    }

    var selectedMissingTextPageCount: Int {
        selectedPageNumbers.filter { pageNumber in
            translatedTextPagesByIndex[pageNumber - 1] == nil
        }.count
    }

    var textTranslationProgressDescription: String {
        guard isTranslatingTextPage else { return "" }
        guard textTranslationProgressTotal > 1 else { return "Translating text..." }

        if let pageNumber = textTranslationProgressPageNumber {
            return "Translating page \(pageNumber) (\(textTranslationProgressCurrent) of \(textTranslationProgressTotal))"
        }
        return "Translating text (\(textTranslationProgressCurrent) of \(textTranslationProgressTotal))"
    }

    var lastTranslationUsageDescription: String? {
        guard let lastTranslationUsage else { return nil }
        return "Last usage: \(lastTranslationUsage.displayText)"
    }

    var translatedExportPageCount: Int {
        translatedRenderedPagesByIndex.count
    }

    var translatedTextExportPageCount: Int {
        translatedTextPagesByIndex.count
    }

    var translatedTextBlankPageCount: Int {
        translatedTextPagesByIndex.values.filter(\.isBlank).count
    }

    var translatedTextMissingPageCount: Int {
        guard pageCount > 0 else { return 0 }
        return max(pageCount - translatedTextPagesByIndex.count, 0)
    }

    var translatedTextCoverageDescription: String {
        guard pageCount > 0 else { return "No PDF open" }
        let translatedCount = translatedTextExportPageCount - translatedTextBlankPageCount
        return "\(translatedTextExportPageCount) / \(pageCount) pages ready, \(translatedCount) translated, \(translatedTextBlankPageCount) blank, \(translatedTextMissingPageCount) missing"
    }

    var canExportCompleteTextBook: Bool {
        pageCount > 0 && translatedTextMissingPageCount == 0
    }

    var currentTranslationProjectPath: String? {
        guard let currentTranslationProject,
              let url = try? translationProjectStore.projectDirectoryURL(projectID: currentTranslationProject.id) else {
            return nil
        }

        return url.path
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
        translatedRenderedPagesByIndex = [:]
        translatedTextPage = nil
        lastExportedPDFURL = nil
        lastExportedTextPDFURL = nil
        lastErrorMessage = nil

        do {
            let model = normalizedSetting(
                key: SettingsKey.defaultModelName,
                fallback: SettingsKey.fallbackModelName
            )
            let targetLanguage = normalizedSetting(
                key: SettingsKey.defaultTargetLanguage,
                fallback: SettingsKey.fallbackTargetLanguage
            )
            let project = try translationProjectStore.loadOrCreateProject(
                sourceURL: url,
                displayName: loadedDocument.documentURL?.deletingPathExtension().lastPathComponent ?? url.deletingPathExtension().lastPathComponent,
                pageCount: loadedDocument.pageCount,
                targetLanguage: targetLanguage,
                model: model
            )
            currentTranslationProject = project
            translatedTextPagesByIndex = try translationProjectStore.loadPages(projectID: project.id)
            translatedTextPage = translatedTextPagesByIndex[currentPageIndex]
        } catch {
            currentTranslationProject = nil
            translatedTextPagesByIndex = [:]
            lastErrorMessage = error.localizedDescription
        }
    }

    func goToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
        renderedPage = nil
        translatedPage = nil
        translatedRenderedPage = nil
        translatedTextPage = translatedTextPagesByIndex[currentPageIndex]
    }

    func goToNextPage() {
        guard currentPageIndex + 1 < pageCount else { return }
        currentPageIndex += 1
        renderedPage = nil
        translatedPage = nil
        translatedRenderedPage = nil
        translatedTextPage = translatedTextPagesByIndex[currentPageIndex]
    }

    func goToPage(number: Int) {
        guard pageCount > 0 else { return }
        currentPageIndex = min(max(number - 1, 0), pageCount - 1)
        renderedPage = nil
        translatedPage = nil
        translatedRenderedPage = nil
        translatedTextPage = translatedTextPagesByIndex[currentPageIndex]
    }

    func setPageSelection(startPage: Int, endPage: Int) {
        guard pageCount > 0 else {
            pageSelection = .firstPage
            return
        }

        pageSelection = PDFPageSelection(
            startPage: clampedPageNumber(startPage),
            endPage: clampedPageNumber(endPage)
        )
    }

    func selectCurrentPage() {
        guard pageCount > 0 else { return }
        pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
    }

    func selectAllPages() {
        guard pageCount > 0 else { return }
        pageSelection = PDFPageSelection(startPage: 1, endPage: pageCount)
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
            translatedRenderedPagesByIndex[currentPageIndex] = nil
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
            let baseURL = normalizedSetting(
                key: SettingsKey.defaultAIBaseURL,
                fallback: SettingsKey.fallbackAIBaseURL
            )
            let provider = normalizedSetting(
                key: SettingsKey.defaultAIProvider,
                fallback: SettingsKey.fallbackAIProvider
            )
            let targetLanguage = normalizedSetting(
                key: SettingsKey.defaultTargetLanguage,
                fallback: SettingsKey.fallbackTargetLanguage
            )

            let client = OpenAIClient(
                apiKey: apiKey,
                baseURL: baseURL,
                apiStyle: OpenAIClient.APIStyle(rawValue: provider) ?? .responses
            )
            let result = try await client.translatePage(
                renderedPage: renderedPage,
                targetLanguage: targetLanguage,
                model: model
            )
            translatedPage = result.page
            lastTranslationUsage = result.usage
            renderTranslatedPreview()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func translateCurrentPageAsText() async {
        guard pageCount > 0 else {
            lastErrorMessage = "Open a PDF before translating a page."
            return
        }

        await translateTextPagesAsText(
            pageNumbers: [currentPageNumber]
        )
    }

    func translateSelectedPagesAsText() async {
        guard pageCount > 0 else {
            lastErrorMessage = "Open a PDF before translating pages."
            return
        }

        await translateTextPagesAsText(
            pageNumbers: selectedPageNumbers
        )
    }

    func translateMissingSelectedPagesAsText() async {
        guard pageCount > 0 else {
            lastErrorMessage = "Open a PDF before translating pages."
            return
        }

        let missingPageNumbers = selectedPageNumbers.filter { pageNumber in
            translatedTextPagesByIndex[pageNumber - 1] == nil
        }

        guard !missingPageNumbers.isEmpty else {
            lastErrorMessage = "All selected pages are already saved in this translation project."
            return
        }

        await translateTextPagesAsText(pageNumbers: missingPageNumbers)
    }

    func loadAvailableAIModels() async {
        isLoadingAIModels = true
        defer { isLoadingAIModels = false }

        do {
            let apiKey = try keychainService.read(account: SettingsKey.openAIAPIKeyAccount) ?? ""
            let baseURL = normalizedSetting(
                key: SettingsKey.defaultAIBaseURL,
                fallback: SettingsKey.fallbackAIBaseURL
            )
            let provider = normalizedSetting(
                key: SettingsKey.defaultAIProvider,
                fallback: SettingsKey.fallbackAIProvider
            )
            let client = OpenAIClient(
                apiKey: apiKey,
                baseURL: baseURL,
                apiStyle: OpenAIClient.APIStyle(rawValue: provider) ?? .responses
            )
            availableAIModels = try await client.listModels()
            lastErrorMessage = nil
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
            let renderedTranslation = try translatedPageRenderer.render(
                renderedPage: renderedPage,
                translatedPage: page
            )
            translatedRenderedPage = renderedTranslation
            translatedRenderedPagesByIndex[renderedTranslation.pageIndex] = renderedTranslation
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func exportTranslatedPDF() {
        guard !translatedRenderedPagesByIndex.isEmpty else {
            lastErrorMessage = PDFExportServiceError.noPages.localizedDescription
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = "\(displayName)-translated.pdf"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }

        isExportingPDF = true
        defer { isExportingPDF = false }

        do {
            try pdfExportService.export(
                pages: Array(translatedRenderedPagesByIndex.values),
                to: url
            )
            lastExportedPDFURL = url
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func exportTextTranslatedPDF(options: TextPDFExportOptions = .default) {
        guard !translatedTextPagesByIndex.isEmpty else {
            lastErrorMessage = TextPDFExportServiceError.noPages.localizedDescription
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = "\(displayName)-text-translated.pdf"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }

        isExportingTextPDF = true
        defer { isExportingTextPDF = false }

        do {
            if let currentTranslationProject {
                try translationProjectStore.saveExportOptions(options, projectID: currentTranslationProject.id)
            }
            try textPDFExportService.export(
                pages: Array(translatedTextPagesByIndex.values),
                to: url,
                options: options
            )
            lastExportedTextPDFURL = url
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func exportCompleteTextBook(options: TextPDFExportOptions = .default) {
        guard pageCount > 0 else {
            lastErrorMessage = "Open a PDF before exporting a complete book."
            return
        }

        guard canExportCompleteTextBook else {
            lastErrorMessage = "Translate or preserve all pages before exporting the complete book. Missing pages: \(formattedPageList(missingTextPageNumbers()))."
            return
        }

        let pages = (0..<pageCount).compactMap { translatedTextPagesByIndex[$0] }
        guard pages.count == pageCount else {
            lastErrorMessage = "Mirook could not collect every page for export."
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = "\(displayName)-complete-translated.pdf"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }

        isExportingTextPDF = true
        defer { isExportingTextPDF = false }

        do {
            if let currentTranslationProject {
                try translationProjectStore.saveExportOptions(options, projectID: currentTranslationProject.id)
            }
            try textPDFExportService.export(
                pages: pages,
                to: url,
                options: options
            )
            lastExportedTextPDFURL = url
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func translateTextPagesAsText(pageNumbers: [Int]) async {
        guard let document else {
            lastErrorMessage = "Open a PDF before translating pages."
            return
        }

        let normalizedPageNumbers = uniquePageNumbers(pageNumbers)
        guard !normalizedPageNumbers.isEmpty else {
            lastErrorMessage = "Choose at least one page before translating."
            return
        }

        isTranslatingTextPage = true
        lastTranslationUsage = nil
        textTranslationProgressCurrent = 0
        textTranslationProgressTotal = normalizedPageNumbers.count
        textTranslationProgressPageNumber = nil
        defer {
            isTranslatingTextPage = false
            textTranslationProgressCurrent = 0
            textTranslationProgressTotal = 0
            textTranslationProgressPageNumber = nil
        }

        do {
            let model = normalizedSetting(
                key: SettingsKey.defaultModelName,
                fallback: SettingsKey.fallbackModelName
            )
            let targetLanguage = normalizedSetting(
                key: SettingsKey.defaultTargetLanguage,
                fallback: SettingsKey.fallbackTargetLanguage
            )

            var client: OpenAIClient?
            func translationClient() throws -> OpenAIClient {
                if let client {
                    return client
                }

                let apiKey = try keychainService.read(account: SettingsKey.openAIAPIKeyAccount) ?? ""
                let baseURL = normalizedSetting(
                    key: SettingsKey.defaultAIBaseURL,
                    fallback: SettingsKey.fallbackAIBaseURL
                )
                let provider = normalizedSetting(
                    key: SettingsKey.defaultAIProvider,
                    fallback: SettingsKey.fallbackAIProvider
                )
                let newClient = OpenAIClient(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    apiStyle: OpenAIClient.APIStyle(rawValue: provider) ?? .responses
                )
                client = newClient
                return newClient
            }

            var blankPageNumbers: [Int] = []
            var operationUsage = AIUsage.zero

            for (offset, pageNumber) in normalizedPageNumbers.enumerated() {
                textTranslationProgressCurrent = offset + 1
                textTranslationProgressPageNumber = pageNumber

                guard let page = document.page(at: pageNumber - 1) else {
                    blankPageNumbers.append(pageNumber)
                    try cacheTranslatedTextPage(blankTextPage(pageNumber: pageNumber))
                    continue
                }

                let sourceText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sourceText.isEmpty else {
                    blankPageNumbers.append(pageNumber)
                    try cacheTranslatedTextPage(blankTextPage(pageNumber: pageNumber))
                    continue
                }

                let translationResult = try await translationClient().translateText(
                    sourceText,
                    targetLanguage: targetLanguage,
                    model: model
                )
                operationUsage.add(translationResult.usage)
                let translatedTextPage = TranslatedTextPage(
                    pageIndex: pageNumber - 1,
                    sourceText: sourceText,
                    translatedText: translationResult.text,
                    isBlank: false
                )
                try cacheTranslatedTextPage(translatedTextPage)
            }

            translatedTextPage = translatedTextPagesByIndex[currentPageIndex]
            lastTranslationUsage = operationUsage.hasTokens ? operationUsage : nil

            if !blankPageNumbers.isEmpty {
                lastErrorMessage = "Preserved blank pages: \(formattedPageList(blankPageNumbers))."
            } else {
                lastErrorMessage = nil
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func blankTextPage(pageNumber: Int) -> TranslatedTextPage {
        TranslatedTextPage(
            pageIndex: pageNumber - 1,
            sourceText: "",
            translatedText: "",
            isBlank: true
        )
    }

    private func cacheTranslatedTextPage(_ page: TranslatedTextPage) throws {
        translatedTextPagesByIndex[page.pageIndex] = page

        if page.pageIndex == currentPageIndex {
            translatedTextPage = page
        }

        if let currentTranslationProject {
            try translationProjectStore.savePage(page, projectID: currentTranslationProject.id)
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

    private var selectedPageRange: ClosedRange<Int>? {
        guard pageCount > 0 else { return nil }

        let normalized = pageSelection.normalized
        let lowerBound = clampedPageNumber(normalized.lowerBound)
        let upperBound = clampedPageNumber(normalized.upperBound)
        return min(lowerBound, upperBound)...max(lowerBound, upperBound)
    }

    private func clampedPageNumber(_ pageNumber: Int) -> Int {
        min(max(pageNumber, 1), max(pageCount, 1))
    }

    private func uniquePageNumbers(_ pageNumbers: [Int]) -> [Int] {
        var seenPageNumbers = Set<Int>()
        return pageNumbers
            .map(clampedPageNumber)
            .filter { pageNumber in
                seenPageNumbers.insert(pageNumber).inserted
            }
    }

    private func missingTextPageNumbers() -> [Int] {
        guard pageCount > 0 else { return [] }
        return (0..<pageCount)
            .filter { translatedTextPagesByIndex[$0] == nil }
            .map { $0 + 1 }
    }

    private func formattedPageList(_ pageNumbers: [Int]) -> String {
        let sortedNumbers = pageNumbers.sorted()
        let visibleNumbers = sortedNumbers.prefix(8).map(String.init).joined(separator: ", ")
        return sortedNumbers.count > 8 ? "\(visibleNumbers), ..." : visibleNumbers
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
