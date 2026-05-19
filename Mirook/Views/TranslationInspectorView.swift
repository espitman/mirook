import SwiftUI

struct TranslationInspectorView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Translation")
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Source") {
                        Text("Auto")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Target") {
                        Text("Persian")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Layout") {
                        Text("Mirror")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Page Range")
                        .font(.headline)

                    if documentStore.document == nil {
                        Text("Open a PDF to choose pages.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Current page: \(documentStore.currentPageNumber)")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    documentStore.renderCurrentPage()
                } label: {
                    Label("Render Current Page", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(documentStore.document == nil || documentStore.isRenderingPage)

                renderPreview

                Button {
                    Task {
                        await documentStore.translateCurrentPage()
                    }
                } label: {
                    Label("Translate Current Page", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(documentStore.document == nil || documentStore.isTranslatingPage)

                translationPreview

                Button {
                    Task {
                        await documentStore.translateCurrentPageAsText()
                    }
                } label: {
                    Label("Translate Current Page Text", systemImage: "text.alignright")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(documentStore.document == nil || documentStore.isTranslatingTextPage)

                textTranslationPreview

                Button {
                    documentStore.renderTranslatedPreview()
                } label: {
                    Label(documentStore.translatedPage == nil ? "Build Mock Layout Preview" : "Build Translated Preview", systemImage: "doc.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(documentStore.document == nil || documentStore.isRenderingTranslatedPage)

                translatedPagePreview

                exportControls
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var renderPreview: some View {
        if documentStore.isRenderingPage {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Rendering page...")
                    .foregroundStyle(.secondary)
            }
        } else if let renderedPage = documentStore.renderedPage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rendered Page")
                    .font(.headline)

                if let image = renderedPage.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.separator, lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(renderedPage.pageNumber)")
                    Text("\(Int(renderedPage.width)) x \(Int(renderedPage.height)) px at \(renderedPage.scale.formatted())x")
                    Text(renderedPage.imageData.count.formatted(.byteCount(style: .file)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
        } else if let translatedPage = documentStore.translatedPage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Translated Blocks")
                    .font(.headline)

                Text("\(translatedPage.blocks.count) blocks detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(translatedPage.blocks.prefix(8)) { block in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(block.role.rawValue)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            if let confidence = block.confidence {
                                Text(confidence.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(block.sourceText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Text(block.translatedText)
                            .font(.body)
                            .lineLimit(3)
                    }
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    @ViewBuilder
    private var textTranslationPreview: some View {
        if documentStore.isTranslatingTextPage {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Translating text...")
                    .foregroundStyle(.secondary)
            }
        } else if let translatedTextPage = documentStore.translatedTextPage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Translated Text")
                    .font(.headline)

                Text(translatedTextPage.translatedText)
                    .font(.body)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Page \(translatedTextPage.pageNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var translatedPagePreview: some View {
        if documentStore.isRenderingTranslatedPage {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Building translated preview...")
                    .foregroundStyle(.secondary)
            }
        } else if let translatedRenderedPage = documentStore.translatedRenderedPage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Translated Page Preview")
                    .font(.headline)

                if documentStore.translatedPage?.blocks.first?.id.hasPrefix("mock_") == true {
                    Text("Mock preview uses local PDF text bounds. Real translation requires OpenAI output.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let image = translatedRenderedPage.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.separator, lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(translatedRenderedPage.pageNumber)")
                    Text("\(translatedRenderedPage.blockCount) translated blocks")
                    Text("\(Int(translatedRenderedPage.width)) x \(Int(translatedRenderedPage.height)) px")
                    Text(translatedRenderedPage.imageData.count.formatted(.byteCount(style: .file)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var exportControls: some View {
        if documentStore.document != nil {
            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Export")
                    .font(.headline)

                Button {
                    documentStore.exportTranslatedPDF()
                } label: {
                    Label("Export Translated PDF", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(documentStore.translatedExportPageCount == 0 || documentStore.isExportingPDF)

                Button {
                    documentStore.exportTextTranslatedPDF()
                } label: {
                    Label("Export Text PDF", systemImage: "doc.plaintext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(documentStore.translatedTextExportPageCount == 0 || documentStore.isExportingTextPDF)

                HStack(spacing: 6) {
                    Text("\(documentStore.translatedExportPageCount) pages ready")
                    if let url = documentStore.lastExportedPDFURL {
                        Text("Saved: \(url.lastPathComponent)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text("\(documentStore.translatedTextExportPageCount) text pages ready")
                    if let url = documentStore.lastExportedTextPDFURL {
                        Text("Saved: \(url.lastPathComponent)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
