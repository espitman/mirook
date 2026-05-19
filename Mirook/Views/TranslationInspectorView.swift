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
}
