import CoreGraphics
import Foundation

struct TranslatedPage: Codable {
    let pageWidth: Double
    let pageHeight: Double
    let blocks: [TranslatedTextBlock]
}

struct TranslatedTextBlock: Codable, Identifiable {
    let id: String
    let sourceText: String
    let translatedText: String
    let bbox: BoundingBox
    let role: TextRole
    let confidence: Double?
}

struct BoundingBox: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

extension BoundingBox {
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

enum TextRole: String, Codable, CaseIterable {
    case title
    case heading
    case paragraph
    case footnote
    case caption
    case pageNumber
    case other
}
