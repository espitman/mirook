import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var documentStore: PDFDocumentStore
    @AppStorage("defaultModelName") private var defaultModelName = "gpt-5.2"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image("MirookLogoMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mirook")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(MirookTheme.ink)
                        Text("PDF translation workspace")
                            .font(.caption)
                            .foregroundStyle(MirookTheme.mutedInk)
                    }
                }

                Button {
                    openDocument()
                } label: {
                    Label("Open PDF / Book", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MirookPrimaryButtonStyle())

                modelControls

                if documentStore.document != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Document")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MirookTheme.mutedInk)
                        Text(documentStore.displayName)
                            .font(.headline)
                            .foregroundStyle(MirookTheme.ink)
                            .lineLimit(2)
                        Text("\(documentStore.pageCount) pages")
                            .font(.subheadline)
                            .foregroundStyle(MirookTheme.mutedInk)
                    }
                    .mirookPanel()

                    usageSummary
                    bookFileControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 22)
        }
        .scrollContentBackground(.hidden)
    }

    private var bookFileControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Book File")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MirookTheme.mutedInk)

            HStack(spacing: 8) {
                Button {
                    documentStore.revealCurrentBookFile()
                } label: {
                    Label("Reveal", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MirookSecondaryButtonStyle())

                if documentStore.isCurrentBookPasswordProtected {
                    Button {
                        documentStore.changeCurrentBookPassword()
                    } label: {
                        Image(systemName: "key")
                    }
                    .buttonStyle(MirookIconButtonStyle())
                    .help("Change password")

                    Button {
                        documentStore.removeCurrentBookPassword()
                    } label: {
                        Image(systemName: "lock.open")
                    }
                    .buttonStyle(MirookIconButtonStyle())
                    .help("Remove password")
                } else {
                    Button {
                        documentStore.setCurrentBookPassword()
                    } label: {
                        Image(systemName: "lock")
                    }
                    .buttonStyle(MirookIconButtonStyle())
                    .help("Set password")
                }
            }

            Text(documentStore.isCurrentBookPasswordProtected ? "Password protected" : "PDF embedded in .mrbk")
                .font(.caption)
                .foregroundStyle(MirookTheme.mutedInk)
        }
        .mirookPanel()
    }

    @ViewBuilder
    private var usageSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Usage")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MirookTheme.mutedInk)

            if let projectCost = documentStore.projectCostDescription {
                Text(projectCost)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MirookTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let projectTokens = documentStore.projectTokenDescription {
                    Text(projectTokens)
                        .font(.caption)
                        .foregroundStyle(MirookTheme.mutedInk)
                }
            } else {
                Text("Project cost will appear after Liara returns it.")
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lastCost = documentStore.lastTranslationCostDescription {
                Divider()
                    .padding(.vertical, 2)

                Text(lastCost)
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let lastTokens = documentStore.lastTranslationTokenDescription {
                    Text(lastTokens)
                        .font(.caption)
                        .foregroundStyle(MirookTheme.mutedInk)
                }
            }
        }
        .mirookPanel()
    }

    private var modelControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Model")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MirookTheme.mutedInk)

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
                .buttonStyle(MirookIconButtonStyle())
                .disabled(documentStore.isLoadingAIModels)
                .help("Load models from the configured AI provider")
            }

            if documentStore.availableAIModels.isEmpty {
                Text("Refresh to load models from Liara or the configured provider.")
                    .font(.caption)
                    .foregroundStyle(MirookTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .mirookPanel()
    }

    private func openDocument() {
        let panel = NSOpenPanel()
        let mirookBookType = UTType(filenameExtension: "mrbk") ?? .data
        panel.allowedContentTypes = [.pdf, mirookBookType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            if url.pathExtension.lowercased() == "mrbk" {
                documentStore.openBook(from: url)
            } else {
                documentStore.openPDF(from: url)
            }
        }
    }
}
