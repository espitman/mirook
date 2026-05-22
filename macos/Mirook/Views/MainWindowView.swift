import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore

    var body: some View {
        ZStack {
            FullSizeWindowOnOpen()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            PageKeyboardNavigationHandler(
                isEnabled: documentStore.hasOpenDocument &&
                    documentStore.bookPasswordDialog == nil &&
                    documentStore.lastErrorMessage == nil,
                exitsOnEscape: documentStore.isReadingMode,
                onPrevious: {
                    documentStore.goToPreviousPage()
                },
                onNext: {
                    documentStore.goToNextPage()
                },
                onExit: {
                    documentStore.isReadingMode = false
                }
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)

            if documentStore.isReadingMode, documentStore.hasOpenDocument {
                ReadingModeView()
            } else {
                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: 280)
                        .background(MirookTheme.sidebarBackground)

                    Rectangle()
                        .fill(MirookTheme.separator)
                        .frame(width: 1)

                    ReaderView()
                        .frame(minWidth: 560)

                    Rectangle()
                        .fill(MirookTheme.separator)
                        .frame(width: 1)

                    TranslationInspectorView()
                        .frame(width: 360)
                }
            }

            FileDropOverlay { url in
                documentStore.openDroppedDocument(from: url)
            }

            if let dialog = documentStore.bookPasswordDialog {
                BookPasswordDialogView(
                    dialog: dialog,
                    errorMessage: documentStore.bookPasswordDialogErrorMessage,
                    onSubmit: { currentPassword, newPassword, confirmPassword in
                        documentStore.submitBookPasswordDialog(
                            currentPassword: currentPassword,
                            newPassword: newPassword,
                            confirmPassword: confirmPassword
                        )
                    },
                    onCancel: {
                        documentStore.cancelBookPasswordDialog()
                    }
                )
                .zIndex(10)
            }
        }
        .background(MirookTheme.appBackground)
        .preferredColorScheme(.light)
        .frame(minWidth: 1120, minHeight: 720)
        .onDrop(of: supportedDropTypes, isTargeted: nil, perform: openDroppedDocuments)
        .alert("Unable to Open Book", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                documentStore.lastErrorMessage = nil
            }
        } message: {
            Text(documentStore.lastErrorMessage ?? "Unknown error.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { documentStore.lastErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    documentStore.lastErrorMessage = nil
                }
            }
        )
    }

    private var supportedDropTypes: [String] {
        var types = [UTType.pdf.identifier]
        if let epubType = UTType(filenameExtension: "epub") {
            types.append(epubType.identifier)
        }
        if let mirookBookType = UTType(filenameExtension: "mrbk") {
            types.append(mirookBookType.identifier)
        }
        types.append(UTType.fileURL.identifier)
        return types
    }

    private func openDroppedDocuments(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let droppedURL = item as? URL {
                    url = droppedURL
                } else if let path = item as? String {
                    url = URL(string: path)
                } else {
                    url = nil
                }

                guard let url else { return }

                Task { @MainActor in
                    documentStore.openDroppedDocument(from: url)
                }
            }

            return true
        }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                guard let url else { return }

                Task { @MainActor in
                    documentStore.openDroppedDocument(from: url)
                }
            }

            return true
        }

        if let epubType = UTType(filenameExtension: "epub") {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(epubType.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: epubType.identifier) { url, _ in
                    guard let url else { return }

                    Task { @MainActor in
                        documentStore.openDroppedDocument(from: url)
                    }
                }

                return true
            }
        }

        return false
    }
}

private struct FullSizeWindowOnOpen: NSViewRepresentable {
    func makeNSView(context: Context) -> FullSizeWindowView {
        FullSizeWindowView()
    }

    func updateNSView(_ view: FullSizeWindowView, context: Context) {
        view.sizeWindowIfNeeded()
    }
}

