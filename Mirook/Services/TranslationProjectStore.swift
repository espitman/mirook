import CryptoKit
import Foundation

struct TranslationProjectStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadOrCreateProject(
        sourceURL: URL,
        displayName: String,
        pageCount: Int,
        targetLanguage: String,
        model: String
    ) throws -> TranslationProjectManifest {
        let id = try projectID(for: sourceURL, pageCount: pageCount)
        try fileManager.createDirectory(at: try projectDirectoryURL(projectID: id), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: try pagesDirectoryURL(projectID: id), withIntermediateDirectories: true)

        let manifestURL = try manifestURL(projectID: id)
        let now = Date()
        var manifest: TranslationProjectManifest

        if fileManager.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            manifest = try decoder.decode(TranslationProjectManifest.self, from: data)
            manifest.sourcePath = sourceURL.path
            manifest.displayName = displayName
            manifest.pageCount = pageCount
            manifest.targetLanguage = targetLanguage
            manifest.model = model
            manifest.updatedAt = now
        } else {
            manifest = TranslationProjectManifest(
                id: id,
                sourcePath: sourceURL.path,
                displayName: displayName,
                pageCount: pageCount,
                targetLanguage: targetLanguage,
                model: model,
                createdAt: now,
                updatedAt: now
            )
        }

        try saveManifest(manifest)
        return manifest
    }

    func loadPages(projectID: String) throws -> [Int: TranslatedTextPage] {
        let pagesURL = try pagesDirectoryURL(projectID: projectID)
        guard fileManager.fileExists(atPath: pagesURL.path) else {
            return [:]
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: pagesURL,
            includingPropertiesForKeys: nil
        )
        var pagesByIndex: [Int: TranslatedTextPage] = [:]

        for fileURL in fileURLs where fileURL.pathExtension == "json" {
            let data = try Data(contentsOf: fileURL)
            let page = try decoder.decode(TranslatedTextPage.self, from: data)
            pagesByIndex[page.pageIndex] = page
        }

        return pagesByIndex
    }

    func savePage(_ page: TranslatedTextPage, projectID: String) throws {
        try fileManager.createDirectory(at: try pagesDirectoryURL(projectID: projectID), withIntermediateDirectories: true)
        let data = try encoder.encode(page)
        try data.write(to: try pageURL(projectID: projectID, pageIndex: page.pageIndex), options: .atomic)
        try touchManifest(projectID: projectID)
    }

    func saveExportOptions(_ options: TextPDFExportOptions, projectID: String) throws {
        try fileManager.createDirectory(at: try projectDirectoryURL(projectID: projectID), withIntermediateDirectories: true)
        let data = try encoder.encode(options)
        try data.write(to: try exportOptionsURL(projectID: projectID), options: .atomic)
        try touchManifest(projectID: projectID)
    }

    func loadExportOptions(projectID: String) throws -> TextPDFExportOptions? {
        let url = try exportOptionsURL(projectID: projectID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(TextPDFExportOptions.self, from: data)
    }

    func projectDirectoryURL(projectID: String) throws -> URL {
        let url = try projectsRootURL().appendingPathComponent(projectID, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func projectID(for sourceURL: URL, pageCount: Int) throws -> String {
        let resourceValues = try? sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let identity = [
            sourceURL.standardizedFileURL.path,
            "\(resourceValues?.fileSize ?? 0)",
            "\(pageCount)"
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func projectsRootURL() throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = baseURL.appendingPathComponent("Mirook/Projects", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func pagesDirectoryURL(projectID: String) throws -> URL {
        try projectsRootURL()
            .appendingPathComponent(projectID, isDirectory: true)
            .appendingPathComponent("pages", isDirectory: true)
    }

    private func manifestURL(projectID: String) throws -> URL {
        try projectsRootURL()
            .appendingPathComponent(projectID, isDirectory: true)
            .appendingPathComponent("manifest.json")
    }

    private func pageURL(projectID: String, pageIndex: Int) throws -> URL {
        try pagesDirectoryURL(projectID: projectID)
            .appendingPathComponent(String(format: "%04d.json", pageIndex + 1))
    }

    private func exportOptionsURL(projectID: String) throws -> URL {
        try projectsRootURL()
            .appendingPathComponent(projectID, isDirectory: true)
            .appendingPathComponent("export-options.json")
    }

    private func saveManifest(_ manifest: TranslationProjectManifest) throws {
        try fileManager.createDirectory(at: try projectDirectoryURL(projectID: manifest.id), withIntermediateDirectories: true)
        let data = try encoder.encode(manifest)
        try data.write(to: try manifestURL(projectID: manifest.id), options: .atomic)
    }

    private func touchManifest(projectID: String) throws {
        let url = try manifestURL(projectID: projectID)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let data = try Data(contentsOf: url)
        var manifest = try decoder.decode(TranslationProjectManifest.self, from: data)
        manifest.updatedAt = Date()
        try saveManifest(manifest)
    }
}
