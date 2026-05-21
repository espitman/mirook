import CommonCrypto
import CryptoKit
import Foundation
import Security
import SQLite3

struct TranslationProjectPackage {
    let manifest: TranslationProjectManifest
    let pdfData: Data
    let bookURL: URL
}

final class TranslationProjectStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var unlockedKeysByBookPath: [String: SymmetricKey] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? migrateLegacyBookFilesIfNeeded()
        try? migrateAllLegacyProjectsIfNeeded()
        try? embedAvailableSourcePDFsInExistingBooks()
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

        let bookURL = try bookURL(projectID: id, displayName: displayName)
        let database = try MirookBookDatabase(url: bookURL)
        try requireUnlockedIfNeeded(database: database, bookURL: bookURL)

        let now = Date()
        var manifest: TranslationProjectManifest

        if let data = try loadMetadataPayload(key: MetadataKey.manifest, database: database, bookURL: bookURL) {
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

        try saveManifest(manifest, database: database, bookURL: bookURL)
        try embedSourcePDFIfNeeded(projectID: id, sourceURL: sourceURL)
        return manifest
    }

    func loadProject(fromBookURL url: URL) throws -> TranslationProjectPackage {
        let bookURL = try normalizedBookURL(url)
        let database = try MirookBookDatabase(url: bookURL)
        try requireUnlockedIfNeeded(database: database, bookURL: bookURL)

        guard let data = try loadMetadataPayload(key: MetadataKey.manifest, database: database, bookURL: bookURL) else {
            throw TranslationProjectStoreError.missingManifest(projectID: bookURL.deletingPathExtension().lastPathComponent)
        }

        let manifest = try decoder.decode(TranslationProjectManifest.self, from: data)
        guard let pdfData = try embeddedPDFData(database: database, bookURL: bookURL, manifest: manifest) else {
            throw TranslationProjectStoreError.missingEmbeddedPDF(displayName: manifest.displayName)
        }

        return TranslationProjectPackage(manifest: manifest, pdfData: pdfData, bookURL: bookURL)
    }

    func loadPages(projectID: String) throws -> [Int: TranslatedTextPage] {
        guard let bookURL = try existingBookURL(projectID: projectID) else {
            return [:]
        }

        let database = try MirookBookDatabase(url: bookURL)
        try requireUnlockedIfNeeded(database: database, bookURL: bookURL)

        var pagesByIndex: [Int: TranslatedTextPage] = [:]
        for (pageIndex, data) in try loadPagePayloads(database: database, bookURL: bookURL) {
            let page = try decoder.decode(TranslatedTextPage.self, from: data)
            pagesByIndex[page.pageIndex] = page

            if page.pageIndex != pageIndex {
                pagesByIndex[pageIndex] = page
            }
        }

        return pagesByIndex
    }

    func savePage(_ page: TranslatedTextPage, projectID: String) throws {
        let bookURL = try bookURL(projectID: projectID)
        let database = try MirookBookDatabase(url: bookURL)
        let data = try encoder.encode(page)
        try savePagePayload(data, pageIndex: page.pageIndex, database: database, bookURL: bookURL)
        try touchManifest(projectID: projectID)
    }

    func saveExportOptions(_ options: TextPDFExportOptions, projectID: String) throws {
        let bookURL = try bookURL(projectID: projectID)
        let database = try MirookBookDatabase(url: bookURL)
        let data = try encoder.encode(options)
        try saveMetadataPayload(data, key: MetadataKey.exportOptions, database: database, bookURL: bookURL)
        try touchManifest(projectID: projectID)
    }

    func loadExportOptions(projectID: String) throws -> TextPDFExportOptions? {
        guard let bookURL = try existingBookURL(projectID: projectID) else {
            return nil
        }

        let database = try MirookBookDatabase(url: bookURL)
        guard let data = try loadMetadataPayload(key: MetadataKey.exportOptions, database: database, bookURL: bookURL) else {
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

    func embedSourcePDFIfNeeded(projectID: String, sourceURL: URL) throws {
        let bookURL = try bookURL(projectID: projectID)
        let database = try MirookBookDatabase(url: bookURL)
        try requireUnlockedIfNeeded(database: database, bookURL: bookURL)

        if try loadMetadataPayload(key: MetadataKey.sourcePDF, database: database, bookURL: bookURL) != nil {
            return
        }

        let data = try Data(contentsOf: sourceURL)
        try saveMetadataPayload(data, key: MetadataKey.sourcePDF, database: database, bookURL: bookURL)
    }

    func projectDirectoryURL(projectID: String) throws -> URL {
        try bookURL(projectID: projectID)
    }

    func isPasswordProtected(projectID: String) throws -> Bool {
        guard let bookURL = try existingBookURL(projectID: projectID) else {
            return false
        }

        return try MirookBookDatabase(url: bookURL).loadInfoData(key: InfoKey.encryption) != nil
    }

    func unlockProject(projectID: String, password: String) throws {
        guard let bookURL = try existingBookURL(projectID: projectID) else {
            throw TranslationProjectStoreError.missingManifest(projectID: projectID)
        }

        try unlockBook(at: bookURL, password: password)
    }

    func unlockBook(at url: URL, password: String) throws {
        let bookURL = try normalizedBookURL(url)
        let database = try MirookBookDatabase(url: bookURL)
        guard let encryptionMetadata = try encryptionMetadata(database: database) else {
            return
        }

        let key = try BookPasswordCrypto.deriveKey(
            password: password,
            salt: encryptionMetadata.salt,
            iterations: encryptionMetadata.iterations
        )

        do {
            let checkData = try BookPasswordCrypto.decrypt(encryptionMetadata.passwordCheck, using: key)
            guard String(data: checkData, encoding: .utf8) == BookPasswordCrypto.passwordCheckText else {
                throw TranslationProjectStoreError.invalidPassword
            }
        } catch {
            throw TranslationProjectStoreError.invalidPassword
        }

        unlockedKeysByBookPath[bookURL.standardizedFileURL.path] = key
    }

    func setPassword(projectID: String, password: String) throws {
        guard !password.isEmpty else {
            throw TranslationProjectStoreError.emptyPassword
        }

        let bookURL = try bookURL(projectID: projectID)
        let database = try MirookBookDatabase(url: bookURL)
        guard try encryptionMetadata(database: database) == nil else {
            throw TranslationProjectStoreError.bookAlreadyLocked
        }

        let payloads = try decryptedPayloads(database: database, bookURL: bookURL)
        let newKey = try installEncryption(password: password, payloads: payloads, database: database, bookURL: bookURL)
        unlockedKeysByBookPath[bookURL.standardizedFileURL.path] = newKey
    }

    func changePassword(projectID: String, oldPassword: String, newPassword: String) throws {
        guard !newPassword.isEmpty else {
            throw TranslationProjectStoreError.emptyPassword
        }

        let bookURL = try bookURL(projectID: projectID)
        try unlockBook(at: bookURL, password: oldPassword)

        let database = try MirookBookDatabase(url: bookURL)
        let payloads = try decryptedPayloads(database: database, bookURL: bookURL)
        let newKey = try installEncryption(password: newPassword, payloads: payloads, database: database, bookURL: bookURL)
        unlockedKeysByBookPath[bookURL.standardizedFileURL.path] = newKey
    }

    func removePassword(projectID: String, password: String) throws {
        let bookURL = try bookURL(projectID: projectID)
        try unlockBook(at: bookURL, password: password)

        let database = try MirookBookDatabase(url: bookURL)
        let payloads = try decryptedPayloads(database: database, bookURL: bookURL)

        try database.transaction {
            for (key, data) in payloads.metadata {
                try database.saveMetadataJSONData(data, key: key)
            }
            for (pageIndex, data) in payloads.pages {
                try database.savePageJSONData(data, pageIndex: pageIndex)
            }
            try database.deleteInfoData(key: InfoKey.encryption)
        }

        unlockedKeysByBookPath[bookURL.standardizedFileURL.path] = nil
    }

    private enum MetadataKey {
        static let manifest = "manifest"
        static let exportOptions = "exportOptions"
        static let sourcePDF = "sourcePDF"
    }

    private enum InfoKey {
        static let encryption = "encryption"
        static let projectID = "projectID"
        static let displayName = "displayName"
        static let pageCount = "pageCount"
        static let sourcePath = "sourcePath"
    }

    private struct PayloadSnapshot {
        let metadata: [(String, Data)]
        let pages: [(Int, Data)]
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

        return try booksRootURL().appendingPathComponent("\(projectID).mrbk")
    }

    private func bookURL(projectID: String, displayName: String) throws -> URL {
        if let existingURL = try existingBookURL(projectID: projectID) {
            return existingURL
        }

        return try booksRootURL().appendingPathComponent(
            "\(projectFileName(displayName: displayName, projectID: projectID)).mrbk"
        )
    }

    private func existingBookURL(projectID: String) throws -> URL? {
        let rootURL = try booksRootURL()
        for fileExtension in ["mrbk", "mirookbook"] {
            let exactURL = rootURL.appendingPathComponent("\(projectID).\(fileExtension)")
            if fileManager.fileExists(atPath: exactURL.path) {
                return try normalizedBookURL(exactURL)
            }
        }

        let shortID = String(projectID.prefix(12))
        let bookURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for candidateURL in bookURLs where ["mrbk", "mirookbook"].contains(candidateURL.pathExtension) {
            let bookURL = try normalizedBookURL(candidateURL)

            if bookURL.deletingPathExtension().lastPathComponent.hasSuffix(" - \(shortID)") {
                return bookURL
            }

            guard let database = try? MirookBookDatabase(url: bookURL) else {
                continue
            }

            if let publicProjectID = try? database.loadInfoText(key: InfoKey.projectID),
               publicProjectID == projectID {
                return bookURL
            }

            guard let data = try? database.loadMetadataJSONData(key: MetadataKey.manifest),
                  let manifest = try? decoder.decode(TranslationProjectManifest.self, from: data),
                  manifest.id == projectID else {
                continue
            }

            return bookURL
        }

        return nil
    }

    private func normalizedBookURL(_ url: URL) throws -> URL {
        guard url.pathExtension == "mirookbook" else {
            return url
        }

        let targetURL = url.deletingPathExtension().appendingPathExtension("mrbk")
        if fileManager.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        try fileManager.moveItem(at: url, to: targetURL)
        return targetURL
    }

    private func saveManifest(_ manifest: TranslationProjectManifest) throws {
        let bookURL = try bookURL(projectID: manifest.id, displayName: manifest.displayName)
        let database = try MirookBookDatabase(url: bookURL)
        try saveManifest(manifest, database: database, bookURL: bookURL)
    }

    private func saveManifest(_ manifest: TranslationProjectManifest, database: MirookBookDatabase, bookURL: URL) throws {
        try savePublicInfo(manifest, database: database)
        let data = try encoder.encode(manifest)
        try saveMetadataPayload(data, key: MetadataKey.manifest, database: database, bookURL: bookURL)
    }

    private func savePublicInfo(_ manifest: TranslationProjectManifest, database: MirookBookDatabase) throws {
        try database.saveInfoText(manifest.id, key: InfoKey.projectID)
        try database.saveInfoText(manifest.displayName, key: InfoKey.displayName)
        try database.saveInfoText("\(manifest.pageCount)", key: InfoKey.pageCount)
        try database.saveInfoText(manifest.sourcePath, key: InfoKey.sourcePath)
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
        guard let data = try loadMetadataPayload(key: MetadataKey.manifest, database: database, bookURL: bookURL) else {
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

    private func loadMetadataPayload(key: String, database: MirookBookDatabase, bookURL: URL) throws -> Data? {
        guard let data = try database.loadMetadataJSONData(key: key) else {
            return nil
        }

        guard try encryptionMetadata(database: database) != nil else {
            return data
        }

        return try BookPasswordCrypto.decrypt(data, using: requiredUnlockedKey(for: bookURL, database: database))
    }

    private func saveMetadataPayload(_ data: Data, key: String, database: MirookBookDatabase, bookURL: URL) throws {
        let payload = if try encryptionMetadata(database: database) != nil {
            try BookPasswordCrypto.encrypt(data, using: requiredUnlockedKey(for: bookURL, database: database))
        } else {
            data
        }

        try database.saveMetadataJSONData(payload, key: key)
    }

    private func loadPagePayloads(database: MirookBookDatabase, bookURL: URL) throws -> [(Int, Data)] {
        let pages = try database.loadPageJSONData()
        guard try encryptionMetadata(database: database) != nil else {
            return pages
        }

        let key = try requiredUnlockedKey(for: bookURL, database: database)
        return try pages.map { pageIndex, data in
            (pageIndex, try BookPasswordCrypto.decrypt(data, using: key))
        }
    }

    private func savePagePayload(_ data: Data, pageIndex: Int, database: MirookBookDatabase, bookURL: URL) throws {
        let payload = if try encryptionMetadata(database: database) != nil {
            try BookPasswordCrypto.encrypt(data, using: requiredUnlockedKey(for: bookURL, database: database))
        } else {
            data
        }

        try database.savePageJSONData(payload, pageIndex: pageIndex)
    }

    private func decryptedPayloads(database: MirookBookDatabase, bookURL: URL) throws -> PayloadSnapshot {
        let metadata: [(String, Data)]
        let pages: [(Int, Data)]

        if try encryptionMetadata(database: database) != nil {
            let key = try requiredUnlockedKey(for: bookURL, database: database)
            metadata = try database.loadAllMetadataJSONData().map { keyName, data in
                (keyName, try BookPasswordCrypto.decrypt(data, using: key))
            }
            pages = try database.loadPageJSONData().map { pageIndex, data in
                (pageIndex, try BookPasswordCrypto.decrypt(data, using: key))
            }
        } else {
            metadata = try database.loadAllMetadataJSONData()
            pages = try database.loadPageJSONData()
        }

        return PayloadSnapshot(metadata: metadata, pages: pages)
    }

    private func installEncryption(
        password: String,
        payloads: PayloadSnapshot,
        database: MirookBookDatabase,
        bookURL: URL
    ) throws -> SymmetricKey {
        let salt = try BookPasswordCrypto.randomData(count: 16)
        let key = try BookPasswordCrypto.deriveKey(
            password: password,
            salt: salt,
            iterations: BookPasswordCrypto.defaultIterations
        )
        let check = try BookPasswordCrypto.encrypt(Data(BookPasswordCrypto.passwordCheckText.utf8), using: key)
        let metadata = BookEncryptionMetadata(
            iterations: BookPasswordCrypto.defaultIterations,
            salt: salt,
            passwordCheck: check
        )
        let encryptionData = try encoder.encode(metadata)

        try database.transaction {
            for (keyName, data) in payloads.metadata {
                try database.saveMetadataJSONData(try BookPasswordCrypto.encrypt(data, using: key), key: keyName)
            }
            for (pageIndex, data) in payloads.pages {
                try database.savePageJSONData(try BookPasswordCrypto.encrypt(data, using: key), pageIndex: pageIndex)
            }
            try database.saveInfoData(encryptionData, key: InfoKey.encryption)
        }

        return key
    }

    private func requireUnlockedIfNeeded(database: MirookBookDatabase, bookURL: URL) throws {
        guard try encryptionMetadata(database: database) != nil else {
            return
        }

        _ = try requiredUnlockedKey(for: bookURL, database: database)
    }

    private func requiredUnlockedKey(for bookURL: URL, database: MirookBookDatabase) throws -> SymmetricKey {
        let path = bookURL.standardizedFileURL.path
        if let key = unlockedKeysByBookPath[path] {
            return key
        }

        throw TranslationProjectStoreError.lockedBook(
            bookURL: bookURL,
            displayName: (try? database.loadInfoText(key: InfoKey.displayName)) ?? bookURL.deletingPathExtension().lastPathComponent
        )
    }

    private func encryptionMetadata(database: MirookBookDatabase) throws -> BookEncryptionMetadata? {
        guard let data = try database.loadInfoData(key: InfoKey.encryption) else {
            return nil
        }

        return try decoder.decode(BookEncryptionMetadata.self, from: data)
    }

    private func embeddedPDFData(
        database: MirookBookDatabase,
        bookURL: URL,
        manifest: TranslationProjectManifest
    ) throws -> Data? {
        if let data = try loadMetadataPayload(key: MetadataKey.sourcePDF, database: database, bookURL: bookURL) {
            return data
        }

        let sourceURL = URL(fileURLWithPath: manifest.sourcePath)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: sourceURL)
        try saveMetadataPayload(data, key: MetadataKey.sourcePDF, database: database, bookURL: bookURL)
        return data
    }

    private func migrateLegacyBookFilesIfNeeded() throws {
        let rootURL = try booksRootURL()
        let legacyBookURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "mirookbook" }

        for legacyURL in legacyBookURLs {
            _ = try normalizedBookURL(legacyURL)
        }
    }

    private func embedAvailableSourcePDFsInExistingBooks() throws {
        let rootURL = try booksRootURL()
        let bookURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "mrbk" }

        for bookURL in bookURLs {
            let database = try MirookBookDatabase(url: bookURL)
            guard try encryptionMetadata(database: database) == nil,
                  let data = try database.loadMetadataJSONData(key: MetadataKey.manifest),
                  let manifest = try? decoder.decode(TranslationProjectManifest.self, from: data),
                  try database.loadMetadataJSONData(key: MetadataKey.sourcePDF) == nil else {
                continue
            }

            try savePublicInfo(manifest, database: database)
            let sourceURL = URL(fileURLWithPath: manifest.sourcePath)
            if fileManager.fileExists(atPath: sourceURL.path) {
                try database.saveMetadataJSONData(Data(contentsOf: sourceURL), key: MetadataKey.sourcePDF)
            }
        }
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

        try savePublicInfo(manifest, database: database)
        if try database.loadMetadataJSONData(key: MetadataKey.manifest) == nil {
            try database.saveMetadataJSONData(manifestData, key: MetadataKey.manifest)
        }

        let sourceURL = URL(fileURLWithPath: manifest.sourcePath)
        if fileManager.fileExists(atPath: sourceURL.path),
           try database.loadMetadataJSONData(key: MetadataKey.sourcePDF) == nil {
            try database.saveMetadataJSONData(Data(contentsOf: sourceURL), key: MetadataKey.sourcePDF)
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

enum TranslationProjectStoreError: LocalizedError {
    case missingManifest(projectID: String)
    case incompleteMigration(projectName: String)
    case lockedBook(bookURL: URL, displayName: String)
    case invalidPassword
    case emptyPassword
    case bookAlreadyLocked
    case missingEmbeddedPDF(displayName: String)
    case crypto(message: String)
    case sqlite(message: String)

    var errorDescription: String? {
        switch self {
        case let .missingManifest(projectID):
            "Mirook could not find the project manifest for \(projectID)."
        case let .incompleteMigration(projectName):
            "Mirook could not fully migrate \(projectName) into an .mrbk file."
        case let .lockedBook(_, displayName):
            "\(displayName) is password protected."
        case .invalidPassword:
            "The password is incorrect."
        case .emptyPassword:
            "Password cannot be empty."
        case .bookAlreadyLocked:
            "This book already has a password."
        case let .missingEmbeddedPDF(displayName):
            "The original PDF is not embedded in \(displayName), and the old source file could not be found."
        case let .crypto(message):
            "Mirook encryption error: \(message)"
        case let .sqlite(message):
            "Mirook storage error: \(message)"
        }
    }
}

private struct BookEncryptionMetadata: Codable {
    let version: Int
    let kdf: String
    let iterations: Int
    let salt: Data
    let passwordCheck: Data

    init(iterations: Int, salt: Data, passwordCheck: Data) {
        version = 1
        kdf = "PBKDF2-HMAC-SHA256"
        self.iterations = iterations
        self.salt = salt
        self.passwordCheck = passwordCheck
    }
}

private enum BookPasswordCrypto {
    static let defaultIterations = 210_000
    static let passwordCheckText = "mirook-password-check-v1"
    private static let keyByteCount = 32

    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        guard !password.isEmpty else {
            throw TranslationProjectStoreError.emptyPassword
        }

        var keyData = Data(count: keyByteCount)
        let status = password.withCString { passwordPointer in
            salt.withUnsafeBytes { saltPointer in
                keyData.withUnsafeMutableBytes { keyPointer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPointer,
                        strlen(passwordPointer),
                        saltPointer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        keyPointer.bindMemory(to: UInt8.self).baseAddress,
                        keyByteCount
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw TranslationProjectStoreError.crypto(message: "Could not derive a password key.")
        }

        return SymmetricKey(data: keyData)
    }

    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw TranslationProjectStoreError.crypto(message: "Could not seal encrypted data.")
        }

        return combined
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    static func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, count, pointer.baseAddress!)
        }

        guard status == errSecSuccess else {
            throw TranslationProjectStoreError.crypto(message: "Could not generate secure random data.")
        }

        return data
    }
}

