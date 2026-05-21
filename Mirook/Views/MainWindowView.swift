import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore

    var body: some View {
        Group {
            if documentStore.isReadingMode, documentStore.document != nil {
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
        }
        .background(MirookTheme.appBackground)
        .preferredColorScheme(.light)
        .frame(minWidth: 1120, minHeight: 720)
        .alert("Unable to Open PDF", isPresented: errorBinding) {
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
                    allowsTranslationPopover: false
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
                        translatedTextView(translatedTextPage.translatedText)
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

    private func translatedTextView(_ text: String) -> some View {
        ReadingModeRTLTextView(
            text: text,
            fontSize: CGFloat(readingModeTranslationFontSize)
        )
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
            scrollView.contentView.scroll(to: .zero)
        } else {
            scrollView.contentView.scroll(to: visibleOrigin)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)

        context.coordinator.lastText = text
    }

    private static func attributedString(text: String, fontSize: CGFloat) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 8
        paragraphStyle.paragraphSpacing = 10

        return NSAttributedString(
            string: text,
            attributes: [
                .font: MirookFontRegistrar.vazirmatnRegular(size: fontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    final class Coordinator {
        var lastText = ""
    }
}
