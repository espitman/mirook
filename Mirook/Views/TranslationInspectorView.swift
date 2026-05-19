import SwiftUI

struct TranslationInspectorView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore

    var body: some View {
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
            } label: {
                Label("Translate Current Page", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(documentStore.document == nil)

            Spacer()
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
