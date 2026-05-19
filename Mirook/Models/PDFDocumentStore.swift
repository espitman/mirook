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
        }
    }
    @Published var zoomScale: CGFloat = 1.0
    @Published var pageSelection: PDFPageSelection = .firstPage
    @Published private(set) var renderedPage: RenderedPage?
    @Published private(set) var isRenderingPage = false
    @Published private(set) var translatedPage: TranslatedPage?
    @Published private(set) var isTranslatingPage = false
    @Published var lastErrorMessage: String?

    private let pageRenderer = PDFPageRenderer(scale: 2.0)
    private let keychainService = KeychainService()

    private enum SettingsKey {
        static let openAIAPIKeyAccount = "openai-api-key"
        static let defaultTargetLanguage = "defaultTargetLanguage"
        static let defaultModelName = "defaultModelName"
        static let fallbackTargetLanguage = "Persian"
        static let fallbackModelName = "gpt-5.2"
    }

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
        lastErrorMessage = nil
    }

    func goToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
        pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
        renderedPage = nil
        translatedPage = nil
    }

    func goToNextPage() {
        guard currentPageIndex + 1 < pageCount else { return }
        currentPageIndex += 1
        pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
        renderedPage = nil
        translatedPage = nil
    }

    func goToPage(number: Int) {
        guard pageCount > 0 else { return }
        currentPageIndex = min(max(number - 1, 0), pageCount - 1)
        pageSelection = PDFPageSelection(startPage: currentPageNumber, endPage: currentPageNumber)
        renderedPage = nil
        translatedPage = nil
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
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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
