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
                        Text("Book translation workspace")
                            .font(.caption)
                            .foregroundStyle(MirookTheme.mutedInk)
                    }
                }

                if documentStore.hasOpenDocument {
                    currentBookSummary
                }

                Button {
                    openDocument()
                } label: {
                    Label("Open PDF / EPUB / Book", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MirookPrimaryButtonStyle())

                modelControls

                if documentStore.hasOpenDocument {
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

    private var currentBookSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            firstPagePreview

            VStack(alignment: .leading, spacing: 6) {
                Text("Current Book")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MirookTheme.mutedInk)

                Text(documentStore.displayName)
                    .font(.headline)
                    .foregroundStyle(MirookTheme.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(documentStore.sourceKindDisplayName)
                    Text("\(documentStore.pageCount) pages")
                    Text("Page 1 preview")
                }
                .font(.caption)
                .foregroundStyle(MirookTheme.mutedInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .mirookPanel()
    }

    @ViewBuilder
    private var firstPagePreview: some View {
        if let image = firstPageThumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 68, height: 92)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(MirookTheme.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        } else if let page = documentStore.epubDocument?.pages.first {
            EPUBFirstPagePreview(page: page)
                .frame(width: 68, height: 92)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(MirookTheme.controlFill)
                .frame(width: 68, height: 92)
                .overlay {
                    Image(systemName: "book.closed")
                        .foregroundStyle(MirookTheme.mutedInk)
                }
        }
    }

    private var firstPageThumbnail: NSImage? {
        guard let page = documentStore.document?.page(at: 0) else {
            return nil
        }
        return page.thumbnail(of: NSSize(width: 136, height: 184), for: .cropBox)
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

            Text(documentStore.isCurrentBookPasswordProtected ? "Password protected" : "\(documentStore.sourceKindDisplayName) embedded in .mrbk")
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
        let epubType = UTType(filenameExtension: "epub") ?? .data
        panel.allowedContentTypes = [.pdf, epubType, mirookBookType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            if url.pathExtension.lowercased() == "mrbk" {
                documentStore.openBook(from: url)
            } else if url.pathExtension.lowercased() == "epub" {
                documentStore.openEPUB(from: url)
            } else {
                documentStore.openPDF(from: url)
            }
        }
    }
}

private struct EPUBFirstPagePreview: View {
    let page: EPUBSourcePage

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white)

            if let image = firstImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(5)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(previewLines, id: \.self) { line in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(MirookTheme.ink.opacity(lineOpacity(for: line)))
                            .frame(width: lineWidth(for: line), height: 2.5)
                    }

                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(MirookTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    private var firstImage: NSImage? {
        for block in page.blocks {
            if case let .image(image) = block,
               let nsImage = NSImage(data: image.data) {
                return nsImage
            }
        }
        return nil
    }

    private var previewLines: [String] {
        let text = page.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            return ["empty-1", "empty-2", "empty-3"]
        }

        var lines: [String] = []
        var current = ""
        for word in words.prefix(28) {
            if current.count + word.count > 18 {
                lines.append(current)
                current = word
            } else {
                current = current.isEmpty ? word : "\(current) \(word)"
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return Array(lines.prefix(12))
    }

    private func lineWidth(for line: String) -> CGFloat {
        if line.hasPrefix("empty-") {
            return 42
        }
        let clamped = min(max(line.count, 5), 19)
        return CGFloat(clamped) / 19 * 48
    }

    private func lineOpacity(for line: String) -> Double {
        line.hasPrefix("empty-") ? 0.14 : 0.34
    }
}
