import CryptoKit
import Foundation
import SQLite3

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

        try? migrateAllLegacyProjectsIfNeeded()
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

        let now = Date()
        var manifest: TranslationProjectManifest

        if let existingManifest = try loadManifestIfExists(projectID: id) {
            manifest = existingManifest
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
        guard let bookURL = try existingBookURL(projectID: projectID) else {
            return [:]
        }

        let database = try MirookBookDatabase(url: bookURL)
        var pagesByIndex: [Int: TranslatedTextPage] = [:]

        for (pageIndex, data) in try database.loadPageJSONData() {
            let page = try decoder.decode(TranslatedTextPage.self, from: data)
            pagesByIndex[page.pageIndex] = page

            if page.pageIndex != pageIndex {
                pagesByIndex[pageIndex] = page
            }
        }

        return pagesByIndex
    }

    func savePage(_ page: TranslatedTextPage, projectID: String) throws {
        let database = try MirookBookDatabase(url: try bookURL(projectID: projectID))
        let data = try encoder.encode(page)
        try database.savePageJSONData(data, pageIndex: page.pageIndex)
        try touchManifest(projectID: projectID)
    }

    func saveExportOptions(_ options: TextPDFExportOptions, projectID: String) throws {
        let database = try MirookBookDatabase(url: try bookURL(projectID: projectID))
        let data = try encoder.encode(options)
        try database.saveMetadataJSONData(data, key: MetadataKey.exportOptions)
        try touchManifest(projectID: projectID)
    }

    func loadExportOptions(projectID: String) throws -> TextPDFExportOptions? {
        guard let bookURL = try existingBookURL(projectID: projectID) else {
            return nil
        }

        let database = try MirookBookDatabase(url: bookURL)
        guard let data = try database.loadMetadataJSONData(key: MetadataKey.exportOptions) else {
            return nil
        }

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
        try bookURL(projectID: projectID)
    }

    private enum MetadataKey {
        static let manifest = "manifest"
        static let exportOptions = "exportOptions"
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

    private func mirookRootURL() throws -> URL {
        let baseURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = baseURL.appendingPathComponent("Mirook", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func booksRootURL() throws -> URL {
        let rootURL = try mirookRootURL().appendingPathComponent("Books", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func documentsProjectsRootURL() throws -> URL {
        try mirookRootURL().appendingPathComponent("Projects", isDirectory: true)
    }

    private func applicationSupportProjectsRootURL() throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return baseURL.appendingPathComponent("Mirook/Projects", isDirectory: true)
    }

    private func bookURL(projectID: String) throws -> URL {
        if let existingURL = try existingBookURL(projectID: projectID) {
            return existingURL
        }

        return try booksRootURL().appendingPathComponent("\(projectID).mirookbook")
    }

    private func bookURL(projectID: String, displayName: String) throws -> URL {
        if let existingURL = try existingBookURL(projectID: projectID) {
            return existingURL
        }

        return try booksRootURL().appendingPathComponent(
            "\(projectFileName(displayName: displayName, projectID: projectID)).mirookbook"
        )
    }

    private func existingBookURL(projectID: String) throws -> URL? {
        let rootURL = try booksRootURL()
        let exactURL = rootURL.appendingPathComponent("\(projectID).mirookbook")
        if fileManager.fileExists(atPath: exactURL.path) {
            return exactURL
        }

        let shortID = String(projectID.prefix(12))
        let bookURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for bookURL in bookURLs where bookURL.pathExtension == "mirookbook" {
            if bookURL.deletingPathExtension().lastPathComponent.hasSuffix(" - \(shortID)") {
                return bookURL
            }

            guard let database = try? MirookBookDatabase(url: bookURL),
                  let data = try? database.loadMetadataJSONData(key: MetadataKey.manifest),
                  let manifest = try? decoder.decode(TranslationProjectManifest.self, from: data),
                  manifest.id == projectID else {
                continue
            }

            return bookURL
        }

        return nil
    }

    private func saveManifest(_ manifest: TranslationProjectManifest) throws {
        let database = try MirookBookDatabase(url: try bookURL(projectID: manifest.id, displayName: manifest.displayName))
        let data = try encoder.encode(manifest)
        try database.saveMetadataJSONData(data, key: MetadataKey.manifest)
    }

    private func loadManifest(projectID: String) throws -> TranslationProjectManifest {
        guard let manifest = try loadManifestIfExists(projectID: projectID) else {
            throw TranslationProjectStoreError.missingManifest(projectID: projectID)
        }

        return manifest
    }

    private func loadManifestIfExists(projectID: String) throws -> TranslationProjectManifest? {
        guard let bookURL = try existingBookURL(projectID: projectID) else {
            return nil
        }

        let database = try MirookBookDatabase(url: bookURL)
        guard let data = try database.loadMetadataJSONData(key: MetadataKey.manifest) else {
            return nil
        }

        return try decoder.decode(TranslationProjectManifest.self, from: data)
    }

    private func touchManifest(projectID: String) throws {
        guard var manifest = try loadManifestIfExists(projectID: projectID) else {
            return
        }

        manifest.updatedAt = Date()
        try saveManifest(manifest)
    }

    private func migrateAllLegacyProjectsIfNeeded() throws {
        let possibleRoots = [
            try? documentsProjectsRootURL(),
            try? applicationSupportProjectsRootURL()
        ].compactMap { $0 }

        for rootURL in possibleRoots {
            guard fileManager.fileExists(atPath: rootURL.path) else {
                continue
            }

            let projectURLs = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for projectURL in projectURLs {
                let isDirectory = (try? projectURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDirectory,
                      fileManager.fileExists(atPath: projectURL.appendingPathComponent("manifest.json").path) else {
                    continue
                }

                try migrateLegacyProject(at: projectURL)
            }

            try removeDirectoryIfEmpty(rootURL)
        }
    }

    private func migrateLegacyProjectIfNeeded(projectID: String, displayName: String) throws {
        let possibleRoots = [
            try? documentsProjectsRootURL(),
            try? applicationSupportProjectsRootURL()
        ].compactMap { $0 }

        for rootURL in possibleRoots {
            guard let projectURL = try existingLegacyProjectDirectoryURL(
                projectID: projectID,
                displayName: displayName,
                rootURL: rootURL
            ) else {
                continue
            }

            try migrateLegacyProject(at: projectURL)
            try removeDirectoryIfEmpty(rootURL)
        }
    }

    private func migrateLegacyProject(at projectURL: URL) throws {
        let manifestURL = projectURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(TranslationProjectManifest.self, from: manifestData)
        let destinationURL = try bookURL(projectID: manifest.id, displayName: manifest.displayName)
        let database = try MirookBookDatabase(url: destinationURL)

        if try database.loadMetadataJSONData(key: MetadataKey.manifest) == nil {
            try database.saveMetadataJSONData(manifestData, key: MetadataKey.manifest)
        }

        let exportOptionsURL = projectURL.appendingPathComponent("export-options.json")
        if fileManager.fileExists(atPath: exportOptionsURL.path),
           try database.loadMetadataJSONData(key: MetadataKey.exportOptions) == nil {
            try database.saveMetadataJSONData(Data(contentsOf: exportOptionsURL), key: MetadataKey.exportOptions)
        }

        let pageIndices = try migrateLegacyPages(from: projectURL, into: database)
        guard try database.containsPageIndices(pageIndices) else {
            throw TranslationProjectStoreError.incompleteMigration(projectName: projectURL.lastPathComponent)
        }

        try archiveLegacyProject(projectURL)
    }

    private func migrateLegacyPages(from projectURL: URL, into database: MirookBookDatabase) throws -> [Int] {
        let pagesURL = projectURL.appendingPathComponent("pages", isDirectory: true)
        guard fileManager.fileExists(atPath: pagesURL.path) else {
            return []
        }

        let pageURLs = try fileManager.contentsOfDirectory(
            at: pagesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var pageIndices: [Int] = []
        for pageURL in pageURLs where pageURL.pathExtension == "json" {
            let data = try Data(contentsOf: pageURL)
            let page = try decoder.decode(TranslatedTextPage.self, from: data)
            pageIndices.append(page.pageIndex)

            if try !database.hasPage(pageIndex: page.pageIndex) {
                try database.savePageJSONData(data, pageIndex: page.pageIndex)
            }
        }

        return pageIndices
    }

    private func archiveLegacyProject(_ projectURL: URL) throws {
        guard fileManager.fileExists(atPath: projectURL.path) else {
            return
        }

        let backupRootURL = try mirookRootURL().appendingPathComponent(".MigratedProjectBackups", isDirectory: true)
        try fileManager.createDirectory(at: backupRootURL, withIntermediateDirectories: true)

        var destinationURL = backupRootURL.appendingPathComponent(projectURL.lastPathComponent, isDirectory: true)
        var duplicateIndex = 2
        while fileManager.fileExists(atPath: destinationURL.path) {
            destinationURL = backupRootURL.appendingPathComponent(
                "\(projectURL.lastPathComponent) \(duplicateIndex)",
                isDirectory: true
            )
            duplicateIndex += 1
        }

        try fileManager.moveItem(at: projectURL, to: destinationURL)
    }

    private func existingLegacyProjectDirectoryURL(
        projectID: String,
        displayName: String,
        rootURL: URL
    ) throws -> URL? {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return nil
        }

        let exactURL = rootURL.appendingPathComponent(projectID, isDirectory: true)
        if fileManager.fileExists(atPath: exactURL.path) {
            return exactURL
        }

        let preferredURL = rootURL.appendingPathComponent(
            projectFileName(displayName: displayName, projectID: projectID),
            isDirectory: true
        )
        if fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
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

    private func projectFileName(displayName: String, projectID: String) -> String {
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

    private func removeDirectoryIfEmpty(_ directoryURL: URL) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        let remainingItems = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
        if remainingItems.isEmpty {
            try fileManager.removeItem(at: directoryURL)
        }
    }
}

private enum TranslationProjectStoreError: LocalizedError {
    case missingManifest(projectID: String)
    case incompleteMigration(projectName: String)
    case sqlite(message: String)

    var errorDescription: String? {
        switch self {
        case let .missingManifest(projectID):
            "Mirook could not find the project manifest for \(projectID)."
        case let .incompleteMigration(projectName):
            "Mirook could not fully migrate \(projectName) into a .mirookbook file."
        case let .sqlite(message):
            "Mirook storage error: \(message)"
        }
    }
}

private final class MirookBookDatabase {
    private let url: URL
    private var handle: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            throw TranslationProjectStoreError.sqlite(message: Self.errorMessage(for: handle))
        }

        try execute("PRAGMA journal_mode = DELETE")
        try execute("PRAGMA synchronous = NORMAL")
        try ensureSchema()
    }

    deinit {
        sqlite3_close(handle)
    }

    func loadMetadataJSONData(key: String) throws -> Data? {
        let statement = try prepare("SELECT json FROM metadata WHERE key = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }

        try bindText(key, to: statement, at: 1)

        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return columnData(statement, at: 0)
        }

        if result == SQLITE_DONE {
            return nil
        }

        throw TranslationProjectStoreError.sqlite(message: Self.errorMessage(for: handle))
    }

    func saveMetadataJSONData(_ data: Data, key: String) throws {
        let statement = try prepare(
            """
            INSERT INTO metadata (key, json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                json = excluded.json,
                updated_at = excluded.updated_at
            """
        )
        defer { sqlite3_finalize(statement) }

        try bindText(key, to: statement, at: 1)
        try bindData(data, to: statement, at: 2)
        try bindText(Self.timestamp(), to: statement, at: 3)
        try stepDone(statement)
    }

    func loadPageJSONData() throws -> [(Int, Data)] {
        let statement = try prepare("SELECT page_index, json FROM pages ORDER BY page_index ASC")
        defer { sqlite3_finalize(statement) }

        var pages: [(Int, Data)] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                let pageIndex = Int(sqlite3_column_int(statement, 0))
                let data = columnData(statement, at: 1)
                pages.append((pageIndex, data))
            } else if result == SQLITE_DONE {
                return pages
            } else {
                throw TranslationProjectStoreError.sqlite(message: Self.errorMessage(for: handle))
            }
        }
    }

    func hasPage(pageIndex: Int) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM pages WHERE page_index = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(pageIndex))

        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return true
        }

        if result == SQLITE_DONE {
            return false
        }

        throw TranslationProjectStoreError.sqlite(message: Self.errorMessage(for: handle))
    }

    func savePageJSONData(_ data: Data, pageIndex: Int) throws {
        let statement = try prepare(
            """
            INSERT INTO pages (page_index, json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(page_index) DO UPDATE SET
                json = excluded.json,
                updated_at = excluded.updated_at
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(pageIndex))
        try bindData(data, to: statement, at: 2)
        try bindText(Self.timestamp(), to: statement, at: 3)
        try stepDone(statement)
    }

    func containsPageIndices(_ pageIndices: [Int]) throws -> Bool {
        for pageIndex in Set(pageIndices) {
            if try !hasPage(pageIndex: pageIndex) {
                return false
            }
        }

        return true
    }

    private func ensureSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY NOT NULL,
                json BLOB NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS pages (
                page_index INTEGER PRIMARY KEY NOT NULL,
                json BLOB NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        try execute("PRAGMA user_version = 1")
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? Self.errorMessage(for: handle)
            sqlite3_free(errorMessage)
            throw TranslationProjectStoreError.sqlite(message: message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TranslationProjectStoreError.sqlite(message: Self.errorMessage(for: handle))
        }

        return statement
    }

    private func bindText(_ text: String, to statement: OpaquePointer?, at index: Int32) throws {
        let result = text.withCString {
            sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
        }

        guard result == SQLITE_OK else {
            throw TranslationProjectStoreError.sqlite(message: Self.errorMessage(for: handle))
        }
    }

    private func bindData(_ data: Data, to statement: OpaquePointer?, at index: Int32) throws {
        let result = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), sqliteTransient)
        }

        guard result == SQLITE_OK else {
            throw TranslationProjectStoreError.sqlite(message: Self.errorMessage(for: handle))
        }
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TranslationProjectStoreError.sqlite(message: Self.errorMessage(for: handle))
        }
    }

    private func columnData(_ statement: OpaquePointer?, at index: Int32) -> Data {
        let byteCount = Int(sqlite3_column_bytes(statement, index))
        guard let bytes = sqlite3_column_blob(statement, index), byteCount > 0 else {
            return Data()
        }

        return Data(bytes: bytes, count: byteCount)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func errorMessage(for handle: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(handle) else {
            return "Unknown SQLite error."
        }

        return String(cString: message)
    }
}