private final class FullSizeWindowView: NSView {
    private var didSizeWindow = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        sizeWindowIfNeeded()
    }

    func sizeWindowIfNeeded() {
        guard !didSizeWindow else { return }

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                !self.didSizeWindow,
                let window = self.window,
                let frame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            else {
                return
            }

            self.didSizeWindow = true
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

private struct BookPasswordDialogView: View {
    let dialog: BookPasswordDialog
    let errorMessage: String?
    let onSubmit: (String, String, String) -> Void
    let onCancel: () -> Void

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case current
        case new
        case confirm
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("MirookLogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .frame(width: 82, height: 82)
                    .background(MirookTheme.readerBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(MirookTheme.border, lineWidth: 1)
                    }

                VStack(spacing: 6) {
                    Text(dialog.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MirookTheme.ink)

                    Text(dialog.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MirookTheme.mutedInk)
                        .lineLimit(1)

                    Text(dialog.message)
                        .font(.subheadline)
                        .foregroundStyle(MirookTheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    if dialog.needsCurrentPassword {
                        passwordField(
                            title: dialog.mode == .unlock ? "Password" : "Current password",
                            text: $currentPassword,
                            focus: .current
                        )
                    }

                    if dialog.needsNewPassword {
                        passwordField(title: "New password", text: $newPassword, focus: .new)
                        passwordField(title: "Confirm password", text: $confirmPassword, focus: .confirm)
                    }
                }

                if let errorMessage {
                    errorBanner(errorMessage)
                }

                actionButtons
            }
            .padding(22)
            .frame(width: 420)
            .background(MirookTheme.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.75), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 28, y: 16)
        }
        .onAppear {
            focusedField = dialog.needsCurrentPassword ? .current : .new
        }
        .onChange(of: dialog.id) {
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            focusedField = dialog.needsCurrentPassword ? .current : .new
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(MirookSecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)
            .frame(maxWidth: .infinity)

            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if dialog.isDestructive {
            Button(dialog.primaryButtonTitle) {
                submit()
            }
            .buttonStyle(MirookDestructiveButtonStyle())
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity)
        } else {
            Button(dialog.primaryButtonTitle) {
                submit()
            }
            .buttonStyle(MirookPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity)
        }
    }

    private func passwordField(title: String, text: Binding<String>, focus: Field) -> some View {
        SecureField(title, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(MirookTheme.ink)
            .focused($focusedField, equals: focus)
            .onSubmit(submit)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(MirookTheme.controlFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(focusedField == focus ? MirookTheme.ink.opacity(0.45) : MirookTheme.border, lineWidth: 1)
            }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.circle")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color(red: 0.74, green: 0.15, blue: 0.12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 1.0, green: 0.92, blue: 0.89))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func submit() {
        onSubmit(currentPassword, newPassword, confirmPassword)
    }
}

private struct MirookDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : MirookTheme.faintInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isEnabled ? Color(red: 0.70, green: 0.12, blue: 0.10) : MirookTheme.disabledFill)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.24 : 0.10), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct FileDropOverlay: NSViewRepresentable {
    let onOpen: @MainActor (URL) -> Void

    func makeNSView(context: Context) -> MirookDropCatchingView {
        let view = MirookDropCatchingView()
        view.onOpen = { url in
            Task { @MainActor in
                onOpen(url)
            }
        }
        return view
    }

    func updateNSView(_ view: MirookDropCatchingView, context: Context) {
        view.onOpen = { url in
            Task { @MainActor in
                onOpen(url)
            }
        }
    }
}

final class MirookDropCatchingView: NSView {
    var onOpen: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(MirookDropSupport.pasteboardTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(MirookDropSupport.pasteboardTypes)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
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

        onOpen?(url)
        return true
    }
}

enum MirookDropSupport {
    static let pasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        NSPasteboard.PasteboardType(UTType.pdf.identifier),
        NSPasteboard.PasteboardType(UTType(filenameExtension: "epub")?.identifier ?? "org.idpf.epub-container")
    ]

    static func acceptableFileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           let url = urls.first(where: isSupportedDocumentURL) {
            return url
        }

        for type in [NSPasteboard.PasteboardType.fileURL, .URL] {
            if let string = pasteboard.string(forType: type),
               let url = URL(string: string),
               isSupportedDocumentURL(url) {
                return url
            }
        }

        if let data = pasteboard.data(forType: .fileURL),
           let url = URL(dataRepresentation: data, relativeTo: nil),
           isSupportedDocumentURL(url) {
            return url
        }

        return nil
    }

    private static func isSupportedDocumentURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "pdf", "epub", "mrbk", "mirookbook":
            return true
        default:
            return false
        }
    }
}

