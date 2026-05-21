import Foundation

struct TranslationProjectManifest: Codable {
    let id: String
    var sourcePath: String
    var displayName: String
    var pageCount: Int
    var targetLanguage: String
    var model: String
    var createdAt: Date
    var updatedAt: Date
    var sourceFingerprint: String? = nil
    var sourceKind: SourceDocumentKind = .pdf
    var totalUsage: AIUsage? = nil

    init(
        id: String,
        sourcePath: String,
        displayName: String,
        pageCount: Int,
        targetLanguage: String,
        model: String,
        createdAt: Date,
        updatedAt: Date,
        sourceFingerprint: String? = nil,
        sourceKind: SourceDocumentKind = .pdf,
        totalUsage: AIUsage? = nil
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.displayName = displayName
        self.pageCount = pageCount
        self.targetLanguage = targetLanguage
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceFingerprint = sourceFingerprint
        self.sourceKind = sourceKind
        self.totalUsage = totalUsage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourcePath
        case displayName
        case pageCount
        case targetLanguage
        case model
        case createdAt
        case updatedAt
        case sourceFingerprint
        case sourceKind
        case totalUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        displayName = try container.decode(String.self, forKey: .displayName)
        pageCount = try container.decode(Int.self, forKey: .pageCount)
        targetLanguage = try container.decode(String.self, forKey: .targetLanguage)
        model = try container.decode(String.self, forKey: .model)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sourceFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFingerprint)
        sourceKind = try container.decodeIfPresent(SourceDocumentKind.self, forKey: .sourceKind) ?? .pdf
        totalUsage = try container.decodeIfPresent(AIUsage.self, forKey: .totalUsage)
    }
}
