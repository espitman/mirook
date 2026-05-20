import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore
    @AppStorage("defaultModelName") private var defaultModelName = "gpt-5.2"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mirook")
                    .font(.title2.weight(.semibold))
                Text("PDF translation workspace")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                openPDF()
            } label: {
                Label("Open PDF", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)

            modelControls

            if documentStore.document != nil {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Document")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(documentStore.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(documentStore.pageCount) pages")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private var modelControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Model")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("AI Model", selection: $defaultModelName) {
                    if !documentStore.availableAIModels.contains(where: { $0.id == defaultModelName }) {
                        Text(defaultModelName).tag(defaultModelName)
                    }

                    ForEach(documentStore.availableAIModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .disabled(documentStore.isLoadingAIModels)

                Button {
                    Task {
                        await documentStore.loadAvailableAIModels()
                    }
                } label: {
                    if documentStore.isLoadingAIModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(documentStore.isLoadingAIModels)
                .help("Load models from the configured AI provider")
            }

            if documentStore.availableAIModels.isEmpty {
                Text("Refresh to load models from Liara or the configured provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            documentStore.openPDF(from: url)
        }
    }
}
