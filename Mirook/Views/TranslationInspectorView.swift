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
                } label: {
                    Label("Translate Current Page", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(documentStore.document == nil)
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
}
