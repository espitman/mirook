import AppKit
import SwiftUI

struct TranslationInspectorView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore
    @AppStorage("textPDFExportFont") private var textPDFExportFont = TextPDFExportFont.vazirmatn.rawValue
    @AppStorage("textPDFBodyFontSize") private var textPDFBodyFontSize = TextPDFExportOptions.default.bodyFontSize
    @AppStorage("textPDFLineSpacing") private var textPDFLineSpacing = TextPDFExportOptions.default.lineSpacing
    @AppStorage("textPDFParagraphSpacing") private var textPDFParagraphSpacing = TextPDFExportOptions.default.paragraphSpacing
    @AppStorage("textPDFMargin") private var textPDFMargin = TextPDFExportOptions.default.margin
    @AppStorage("translatedTextPreviewFontSize") private var translatedTextPreviewFontSize = 18.0
    @State private var showsTextPDFStyleControls = false
    @State private var showsAdvancedLayoutTools = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Translation")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MirookTheme.ink)

                pageRangeControls
                translationControls
                textTranslationPreview
                exportControls
                advancedLayoutTools
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 44)
        }
        .scrollContentBackground(.hidden)
        .background(MirookTheme.panelBackground)
    }

    private var selectedStartPage: Binding<Int> {
        Binding {
            documentStore.pageSelection.startPage
        } set: { newValue in
            documentStore.setPageSelection(
                startPage: newValue,
                endPage: documentStore.pageSelection.endPage
            )
        }
    }

    private var selectedEndPage: Binding<Int> {
        Binding {
            documentStore.pageSelection.endPage
        } set: { newValue in
            documentStore.setPageSelection(
                startPage: documentStore.pageSelection.startPage,
                endPage: newValue
            )
        }
    }

    private func pageNumberField(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MirookTheme.mutedInk)

            TextField(title, value: value, format: .number)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(MirookTheme.controlFill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(MirookTheme.border, lineWidth: 1)
                }
                .frame(width: 76)
        }
    }

    private var textPDFExportOptions: TextPDFExportOptions {
        TextPDFExportOptions(
            font: TextPDFExportFont(rawValue: textPDFExportFont) ?? .vazirmatn,
            bodyFontSize: textPDFBodyFontSize,
            lineSpacing: textPDFLineSpacing,
            paragraphSpacing: textPDFParagraphSpacing,
            margin: textPDFMargin
        )
    }

    @ViewBuilder
    private var pageRangeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pages")
                .font(.headline)
                .foregroundStyle(MirookTheme.ink)

            if documentStore.document == nil {
                Text("Open a PDF to choose pages.")
                    .foregroundStyle(MirookTheme.mutedInk)
            } else {
                HStack(spacing: 10) {
                    pageNumberField("From", value: selectedStartPage)
                    pageNumberField("To", value: selectedEndPage)
                }
                .disabled(documentStore.isTranslatingTextPage)

                HStack(spacing: 8) {
                    Button("Current") {
                        documentStore.selectCurrentPage()
                    }
                    .buttonStyle(MirookSecondaryButtonStyle())

                    Button("All") {
                        documentStore.selectAllPages()
                    }
                    .buttonStyle(MirookSecondaryButtonStyle())

                    Spacer()

                    Text("\(documentStore.selectedPageCount) selected")
                        .font(.caption)
                        .foregroundStyle(MirookTheme.mutedInk)
                }
                .disabled(documentStore.isTranslatingTextPage)
            }
        }
        .mirookPanel(padding: 14)
    }

    @ViewBuilder
    private var translationControls: some View {
        if documentStore.document != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Translate")
                    .font(.headline)
                    .foregroundStyle(MirookTheme.ink)

                Button {
                    Task {
                        await documentStore.translateMissingSelectedPagesAsText()
                    }
                } label: {
                    Label("Translate Selection", systemImage: "text.alignright")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MirookPrimaryButtonStyle())
                .disabled(
                    documentStore.isTranslatingTextPage ||
                    documentStore.selectedPageCount == 0 ||
                    documentStore.selectedMissingTextPageCount == 0
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(documentStore.translatedTextCoverageDescription)
                    if documentStore.selectedMissingTextPageCount > 0 {
                        Text("\(documentStore.selectedMissingTextPageCount) selected missing")
                    }
                }
                .font(.caption)
                .foregroundStyle(MirookTheme.mutedInk)

            }
            .mirookPanel(padding: 14)
        }
    }

    @ViewBuilder
    private var renderPreview: some View {
        if documentStore.isRenderingPage {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Rendering page...")
                    .foregroundStyle(MirookTheme.mutedInk)
            }
        } else if let renderedPage = documentStore.renderedPage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rendered Page")
                    .font(.headline)
                    .foregroundStyle(MirookTheme.ink)

                if let image = renderedPage.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(MirookTheme.border, lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(renderedPage.pageNumber)")
                    Text("\(Int(renderedPage.width)) x \(Int(renderedPage.height)) px at \(renderedPage.scale.formatted())x")
                    Text(renderedPage.imageData.count.formatted(.byteCount(style: .file)))
                }
                .font(.caption)
                .foregroundStyle(MirookTheme.mutedInk)
            }
        }
    }

    @ViewBuilder
    private var translationPreview: some View {
        if documentStore.isTranslatingPage {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Translating page...")
                    .foregroundStyle(MirookTheme.mutedInk)
            }
        } else if let translatedPage = documentStore.translatedPage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Translated Blocks")
                    .font(.headline)
                    .foregroundStyle(MirookTheme.ink)

                Text("\(translatedPage.blocks.count) blocks detected")
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)

                ForEach(translatedPage.blocks.prefix(8)) { block in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(block.role.rawValue)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            if let confidence = block.confidence {
                                Text(confidence.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption)
                                    .foregroundStyle(MirookTheme.mutedInk)
                            }
                        }

                        Text(block.sourceText)
                            .font(.caption)
                            .foregroundStyle(MirookTheme.mutedInk)
                            .lineLimit(2)

                        Text(block.translatedText)
                            .font(.body)
                            .lineLimit(3)
                    }
                    .padding(10)
                    .background(MirookTheme.paperBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    @ViewBuilder
    private var textTranslationPreview: some View {
        if documentStore.isTranslatingTextPage {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                Text(documentStore.textTranslationProgressDescription)
                        .foregroundStyle(MirookTheme.mutedInk)
                }

                if documentStore.textTranslationProgressTotal > 1 {
                    ProgressView(
                        value: Double(documentStore.textTranslationProgressCurrent),
                        total: Double(documentStore.textTranslationProgressTotal)
                    )
                }
            }
        } else if let translatedTextPage = documentStore.translatedTextPage {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(translatedTextPage.isBlank ? "Blank Page" : "Translated Text")
                        .font(.headline)
                        .foregroundStyle(MirookTheme.ink)

                    Spacer()

                    if !translatedTextPage.isBlank {
                        textPreviewFontControls
                    }
                }

                if translatedTextPage.isBlank {
                    Text("This page has no extractable text and will be exported as a blank page.")
                        .font(.caption)
                        .foregroundStyle(MirookTheme.mutedInk)
                } else {
                    RTLSelectableTextView(
                        text: translatedTextPage.translatedText,
                        fontSize: CGFloat(translatedTextPreviewFontSize)
                    )
                        .frame(minHeight: 180, idealHeight: 260, maxHeight: 360)
                        .background(MirookTheme.paperBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(MirookTheme.border, lineWidth: 1)
                        }
                }

                Text("Page \(translatedTextPage.pageNumber)")
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
            }
            .mirookPanel(padding: 14)
        }
    }

    private var textPreviewFontControls: some View {
        HStack(spacing: 6) {
            Button {
                translatedTextPreviewFontSize = max(12, translatedTextPreviewFontSize - 1)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(MirookIconButtonStyle())
            .disabled(translatedTextPreviewFontSize <= 12)
            .help("Smaller translated text")

            Text("\(Int(translatedTextPreviewFontSize))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(MirookTheme.mutedInk)
                .frame(minWidth: 24)

            Button {
                translatedTextPreviewFontSize = min(30, translatedTextPreviewFontSize + 1)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(MirookIconButtonStyle())
            .disabled(translatedTextPreviewFontSize >= 30)
            .help("Larger translated text")
        }
    }

    @ViewBuilder
    private var translatedPagePreview: some View {
        if documentStore.isRenderingTranslatedPage {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Building translated preview...")
                    .foregroundStyle(MirookTheme.mutedInk)
            }
        } else if let translatedRenderedPage = documentStore.translatedRenderedPage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Translated Page Preview")
                    .font(.headline)
                    .foregroundStyle(MirookTheme.ink)

                if documentStore.translatedPage?.blocks.first?.id.hasPrefix("mock_") == true {
                        Text("Mock preview uses local PDF text bounds. Real translation requires OpenAI output.")
                            .font(.caption)
                            .foregroundStyle(MirookTheme.mutedInk)
                }

                if let image = translatedRenderedPage.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(MirookTheme.border, lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(translatedRenderedPage.pageNumber)")
                    Text("\(translatedRenderedPage.blockCount) translated blocks")
                    Text("\(Int(translatedRenderedPage.width)) x \(Int(translatedRenderedPage.height)) px")
                    Text(translatedRenderedPage.imageData.count.formatted(.byteCount(style: .file)))
                }
                .font(.caption)
                .foregroundStyle(MirookTheme.mutedInk)
            }
        }
    }

    @ViewBuilder
    private var exportControls: some View {
        if documentStore.document != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Export")
                    .font(.headline)
                    .foregroundStyle(MirookTheme.ink)

                DisclosureGroup(isExpanded: $showsTextPDFStyleControls) {
                    textPDFStyleControls
                        .padding(.top, 6)
                } label: {
                    Label("PDF Style", systemImage: "textformat.size")
                        .foregroundStyle(MirookTheme.ink)
                }

                Button {
                    documentStore.exportCompleteTextBook(options: textPDFExportOptions)
                } label: {
                    Label("Export Complete Book", systemImage: "books.vertical")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MirookPrimaryButtonStyle())
                .disabled(!documentStore.canExportCompleteTextBook || documentStore.isExportingTextPDF)

                Button {
                    documentStore.exportTextTranslatedPDF(options: textPDFExportOptions)
                } label: {
                    Label("Export Ready Pages", systemImage: "doc.plaintext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MirookSecondaryButtonStyle())
                .disabled(documentStore.translatedTextExportPageCount == 0 || documentStore.isExportingTextPDF)

                VStack(alignment: .leading, spacing: 4) {
                    Text(documentStore.translatedTextCoverageDescription)
                    if let url = documentStore.lastExportedTextPDFURL {
                        Text("Saved: \(url.lastPathComponent)")
                    }
                }
                .font(.caption)
                .foregroundStyle(MirookTheme.mutedInk)

                if let projectPath = documentStore.currentTranslationProjectPath {
                    Text("Project: \(projectPath)")
                        .font(.caption2)
                        .foregroundStyle(MirookTheme.mutedInk)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .mirookPanel(padding: 14)
        }
    }

    @ViewBuilder
    private var advancedLayoutTools: some View {
        if documentStore.document != nil {
            DisclosureGroup(isExpanded: $showsAdvancedLayoutTools) {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        documentStore.renderCurrentPage()
                    } label: {
                        Label("Render Page Image", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MirookSecondaryButtonStyle())
                    .disabled(documentStore.isRenderingPage)

                    renderPreview

                    Button {
                        Task {
                            await documentStore.translateCurrentPage()
                        }
                    } label: {
                        Label("Translate Layout Page", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MirookSecondaryButtonStyle())
                    .disabled(documentStore.isTranslatingPage)

                    translationPreview

                    Button {
                        documentStore.renderTranslatedPreview()
                    } label: {
                        Label("Build Layout Preview", systemImage: "doc.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MirookSecondaryButtonStyle())
                    .disabled(documentStore.isRenderingTranslatedPage)

                    translatedPagePreview

                    Button {
                        documentStore.exportTranslatedPDF()
                    } label: {
                        Label("Export Layout PDF", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MirookSecondaryButtonStyle())
                    .disabled(documentStore.translatedExportPageCount == 0 || documentStore.isExportingPDF)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(documentStore.translatedExportPageCount) layout pages ready")
                        if let url = documentStore.lastExportedPDFURL {
                            Text("Saved: \(url.lastPathComponent)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
                }
                .padding(.top, 8)
            } label: {
                Label("Advanced Layout Tools", systemImage: "slider.horizontal.3")
                    .foregroundStyle(MirookTheme.ink)
            }
            .font(.body)
            .mirookPanel(padding: 14)
        }
    }

    private var textPDFStyleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Font", selection: $textPDFExportFont) {
                ForEach(TextPDFExportFont.allCases) { exportFont in
                    Text(exportFont.displayName).tag(exportFont.rawValue)
                }
            }

            Stepper("Size \(Int(textPDFBodyFontSize))", value: $textPDFBodyFontSize, in: 11...24, step: 1)
            Stepper("Line spacing \(Int(textPDFLineSpacing))", value: $textPDFLineSpacing, in: 2...14, step: 1)
            Stepper("Paragraph spacing \(Int(textPDFParagraphSpacing))", value: $textPDFParagraphSpacing, in: 6...28, step: 1)
            Stepper("Margin \(Int(textPDFMargin))", value: $textPDFMargin, in: 36...90, step: 2)
        }
    }
}

private struct RTLSelectableTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat

    private static func persianBodyFont(size: CGFloat) -> NSFont {
        MirookFontRegistrar.vazirmatnRegular(size: size)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = Self.persianBodyFont(size: fontSize)
        textView.textColor = .labelColor
        textView.alignment = .right
        textView.baseWritingDirection = .rightToLeft
        textView.textContainerInset = NSSize(width: 12, height: 12)
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

        if textView.string != text {
            textView.string = text
        }

        textView.font = Self.persianBodyFont(size: fontSize)
        textView.alignment = .right
        textView.baseWritingDirection = .rightToLeft
        textView.setBaseWritingDirection(.rightToLeft, range: NSRange(location: 0, length: textView.string.utf16.count))
    }
}
