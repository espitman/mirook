import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class PDFDocumentStore: ObservableObject {
    @Published private(set) var document: PDFDocument?
    @Published private(set) var documentURL: URL?
    @Published private(set) var documentDisplayName: String?
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
    @Published var isReadingMode = false
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
    @Published private(set) var isCurrentBookPasswordProtected = false
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
    private static let currentParagraphLayoutVersion = 3

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

    private struct ParagraphCluster {
        let text: String
        let bounds: CGRect
        let role: TextRole
    }

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    var displayName: String {
        documentDisplayName ?? documentURL?.deletingPathExtension().lastPathComponent ?? "Untitled PDF"
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

    var lastTranslationCostDescription: String? {
        guard let lastTranslationUsage else { return nil }
        return "Last run: \(lastTranslationUsage.costDisplayText ?? "cost not returned")"
    }

    var lastTranslationTokenDescription: String? {
        guard let lastTranslationUsage, lastTranslationUsage.hasTokens else { return nil }
        return lastTranslationUsage.tokenDisplayText
    }

    var projectCostDescription: String? {
        guard let totalUsage = currentTranslationProject?.totalUsage,
              totalUsage.hasUsage else {
            return nil
        }

        return "Project total: \(totalUsage.costDisplayText ?? "cost not returned")"
    }

    var projectTokenDescription: String? {
        guard let totalUsage = currentTranslationProject?.totalUsage,
              totalUsage.hasTokens else {
            return nil
        }

        return totalUsage.tokenDisplayText
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

    var lastTranslatedTextPageNumber: Int? {
        translatedTextPagesByIndex
            .filter { !$0.value.isBlank }
            .map(\.key)
            .max()
            .map { $0 + 1 }
    }

    var canGoToLastTranslatedTextPage: Bool {
        lastTranslatedTextPageNumber != nil
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

        do {
            try openLoadedPDF(loadedDocument, sourceURL: url, displayName: url.deletingPathExtension().lastPathComponent)
        } catch let error as TranslationProjectStoreError {
            handleOpenError(error) {
                try openLoadedPDF(loadedDocument, sourceURL: url, displayName: url.deletingPathExtension().lastPathComponent)
            }
        } catch {
            resetProjectStateAfterOpenFailure()
            lastErrorMessage = error.localizedDescription
        }
    }

    func openBook(from url: URL) {
        do {
            let package = try translationProjectStore.loadProject(fromBookURL: url)
            guard let loadedDocument = PDFDocument(data: package.pdfData) else {
                lastErrorMessage = "The embedded PDF in this Mirook book could not be opened."
                return
            }

            try openLoadedBook(loadedDocument, package: package)
        } catch let error as TranslationProjectStoreError {
            handleOpenError(error) {
                let package = try translationProjectStore.loadProject(fromBookURL: url)
                guard let loadedDocument = PDFDocument(data: package.pdfData) else {
                    throw TranslationProjectStoreError.missingEmbeddedPDF(displayName: url.deletingPathExtension().lastPathComponent)
                }

                try openLoadedBook(loadedDocument, package: package)
            }
        } catch {
            resetProjectStateAfterOpenFailure()
            lastErrorMessage = error.localizedDescription
        }
    }

    func revealCurrentBookFile() {
        guard let currentTranslationProject,
              let url = try? translationProjectStore.projectDirectoryURL(projectID: currentTranslationProject.id) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func setCurrentBookPassword() {
        guard let currentTranslationProject else { return }
        guard let password = promptForNewPassword(title: "Set Book Password") else { return }

        do {
            try translationProjectStore.setPassword(projectID: currentTranslationProject.id, password: password)
            try refreshCurrentBookPasswordStatus()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func changeCurrentBookPassword() {
        guard let currentTranslationProject else { return }
        guard let oldPassword = promptForPassword(title: "Current Password", message: "Enter the current password for this book.") else { return }
        guard let newPassword = promptForNewPassword(title: "Change Book Password") else { return }

        do {
            try translationProjectStore.changePassword(
                projectID: currentTranslationProject.id,
                oldPassword: oldPassword,
                newPassword: newPassword
            )
            try refreshCurrentBookPasswordStatus()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeCurrentBookPassword() {
        guard let currentTranslationProject else { return }
        guard let password = promptForPassword(title: "Remove Book Password", message: "Enter the current password to remove protection.") else { return }

        do {
            try translationProjectStore.removePassword(projectID: currentTranslationProject.id, password: password)
            try refreshCurrentBookPasswordStatus()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func openLoadedPDF(_ loadedDocument: PDFDocument, sourceURL: URL, displayName: String) throws {
        let model = normalizedSetting(
            key: SettingsKey.defaultModelName,
            fallback: SettingsKey.fallbackModelName
        )
        let targetLanguage = normalizedSetting(
            key: SettingsKey.defaultTargetLanguage,
            fallback: SettingsKey.fallbackTargetLanguage
        )
        let project = try translationProjectStore.loadOrCreateProject(
            sourceURL: sourceURL,
            displayName: loadedDocument.documentURL?.deletingPathExtension().lastPathComponent ?? displayName,
            pageCount: loadedDocument.pageCount,
            targetLanguage: targetLanguage,
            model: model
        )

        try applyOpenedDocument(
            loadedDocument,
            sourceURL: sourceURL,
            displayName: project.displayName,
            project: project
        )
    }

    private func openLoadedBook(_ loadedDocument: PDFDocument, package: TranslationProjectPackage) throws {
        try applyOpenedDocument(
            loadedDocument,
            sourceURL: URL(fileURLWithPath: package.manifest.sourcePath),
            displayName: package.manifest.displayName,
            project: package.manifest
        )
    }

    private func applyOpenedDocument(
        _ loadedDocument: PDFDocument,
        sourceURL: URL?,
        displayName: String,
        project: TranslationProjectManifest
    ) throws {
        document = loadedDocument
        documentURL = sourceURL
        documentDisplayName = displayName
        currentPageIndex = 0
        zoomScale = 1.0
        isReadingMode = false
        pageSelection = .firstPage
        renderedPage = nil
        translatedPage = nil
        translatedRenderedPage = nil
        translatedRenderedPagesByIndex = [:]
        translatedTextPage = nil
        lastExportedPDFURL = nil
        lastExportedTextPDFURL = nil
        lastErrorMessage = nil

        currentTranslationProject = project
        translatedTextPagesByIndex = try translationProjectStore.loadPages(projectID: project.id)
        hydrateParagraphBlocksForLoadedPages(document: loadedDocument, projectID: project.id)
        translatedTextPage = translatedTextPagesByIndex[currentPageIndex]
        try refreshCurrentBookPasswordStatus()
    }

    private func resetProjectStateAfterOpenFailure() {
        currentTranslationProject = nil
        translatedTextPagesByIndex = [:]
        translatedTextPage = nil
        isCurrentBookPasswordProtected = false
    }

    private func handleOpenError(_ error: TranslationProjectStoreError, retry: () throws -> Void) {
        guard case let .lockedBook(bookURL, displayName) = error else {
            resetProjectStateAfterOpenFailure()
            lastErrorMessage = error.localizedDescription
            return
        }

        guard let password = promptForPassword(
            title: "Unlock \(displayName)",
            message: "Enter the password for this Mirook book."
        ) else {
            resetProjectStateAfterOpenFailure()
            return
        }

        do {
            try translationProjectStore.unlockBook(at: bookURL, password: password)
            try retry()
        } catch {
            resetProjectStateAfterOpenFailure()
            lastErrorMessage = error.localizedDescription
        }
    }

    private func refreshCurrentBookPasswordStatus() throws {
        guard let currentTranslationProject else {
            isCurrentBookPasswordProtected = false
            return
        }

        isCurrentBookPasswordProtected = try translationProjectStore.isPasswordProtected(projectID: currentTranslationProject.id)
    }

    private func promptForPassword(title: String, message: String) -> String? {
        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        passwordField.placeholderString = "Password"

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = passwordField
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        return passwordField.stringValue
    }

    private func promptForNewPassword(title: String) -> String? {
        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 28, width: 260, height: 24))
        passwordField.placeholderString = "Password"
        let confirmField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        confirmField.placeholderString = "Confirm password"

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        accessory.addSubview(passwordField)
        accessory.addSubview(confirmField)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "This password cannot be recovered if you forget it."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        guard !passwordField.stringValue.isEmpty else {
            lastErrorMessage = "Password cannot be empty."
            return nil
        }

        guard passwordField.stringValue == confirmField.stringValue else {
            lastErrorMessage = "Passwords do not match."
            return nil
        }

        return passwordField.stringValue
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

    func goToLastTranslatedTextPage() {
        guard let pageNumber = lastTranslatedTextPageNumber else { return }
        goToPage(number: pageNumber)
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
            try recordProjectUsage(result.usage)
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

                let sourceText = sourceTextForTranslation(on: page)
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
                let translatedTextPage = TranslatedTextPage(
                    pageIndex: pageNumber - 1,
                    sourceText: sourceText,
                    translatedText: translationResult.text,
                    isBlank: false
                )
                try cacheTranslatedTextPage(translatedTextPage)
                operationUsage.add(translationResult.usage)
                try recordProjectUsage(translationResult.usage)
            }

            translatedTextPage = translatedTextPagesByIndex[currentPageIndex]
            lastTranslationUsage = operationUsage.hasUsage ? operationUsage : nil

            lastErrorMessage = nil
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
        let hydratedPage = paragraphBlockHydratedPage(page)
        translatedTextPagesByIndex[hydratedPage.pageIndex] = hydratedPage

        if hydratedPage.pageIndex == currentPageIndex {
            translatedTextPage = hydratedPage
        }

        if let currentTranslationProject {
            try translationProjectStore.savePage(hydratedPage, projectID: currentTranslationProject.id)
        }
    }

    private func hydrateParagraphBlocksForLoadedPages(document: PDFDocument, projectID: String) {
        for page in translatedTextPagesByIndex.values
        where !page.isBlank && page.paragraphLayoutVersion < Self.currentParagraphLayoutVersion {
            guard let pdfPage = document.page(at: page.pageIndex) else {
                continue
            }

            let blocks = makeParagraphBlocks(for: page, pdfPage: pdfPage)
            guard !blocks.isEmpty else {
                continue
            }

            let updatedPage = TranslatedTextPage(
                pageIndex: page.pageIndex,
                sourceText: page.sourceText,
                translatedText: page.translatedText,
                isBlank: page.isBlank,
                paragraphBlocks: blocks,
                paragraphLayoutVersion: Self.currentParagraphLayoutVersion
            )
            translatedTextPagesByIndex[page.pageIndex] = updatedPage
            try? translationProjectStore.savePage(updatedPage, projectID: projectID)
        }
    }

    private func paragraphBlockHydratedPage(_ page: TranslatedTextPage) -> TranslatedTextPage {
        guard !page.isBlank,
              let pdfPage = document?.page(at: page.pageIndex) else {
            return page
        }

        let blocks = makeParagraphBlocks(for: page, pdfPage: pdfPage)
        guard !blocks.isEmpty else {
            return page
        }

        return TranslatedTextPage(
            pageIndex: page.pageIndex,
            sourceText: page.sourceText,
            translatedText: page.translatedText,
            isBlank: page.isBlank,
            paragraphBlocks: blocks,
            paragraphLayoutVersion: Self.currentParagraphLayoutVersion
        )
    }

    private func sourceTextForTranslation(on page: PDFPage) -> String {
        let clusteredText = sourceParagraphClusters(for: page)
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        if !clusteredText.isEmpty {
            return clusteredText
        }

        return (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sourceParagraphClusters(for pdfPage: PDFPage) -> [ParagraphCluster] {
        let pageBounds = pdfPage.bounds(for: .mediaBox)
        guard let selection = pdfPage.selection(for: pageBounds) else {
            return []
        }

        let lines = readableTextLines(from: selection, on: pdfPage, pageBounds: pageBounds)
        return textClusters(from: lines).compactMap { cluster -> ParagraphCluster? in
            guard let bounds = unionRect(for: cluster) else {
                return nil
            }

            let role = inferredRole(for: cluster, bounds: bounds, pageBounds: pageBounds)
            guard role != .pageNumber else {
                return nil
            }

            return ParagraphCluster(
                text: cluster.map(\.text).joined(separator: " "),
                bounds: expandedRect(bounds, in: pageBounds),
                role: role
            )
        }
    }

    private func readableTextLines(
        from selection: PDFSelection,
        on page: PDFPage,
        pageBounds: CGRect
    ) -> [TextLine] {
        selection.selectionsByLine().compactMap { line -> TextLine? in
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
    }

    private func makeParagraphBlocks(
        for textPage: TranslatedTextPage,
        pdfPage: PDFPage
    ) -> [TranslatedTextParagraphBlock] {
        let translatedParagraphs = splitParagraphs(textPage.translatedText)
        guard !translatedParagraphs.isEmpty else {
            return []
        }

        let clusters = sourceParagraphClusters(for: pdfPage)

        guard !clusters.isEmpty else {
            return []
        }

        let alignedTranslations = alignedTranslatedParagraphs(
            translatedParagraphs,
            targetClusters: clusters
        )
        guard alignedTranslations.count == clusters.count else {
            return []
        }

        let confidence = translatedParagraphs.count == clusters.count ? 1.0 : 0.72
        return zip(clusters.indices, zip(clusters, alignedTranslations)).map { index, pair in
            let (cluster, translatedParagraph) = pair
            return TranslatedTextParagraphBlock(
                id: "paragraph_\(textPage.pageIndex + 1)_\(index)",
                sourceText: cluster.text,
                translatedText: translatedParagraph,
                pdfBounds: BoundingBox(
                    x: Double(cluster.bounds.minX),
                    y: Double(cluster.bounds.minY),
                    width: Double(cluster.bounds.width),
                    height: Double(cluster.bounds.height)
                ),
                role: cluster.role,
                confidence: confidence
            )
        }
    }

    private func splitParagraphs(_ text: String) -> [String] {
        var paragraphs: [String] = []
        var currentLines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                if !currentLines.isEmpty {
                    paragraphs.append(currentLines.joined(separator: " "))
                    currentLines = []
                }
            } else {
                currentLines.append(trimmedLine)
            }
        }

        if !currentLines.isEmpty {
            paragraphs.append(currentLines.joined(separator: " "))
        }

        return paragraphs
    }

    private func alignedTranslatedParagraphs(_ paragraphs: [String], targetClusters: [ParagraphCluster]) -> [String] {
        let targetCount = targetClusters.count
        guard targetCount > 0 else {
            return []
        }

        if paragraphs.count == targetCount {
            return paragraphs
        }

        if paragraphs.count > targetCount {
            return mergedParagraphs(paragraphs, targetCount: targetCount)
        }

        return expandedParagraphs(paragraphs, targetClusters: targetClusters)
    }

    private func expandedParagraphs(_ paragraphs: [String], targetClusters: [ParagraphCluster]) -> [String] {
        let targetCount = targetClusters.count
        guard targetCount > 0, paragraphs.count < targetCount else {
            return paragraphs
        }

        let translatedSentences = sentenceSegments(in: paragraphs.joined(separator: " "))
        if translatedSentences.count >= targetCount {
            return distributedSegments(translatedSentences, targetClusters: targetClusters)
        }

        var result = paragraphs
        while result.count < targetCount {
            let splitCandidate = result.indices
                .map { index in (index: index, parts: splitParagraphOnce(result[index]), length: result[index].count) }
                .filter { $0.parts.count == 2 }
                .max { $0.length < $1.length }

            guard let splitCandidate else {
                break
            }

            result.replaceSubrange(splitCandidate.index...splitCandidate.index, with: splitCandidate.parts)
        }

        return result
    }

    private func distributedSegments(_ segments: [String], targetClusters: [ParagraphCluster]) -> [String] {
        guard !targetClusters.isEmpty, segments.count >= targetClusters.count else {
            return segments
        }

        let weights = targetClusters.map { cluster in
            max(sentenceSegments(in: cluster.text).count, cluster.text.split(whereSeparator: \.isWhitespace).count / 35, 1)
        }
        let totalWeight = max(weights.reduce(0, +), 1)
        var result: [String] = []
        var cursor = 0
        var cumulativeWeight = 0

        for index in targetClusters.indices {
            cumulativeWeight += weights[index]

            let remainingGroups = targetClusters.count - index - 1
            let idealEnd = Int((Double(segments.count) * Double(cumulativeWeight) / Double(totalWeight)).rounded())
            let minimumEnd = cursor + 1
            let maximumEnd = segments.count - remainingGroups
            let end = min(max(idealEnd, minimumEnd), maximumEnd)

            result.append(segments[cursor..<end].joined(separator: " "))
            cursor = end
        }

        return result
    }

    private func splitParagraphOnce(_ paragraph: String) -> [String] {
        let sentences = sentenceSegments(in: paragraph)
        if sentences.count > 1 {
            let totalCharacters = sentences.reduce(0) { $0 + $1.count }
            let targetCharacters = max(totalCharacters / 2, 1)
            var firstHalf: [String] = []
            var secondHalf: [String] = []
            var consumedCharacters = 0

            for sentence in sentences {
                if consumedCharacters < targetCharacters || firstHalf.isEmpty {
                    firstHalf.append(sentence)
                    consumedCharacters += sentence.count
                } else {
                    secondHalf.append(sentence)
                }
            }

            if !firstHalf.isEmpty, !secondHalf.isEmpty {
                return [
                    firstHalf.joined(separator: " "),
                    secondHalf.joined(separator: " ")
                ]
            }
        }

        let words = paragraph.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 12 else {
            return [paragraph]
        }

        let midpoint = words.count / 2
        return [
            words[..<midpoint].joined(separator: " "),
            words[midpoint...].joined(separator: " ")
        ]
    }

    private func sentenceSegments(in paragraph: String) -> [String] {
        let terminators = Set<Character>(".!?؟。")
        var segments: [String] = []
        var current = ""

        for character in paragraph {
            current.append(character)
            if terminators.contains(character) {
                let segment = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !segment.isEmpty {
                    segments.append(segment)
                }
                current = ""
            }
        }

        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            segments.append(remaining)
        }

        return segments
    }

    private func mergedClusters(_ clusters: [ParagraphCluster], targetCount: Int) -> [ParagraphCluster] {
        guard targetCount > 0, clusters.count > targetCount else {
            return clusters
        }

        let totalCharacters = max(clusters.reduce(0) { $0 + max($1.text.count, 1) }, targetCount)
        var result: [ParagraphCluster] = []
        var cursor = 0
        var consumedCharacters = 0

        for groupIndex in 0..<targetCount {
            let remainingGroups = targetCount - groupIndex
            let remainingClusters = clusters.count - cursor
            let minimumClustersForThisGroup = max(1, remainingClusters - remainingGroups + 1)
            let targetCharacters = totalCharacters * (groupIndex + 1) / targetCount
            var group: [ParagraphCluster] = []

            repeat {
                let cluster = clusters[cursor]
                group.append(cluster)
                consumedCharacters += max(cluster.text.count, 1)
                cursor += 1
            } while cursor < clusters.count &&
                group.count < minimumClustersForThisGroup &&
                consumedCharacters < targetCharacters

            result.append(mergeParagraphClusterGroup(group))
        }

        return result
    }

    private func mergedParagraphs(_ paragraphs: [String], targetCount: Int) -> [String] {
        guard targetCount > 0, paragraphs.count > targetCount else {
            return paragraphs
        }

        let totalCharacters = max(paragraphs.reduce(0) { $0 + max($1.count, 1) }, targetCount)
        var result: [String] = []
        var cursor = 0
        var consumedCharacters = 0

        for groupIndex in 0..<targetCount {
            let remainingGroups = targetCount - groupIndex
            let remainingParagraphs = paragraphs.count - cursor
            let minimumParagraphsForThisGroup = max(1, remainingParagraphs - remainingGroups + 1)
            let targetCharacters = totalCharacters * (groupIndex + 1) / targetCount
            var group: [String] = []

            repeat {
                let paragraph = paragraphs[cursor]
                group.append(paragraph)
                consumedCharacters += max(paragraph.count, 1)
                cursor += 1
            } while cursor < paragraphs.count &&
                group.count < minimumParagraphsForThisGroup &&
                consumedCharacters < targetCharacters

            result.append(group.joined(separator: "\n\n"))
        }

        return result
    }

    private func mergeParagraphClusterGroup(_ group: [ParagraphCluster]) -> ParagraphCluster {
        guard var bounds = group.first?.bounds else {
            return ParagraphCluster(text: "", bounds: .zero, role: .paragraph)
        }

        for cluster in group.dropFirst() {
            bounds = bounds.union(cluster.bounds)
        }

        let role = group.first(where: { $0.role != .paragraph })?.role ?? .paragraph
        return ParagraphCluster(
            text: group.map(\.text).joined(separator: " "),
            bounds: bounds,
            role: role
        )
    }

    private func recordProjectUsage(_ usage: AIUsage?) throws {
        guard let currentTranslationProject,
              let updatedProject = try translationProjectStore.recordUsage(usage, projectID: currentTranslationProject.id) else {
            return
        }

        self.currentTranslationProject = updatedProject
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
        let clusters = sourceParagraphClusters(for: page)
        let blocks = clusters.enumerated().compactMap { index, cluster -> TranslatedTextBlock? in
            guard !cluster.text.isEmpty else {
                return nil
            }

            let bbox = imageBoundingBox(
                from: cluster.bounds,
                pageBounds: pageBounds,
                scale: renderedPage.scale
            )

            return TranslatedTextBlock(
                id: "mock_pdf_text_\(index)",
                sourceText: cluster.text,
                translatedText: mockPersianText(for: cluster.text, role: cluster.role),
                bbox: bbox,
                role: cluster.role,
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
        let sortedWidths = sortedLines.map(\.rect.width).sorted()
        let referenceLineWidth = sortedWidths[min(sortedWidths.count * 3 / 4, sortedWidths.count - 1)]
        let sortedGaps = zip(sortedLines, sortedLines.dropFirst())
            .map { max(0, $0.rect.minY - $1.rect.maxY) }
            .filter { $0 > 0 }
            .sorted()
        let medianLineGap = sortedGaps.isEmpty ? medianLineHeight * 0.25 : sortedGaps[sortedGaps.count / 2]
        let verticalSplitThreshold = max(medianLineHeight * 0.85, medianLineGap * 1.9, 8)
        let leftEdge = sortedLines.map(\.rect.minX).sorted()[sortedLines.count / 4]
        let indentThreshold = max(medianLineHeight * 0.75, 9)

        var clusters: [[TextLine]] = []
        var currentCluster: [TextLine] = []
        var previousLine: TextLine?

        for line in sortedLines {
            let verticalGap = previousLine.map { $0.rect.minY - line.rect.maxY } ?? 0
            let startsIndented = line.rect.minX > leftEdge + indentThreshold
            let previousEndsParagraph = previousLine.map { lineLooksLikeParagraphEnd($0.text) } ?? false
            let previousIsShortTerminalLine = previousLine.map {
                previousEndsParagraph && $0.rect.width < referenceLineWidth * 0.78
            } ?? false
            let startsNearBodyEdge = abs(line.rect.minX - leftEdge) <= indentThreshold * 1.4
            let shouldStartByIndent = !currentCluster.isEmpty &&
                startsIndented &&
                (previousEndsParagraph || verticalGap > medianLineHeight * 0.2)
            let shouldStartAfterShortTerminalLine = !currentCluster.isEmpty &&
                previousIsShortTerminalLine &&
                startsNearBodyEdge &&
                verticalGap >= -2
            let shouldStartByGap = !currentCluster.isEmpty && verticalGap > verticalSplitThreshold

            if shouldStartByGap || shouldStartByIndent || shouldStartAfterShortTerminalLine {
                clusters.append(currentCluster)
                currentCluster = [line]
            } else {
                currentCluster.append(line)
            }
            previousLine = line
        }

        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        return clusters
    }

    private func lineLooksLikeParagraphEnd(_ text: String) -> Bool {
        guard let lastCharacter = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }

        return ".!?;:)]}”’\"".contains(lastCharacter)
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
        let isNearBottom = bounds.midY < pageBounds.minY + pageBounds.height * 0.08
        let isShortSingleLine = lines.count == 1 && wordCount <= 10
        let lineHeight = lines.map(\.rect.height).max() ?? bounds.height

        if isNearBottom, lines.count == 1, wordCount <= 3 {
            return .pageNumber
        }

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
