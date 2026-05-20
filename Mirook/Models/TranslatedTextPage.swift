import Foundation

struct TranslatedTextPage: Identifiable, Codable {
    let id = UUID()
    let pageIndex: Int
    let sourceText: String
    let translatedText: String
    let isBlank: Bool
    let paragraphBlocks: [TranslatedTextParagraphBlock]
    let paragraphLayoutVersion: Int

    init(
        pageIndex: Int,
        sourceText: String,
        translatedText: String,
        isBlank: Bool,
        paragraphBlocks: [TranslatedTextParagraphBlock] = [],
        paragraphLayoutVersion: Int = 0
    ) {
        self.pageIndex = pageIndex
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.isBlank = isBlank
        self.paragraphBlocks = paragraphBlocks
        self.paragraphLayoutVersion = paragraphLayoutVersion
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
        case paragraphLayoutVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageIndex = try container.decode(Int.self, forKey: .pageIndex)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        translatedText = try container.decode(String.self, forKey: .translatedText)
        isBlank = try container.decode(Bool.self, forKey: .isBlank)
        paragraphBlocks = try container.decodeIfPresent([TranslatedTextParagraphBlock].self, forKey: .paragraphBlocks) ?? []
        paragraphLayoutVersion = try container.decodeIfPresent(Int.self, forKey: .paragraphLayoutVersion) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pageIndex, forKey: .pageIndex)
        try container.encode(sourceText, forKey: .sourceText)
        try container.encode(translatedText, forKey: .translatedText)
        try container.encode(isBlank, forKey: .isBlank)

        if !paragraphBlocks.isEmpty {
            try container.encode(paragraphBlocks, forKey: .paragraphBlocks)
            try container.encode(paragraphLayoutVersion, forKey: .paragraphLayoutVersion)
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