private struct ReadingModeView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore
    @AppStorage("readingModeTranslationFontSize") private var readingModeTranslationFontSize = 22.0

    private static let translationFontSizeRange: ClosedRange<Double> = 14...38

    private var translatedTextPage: TranslatedTextPage? {
        documentStore.translatedTextPagesByIndex[documentStore.currentPageIndex]
    }

    private var pageNumberBinding: Binding<Int> {
        Binding {
            max(documentStore.currentPageNumber, 1)
        } set: { newValue in
            documentStore.goToPage(number: newValue)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Rectangle()
                .fill(MirookTheme.separator)
                .frame(height: 1)

            HStack(spacing: 0) {
                originalPane

                Rectangle()
                    .fill(MirookTheme.separator)
                    .frame(width: 1)

                translationPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MirookTheme.readerBackground)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                documentStore.isReadingMode = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(MirookIconButtonStyle())
            .help("Exit reading mode")

            VStack(alignment: .leading, spacing: 2) {
                Text("Reading Mode")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MirookTheme.ink)
                Text(documentStore.displayName)
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
                    .lineLimit(1)
            }
            .frame(width: 260, alignment: .leading)

            Spacer(minLength: 8)

            Button {
                documentStore.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(MirookIconButtonStyle())
            .help("Previous source page")
            .disabled(documentStore.currentPageIndex == 0)

            Button {
                documentStore.goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(MirookIconButtonStyle())
            .help("Next source page")
            .disabled(documentStore.currentPageIndex + 1 >= documentStore.pageCount)

            HStack(spacing: 6) {
                MirookNumberField(
                    placeholder: "Page",
                    value: pageNumberBinding,
                    range: 1...max(documentStore.pageCount, 1)
                )
                    .frame(width: 54)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(MirookTheme.controlFill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(MirookTheme.border, lineWidth: 1)
                    }

                Text("of \(max(documentStore.pageCount, 1))")
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
            }

            Spacer(minLength: 8)

            Button {
                documentStore.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(MirookIconButtonStyle())
            .help("Zoom out")

            Button {
                documentStore.resetZoom()
            } label: {
                Text("\(Int(documentStore.zoomScale * 100))%")
                    .monospacedDigit()
                    .frame(width: 48)
            }
            .buttonStyle(MirookSecondaryButtonStyle())
            .help("Reset zoom")

            Button {
                documentStore.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(MirookIconButtonStyle())
            .help("Zoom in")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MirookTheme.panelBackground)
    }

    private var originalPane: some View {
        VStack(spacing: 0) {
            paneHeader(title: "Original", detail: "Page \(documentStore.currentPageNumber)")

            if let document = documentStore.document {
                PDFKitView(
                    document: document,
                    currentPageIndex: $documentStore.currentPageIndex,
                    zoomScale: $documentStore.zoomScale,
                    translatedTextPagesByIndex: documentStore.translatedTextPagesByIndex,
                    allowsTranslationPopover: false,
                    resetsScrollOnPageChange: true,
                    onFileDropped: { url in
                        documentStore.openDroppedDocument(from: url)
                    }
                )
            } else if documentStore.epubDocument != nil {
                EPUBSourceView(
                    page: documentStore.currentEPUBPage,
                    onLinkTapped: documentStore.openEPUBLink
                )
            } else {
                EmptyReaderState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var translationPane: some View {
        VStack(spacing: 0) {
            translationHeader

            Group {
                if let translatedTextPage {
                    if translatedTextPage.isBlank {
                        blankTranslationState
                    } else {
                        translatedContentView(translatedTextPage)
                    }
                } else {
                    missingTranslationState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MirookTheme.paperBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var translationHeader: some View {
        HStack(spacing: 8) {
            Text("Translation")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MirookTheme.ink)

            HStack(spacing: 5) {
                Button {
                    adjustTranslationFontSize(by: -1)
                } label: {
                    Text("A-")
                        .frame(width: 18)
                }
                .buttonStyle(MirookIconButtonStyle())
                .help("Make translation text smaller")
                .disabled(readingModeTranslationFontSize <= Self.translationFontSizeRange.lowerBound)

                Text("\(Int(readingModeTranslationFontSize))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(MirookTheme.mutedInk)
                    .frame(width: 24)

                Button {
                    adjustTranslationFontSize(by: 1)
                } label: {
                    Text("A+")
                        .frame(width: 18)
                }
                .buttonStyle(MirookIconButtonStyle())
                .help("Make translation text larger")
                .disabled(readingModeTranslationFontSize >= Self.translationFontSizeRange.upperBound)
            }

            Spacer()

            Text(translationStatusText)
                .font(.caption)
                .foregroundStyle(MirookTheme.mutedInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MirookTheme.panelBackground)
    }

    private var translationStatusText: String {
        guard let translatedTextPage else {
            return "Page \(documentStore.currentPageNumber), not translated"
        }

        if translatedTextPage.isBlank {
            return "Page \(translatedTextPage.pageNumber), blank"
        }

        return "Page \(translatedTextPage.pageNumber)"
    }

    private func paneHeader(title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MirookTheme.ink)

            Spacer()

            Text(detail)
                .font(.caption)
                .foregroundStyle(MirookTheme.mutedInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MirookTheme.panelBackground)
    }

    @ViewBuilder
    private func translatedContentView(_ page: TranslatedTextPage) -> some View {
        if let sourcePage = documentStore.currentEPUBPage {
            ReadingModeEPUBTranslationView(
                page: page,
                sourcePage: sourcePage,
                fontSize: CGFloat(readingModeTranslationFontSize),
                onLinkTapped: documentStore.openEPUBLink
            )
        } else {
            ReadingModeRTLTextView(
                text: normalizedReadingText(page.translatedText),
                fontSize: CGFloat(readingModeTranslationFontSize)
            )
        }
    }

    private func normalizedReadingText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func adjustTranslationFontSize(by delta: Double) {
        readingModeTranslationFontSize = min(
            max(readingModeTranslationFontSize + delta, Self.translationFontSizeRange.lowerBound),
            Self.translationFontSizeRange.upperBound
        )
    }

    private var missingTranslationState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.page.slash")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(MirookTheme.faintInk)
            Text("No translation for this source page yet.")
                .font(.headline)
                .foregroundStyle(MirookTheme.ink)
            Text("Translate this page from the normal workspace to read it here.")
                .font(.subheadline)
                .foregroundStyle(MirookTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var blankTranslationState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(MirookTheme.faintInk)
            Text("Blank page")
                .font(.headline)
                .foregroundStyle(MirookTheme.ink)
            Text("This source page is preserved as blank in the translated book.")
                .font(.subheadline)
                .foregroundStyle(MirookTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct ReadingModeRTLTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.alignment = .right
        textView.baseWritingDirection = .rightToLeft
        textView.textContainerInset = NSSize(width: 42, height: 46)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        let shouldResetScroll = context.coordinator.lastText != text
        let visibleOrigin = scrollView.contentView.bounds.origin
        let selectedRange = textView.selectedRange()

        textView.textStorage?.setAttributedString(Self.attributedString(text: text, fontSize: fontSize))
        textView.alignment = .right
        textView.baseWritingDirection = .rightToLeft
        textView.setBaseWritingDirection(.rightToLeft, range: NSRange(location: 0, length: (text as NSString).length))

        let textLength = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(selectedRange.location, textLength), length: 0))

        if shouldResetScroll {
            DispatchQueue.main.async {
                textView.layoutSubtreeIfNeeded()
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        } else {
            scrollView.contentView.scroll(to: visibleOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        context.coordinator.lastText = text
    }

    private static func attributedString(text: String, fontSize: CGFloat) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 4

        return NSAttributedString(
            string: text,
            attributes: [
                .font: MirookFontRegistrar.vazirmatnRegular(size: fontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    @MainActor
    final class Coordinator {
        var lastText = ""
    }
}

private struct ReadingModeRTLParagraphView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    var foregroundColor: NSColor = .labelColor
    var isUnderlined = false

    func makeNSView(context: Context) -> AutoSizingRTLTextView {
        let view = AutoSizingRTLTextView()
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: AutoSizingRTLTextView, context: Context) {
        view.attributedText = Self.attributedString(
            text: text,
            fontSize: fontSize,
            foregroundColor: foregroundColor,
            isUnderlined: isUnderlined
        )
    }

    private static func attributedString(
        text: String,
        fontSize: CGFloat,
        foregroundColor: NSColor,
        isUnderlined: Bool
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 0

        var attributes: [NSAttributedString.Key: Any] = [
            .font: MirookFontRegistrar.vazirmatnRegular(size: fontSize),
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle
        ]
        if isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        return NSAttributedString(string: text, attributes: attributes)
    }

    final class AutoSizingRTLTextView: NSView {
        private let textView = NSTextView()

        var attributedText: NSAttributedString = NSAttributedString(string: "") {
            didSet {
                textView.textStorage?.setAttributedString(attributedText)
                textView.setBaseWritingDirection(.rightToLeft, range: NSRange(location: 0, length: attributedText.length))
                invalidateIntrinsicContentSize()
                needsLayout = true
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        private func setup() {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = true
            textView.importsGraphics = false
            textView.drawsBackground = false
            textView.textContainerInset = .zero
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.heightTracksTextView = false
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.alignment = .right
            textView.baseWritingDirection = .rightToLeft
            addSubview(textView)
        }

        override func layout() {
            super.layout()
            textView.frame = bounds
            textView.textContainer?.containerSize = CGSize(width: max(bounds.width, 1), height: .greatestFiniteMagnitude)
            invalidateIntrinsicContentSize()
        }

        override var intrinsicContentSize: NSSize {
            let width = max(bounds.width, 1)
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return NSSize(width: NSView.noIntrinsicMetric, height: 0)
            }

            textContainer.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height))
        }
    }
}

private struct PageKeyboardNavigationHandler: NSViewRepresentable {
    let isEnabled: Bool
    let exitsOnEscape: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onExit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            exitsOnEscape: exitsOnEscape,
            onPrevious: onPrevious,
            onNext: onNext,
            onExit: onExit
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.exitsOnEscape = exitsOnEscape
        context.coordinator.onPrevious = onPrevious
        context.coordinator.onNext = onNext
        context.coordinator.onExit = onExit
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isEnabled: Bool
        var exitsOnEscape: Bool
        var onPrevious: () -> Void
        var onNext: () -> Void
        var onExit: () -> Void
        private var monitor: Any?

        init(
            isEnabled: Bool,
            exitsOnEscape: Bool,
            onPrevious: @escaping () -> Void,
            onNext: @escaping () -> Void,
            onExit: @escaping () -> Void
        ) {
            self.isEnabled = isEnabled
            self.exitsOnEscape = exitsOnEscape
            self.onPrevious = onPrevious
            self.onNext = onNext
            self.onExit = onExit
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.isEnabled,
                      event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                      !Self.isEditingTextInput() else {
                    return event
                }

                switch event.keyCode {
                case 53:
                    guard self.exitsOnEscape else {
                        return event
                    }
                    self.onExit()
                    return nil
                case 123:
                    self.onPrevious()
                    return nil
                case 124:
                    self.onNext()
                    return nil
                default:
                    return event
                }
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            removeMonitor()
        }

        @MainActor
        private static func isEditingTextInput() -> Bool {
            guard let firstResponder = NSApp.keyWindow?.firstResponder else {
                return false
            }

            if let textView = firstResponder as? NSTextView {
                return textView.isEditable
            }

            if firstResponder is NSTextField {
                return true
            }

            return false
        }
    }
}

private struct ReadingModeEPUBTranslationView: View {
    let page: TranslatedTextPage
    let sourcePage: EPUBSourcePage
    let fontSize: CGFloat
    let onLinkTapped: (EPUBSourceLink) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .trailing, spacing: 14) {
                Color.clear
                    .frame(height: 0)
                    .id("translation-top")

                ForEach(Array(renderedBlocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 46)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .id(sourcePage.id)
        .background(MirookTheme.paperBackground)
    }

    private var renderedBlocks: [RenderedBlock] {
        var paragraphs = normalizedParagraphs(page.translatedText)
        var blocks: [RenderedBlock] = []
        var previousSourceText = ""

        for sourceBlock in displayBlocks(from: sourcePage.blocks) {
            switch sourceBlock {
            case let .text(sourceText):
                guard !paragraphs.isEmpty else { continue }
                blocks.append(.text(paragraphs.removeFirst()))
                previousSourceText = sourceText
            case let .link(link):
                guard !paragraphs.isEmpty else { continue }
                blocks.append(.link(text: paragraphs.removeFirst(), link: link))
                previousSourceText = link.title
            case let .image(image):
                if let nextParagraph = paragraphs.first,
                   shouldPlaceBeforeImage(nextParagraph, previousSourceText: previousSourceText) {
                    blocks.append(.text(paragraphs.removeFirst()))
                }
                blocks.append(.image(image))
            }
        }

        for paragraph in paragraphs {
            blocks.append(.text(paragraph))
        }

        return blocks
    }

    private func shouldPlaceBeforeImage(_ translatedParagraph: String, previousSourceText: String) -> Bool {
        let translated = translatedParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = previousSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty, !source.isEmpty else {
            return false
        }

        let sourceMentionsFigure = source.range(of: #"(?i)\b(fig\.?|figure|illustration)\b"#, options: .regularExpression) != nil
        let translationMentionsFigure = translated.contains("شکل") ||
            translated.range(of: #"(?i)\bfig\.?|figure\b"#, options: .regularExpression) != nil
        return sourceMentionsFigure && translationMentionsFigure
    }

    private func displayBlocks(from blocks: [EPUBSourceBlock]) -> [EPUBSourceBlock] {
        var result: [EPUBSourceBlock] = []
        var index = 0

        while index < blocks.count {
            guard case let .text(text) = blocks[index] else {
                result.append(blocks[index])
                index += 1
                continue
            }

            var mergedText = text
            var nextIndex = index + 1
            while nextIndex < blocks.count,
                  case let .text(nextText) = blocks[nextIndex],
                  shouldMergeTextFragment(current: mergedText, next: nextText) {
                mergedText += "\n" + nextText
                nextIndex += 1
            }

            result.append(.text(mergedText))
            index = nextIndex
        }

        return result
    }

    private func shouldMergeTextFragment(current: String, next: String) -> Bool {
        if shouldMergeTitleFragment(current: current, next: next) {
            return true
        }

        let currentTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTrimmed.isEmpty, !nextTrimmed.isEmpty else {
            return false
        }
        guard !endsSentence(currentTrimmed),
              !isHeadingLike(currentTrimmed),
              !startsNewListItem(nextTrimmed) else {
            return false
        }

        return currentTrimmed.count >= 45 || startsWithContinuation(nextTrimmed)
    }

    private func shouldMergeTitleFragment(current: String, next: String) -> Bool {
        let currentTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentTrimmed.count <= 90,
              nextTrimmed.count <= 60 else {
            return false
        }

        return isTitleLike(currentTrimmed) && isTitleLike(nextTrimmed)
    }

    private func isTitleLike(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        let uppercaseLetters = letters.filter(\.isUppercase)
        if Double(uppercaseLetters.count) / Double(letters.count) >= 0.75 {
            return true
        }

        return text.range(of: #"(?i)^\s*(chapter|part|section)\b"#, options: .regularExpression) != nil
    }

    private func isHeadingLike(_ text: String) -> Bool {
        guard text.count <= 72,
              !endsSentence(text),
              !startsNewListItem(text) else {
            return false
        }

        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return wordCount <= 8
    }

    private func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return ".!?:;،؛؟。)»”]".contains(last)
    }

    private func startsNewListItem(_ text: String) -> Bool {
        text.range(of: #"^\s*(?:[\u{2022}\-*•]|\d+[\.\)])\s+"#, options: .regularExpression) != nil
    }

    private func startsWithContinuation(_ text: String) -> Bool {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return false
        }
        return first.isLowercase || "،؛:;)]}»”".contains(first)
    }

    @ViewBuilder
    private func blockView(_ block: RenderedBlock) -> some View {
        switch block {
        case let .text(text):
            ReadingModeRTLParagraphView(
                text: text,
                fontSize: fontSize
            )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
        case let .link(text, link):
            Button {
                onLinkTapped(link)
            } label: {
                ReadingModeRTLParagraphView(
                    text: text,
                    fontSize: fontSize,
                    foregroundColor: .systemBlue,
                    isUnderlined: true
                )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                if isHovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .help(link.url.absoluteString)
        case let .image(image):
            if let nsImage = NSImage(data: image.data) {
                VStack(spacing: 8) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)

                    if let altText = image.altText {
                        Text(altText)
                            .font(.caption)
                            .foregroundStyle(MirookTheme.mutedInk)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 8)
            } else if let altText = image.altText {
                Text(altText)
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func normalizedParagraphs(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private enum RenderedBlock {
        case text(String)
        case link(text: String, link: EPUBSourceLink)
        case image(EPUBSourceImage)
    }
}
