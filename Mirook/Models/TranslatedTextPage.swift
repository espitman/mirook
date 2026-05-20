import Foundation

struct TranslatedTextPage: Identifiable, Codable {
    let id = UUID()
    let pageIndex: Int
    let sourceText: String
    let translatedText: String
    let isBlank: Bool
    let paragraphBlocks: [TranslatedTextParagraphBlock]

    init(
        pageIndex: Int,
        sourceText: String,
        translatedText: String,
        isBlank: Bool,
        paragraphBlocks: [TranslatedTextParagraphBlock] = []
    ) {
        self.pageIndex = pageIndex
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.isBlank = isBlank
        self.paragraphBlocks = paragraphBlocks
    }

    var pageNumber: Int {
        pageIndex + 1
    }

    private enum CodingKeys: String, CodingKey {
        case pageIndex
        case sourceText
        case translatedText
        case isBlank
        case paragraphBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageIndex = try container.decode(Int.self, forKey: .pageIndex)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        translatedText = try container.decode(String.self, forKey: .translatedText)
        isBlank = try container.decode(Bool.self, forKey: .isBlank)
        paragraphBlocks = try container.decodeIfPresent([TranslatedTextParagraphBlock].self, forKey: .paragraphBlocks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pageIndex, forKey: .pageIndex)
        try container.encode(sourceText, forKey: .sourceText)
        try container.encode(translatedText, forKey: .translatedText)
        try container.encode(isBlank, forKey: .isBlank)

        if !paragraphBlocks.isEmpty {
            try container.encode(paragraphBlocks, forKey: .paragraphBlocks)
        }
    }
}

struct TranslatedTextParagraphBlock: Identifiable, Codable {
    let id: String
    let sourceText: String
    let translatedText: String
    let pdfBounds: BoundingBox
    let role: TextRole
    let confidence: Double
}
