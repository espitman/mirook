import Foundation

struct TranslatedTextPage: Identifiable, Codable {
    let id = UUID()
    let pageIndex: Int
    let sourceText: String
    let translatedText: String
    let isBlank: Bool

    init(
        pageIndex: Int,
        sourceText: String,
        translatedText: String,
        isBlank: Bool
    ) {
        self.pageIndex = pageIndex
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.isBlank = isBlank
    }

    var pageNumber: Int {
        pageIndex + 1
    }

    private enum CodingKeys: String, CodingKey {
        case pageIndex
        case sourceText
        case translatedText
        case isBlank
    }
}
