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
    var totalUsage: AIUsage? = nil
}