private final class MirookBookDatabase {
    private var handle: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
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

    func loadInfoData(key: String) throws -> Data? {
        let statement = try prepare("SELECT value FROM book_info WHERE key = ? LIMIT 1")
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

    func loadInfoText(key: String) throws -> String? {
        guard let data = try loadInfoData(key: key) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func saveInfoData(_ data: Data, key: String) throws {
        let statement = try prepare(
            """
            INSERT INTO book_info (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = excluded.updated_at
            """
        )
        defer { sqlite3_finalize(statement) }

        try bindText(key, to: statement, at: 1)
        try bindData(data, to: statement, at: 2)
        try bindText(Self.timestamp(), to: statement, at: 3)
        try stepDone(statement)
    }

    func saveInfoText(_ text: String, key: String) throws {
        try saveInfoData(Data(text.utf8), key: key)
    }

    func deleteInfoData(key: String) throws {
        let statement = try prepare("DELETE FROM book_info WHERE key = ?")
        defer { sqlite3_finalize(statement) }

        try bindText(key, to: statement, at: 1)
        try stepDone(statement)
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

    func loadAllMetadataJSONData() throws -> [(String, Data)] {
        let statement = try prepare("SELECT key, json FROM metadata ORDER BY key ASC")
        defer { sqlite3_finalize(statement) }

        var rows: [(String, Data)] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                let key = String(cString: sqlite3_column_text(statement, 0))
                let data = columnData(statement, at: 1)
                rows.append((key, data))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw TranslationProjectStoreError.sqlite(message: Self.errorMessage(for: handle))
            }
        }
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

    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func ensureSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS book_info (
                key TEXT PRIMARY KEY NOT NULL,
                value BLOB NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
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
        try execute("PRAGMA user_version = 2")
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
