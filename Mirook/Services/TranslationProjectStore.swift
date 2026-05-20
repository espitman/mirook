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
        try migrateLegacyProjectIfNeeded(projectID: id, displayName: displayName)
        try fileManager.createDirectory(at: try projectDirectoryURL(projectID: id, displayName: displayName), withIntermediateDirectories: true)
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

    func recordUsage(_ usage: AIUsage?, projectID: String) throws -> TranslationProjectManifest? {
        guard let usage, usage.hasUsage else {
            return nil
        }

        var manifest = try loadManifest(projectID: projectID)
        var totalUsage = manifest.totalUsage ?? .zero
        totalUsage.add(usage)
        manifest.totalUsage = totalUsage
        manifest.updatedAt = Date()
        try saveManifest(manifest)
        return manifest
    }

    func projectDirectoryURL(projectID: String) throws -> URL {
        let rootURL = try projectsRootURL()
        let url = try existingProjectDirectoryURL(projectID: projectID, rootURL: rootURL) ??
            rootURL.appendingPathComponent(projectID, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func projectDirectoryURL(projectID: String, displayName: String) throws -> URL {
        let rootURL = try projectsRootURL()
        let url = try existingProjectDirectoryURL(projectID: projectID, rootURL: rootURL) ??
            rootURL.appendingPathComponent(
                projectDirectoryName(displayName: displayName, projectID: projectID),
                isDirectory: true
            )
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
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = baseURL.appendingPathComponent("Mirook/Projects", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func legacyProjectsRootURL() throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return baseURL.appendingPathComponent("Mirook/Projects", isDirectory: true)
    }

    private func pagesDirectoryURL(projectID: String) throws -> URL {
        try projectDirectoryURL(projectID: projectID)
            .appendingPathComponent("pages", isDirectory: true)
    }

    private func manifestURL(projectID: String) throws -> URL {
        try projectDirectoryURL(projectID: projectID)
            .appendingPathComponent("manifest.json")
    }

    private func pageURL(projectID: String, pageIndex: Int) throws -> URL {
        try pagesDirectoryURL(projectID: projectID)
            .appendingPathComponent(String(format: "%04d.json", pageIndex + 1))
    }

    private func exportOptionsURL(projectID: String) throws -> URL {
        try projectDirectoryURL(projectID: projectID)
            .appendingPathComponent("export-options.json")
    }

    private func saveManifest(_ manifest: TranslationProjectManifest) throws {
        try fileManager.createDirectory(
            at: try projectDirectoryURL(projectID: manifest.id, displayName: manifest.displayName),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(manifest)
        try data.write(to: try manifestURL(projectID: manifest.id), options: .atomic)
    }

    private func loadManifest(projectID: String) throws -> TranslationProjectManifest {
        let url = try manifestURL(projectID: projectID)
        let data = try Data(contentsOf: url)
        return try decoder.decode(TranslationProjectManifest.self, from: data)
    }

    private func touchManifest(projectID: String) throws {
        let url = try manifestURL(projectID: projectID)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        var manifest = try loadManifest(projectID: projectID)
        manifest.updatedAt = Date()
        try saveManifest(manifest)
    }

    private func migrateLegacyProjectIfNeeded(projectID: String, displayName: String) throws {
        let legacyURL = try legacyProjectsRootURL().appendingPathComponent(projectID, isDirectory: true)
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        let targetURL = try preferredProjectDirectoryURL(projectID: projectID, displayName: displayName)
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: targetURL.path) {
            try mergeMissingItems(from: legacyURL, to: targetURL)
            try removeDirectoryIfEmpty(legacyURL)
        } else {
            try fileManager.moveItem(at: legacyURL, to: targetURL)
        }
    }

    private func preferredProjectDirectoryURL(projectID: String, displayName: String) throws -> URL {
        try projectsRootURL().appendingPathComponent(
            projectDirectoryName(displayName: displayName, projectID: projectID),
            isDirectory: true
        )
    }

    private func projectDirectoryName(displayName: String, projectID: String) -> String {
        let invalidScalars = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = String(
            displayName.unicodeScalars.map { scalar in
                invalidScalars.contains(scalar) ? Character("-") : Character(scalar)
            }
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let visibleName = cleaned.isEmpty ? "Book" : String(cleaned.prefix(80))
        return "\(visibleName) - \(projectID.prefix(12))"
    }

    private func existingProjectDirectoryURL(projectID: String, rootURL: URL) throws -> URL? {
        let exactURL = rootURL.appendingPathComponent(projectID, isDirectory: true)
        if fileManager.fileExists(atPath: exactURL.path) {
            return exactURL
        }

        guard fileManager.fileExists(atPath: rootURL.path) else {
            return nil
        }

        let shortID = String(projectID.prefix(12))
        let directoryURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for directoryURL in directoryURLs {
            let isDirectory = (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }

            if directoryURL.lastPathComponent.hasSuffix(" - \(shortID)") {
                return directoryURL
            }

            let manifestURL = directoryURL.appendingPathComponent("manifest.json")
            if fileManager.fileExists(atPath: manifestURL.path),
               let data = try? Data(contentsOf: manifestURL),
               let manifest = try? decoder.decode(TranslationProjectManifest.self, from: data),
               manifest.id == projectID {
                return directoryURL
            }
        }

        return nil
    }

    private func mergeMissingItems(from sourceURL: URL, to targetURL: URL) throws {
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
        let itemURLs = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for itemURL in itemURLs {
            let destinationURL = targetURL.appendingPathComponent(itemURL.lastPathComponent)
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory,
               fileManager.fileExists(atPath: destinationURL.path) {
                try mergeMissingItems(from: itemURL, to: destinationURL)
                try removeDirectoryIfEmpty(itemURL)
            } else if !fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.moveItem(at: itemURL, to: destinationURL)
            }
        }
    }

    private func removeDirectoryIfEmpty(_ directoryURL: URL) throws {
        let remainingItems = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
        if remainingItems.isEmpty {
            try fileManager.removeItem(at: directoryURL)
        }
    }
}
