import Foundation

enum SourceDocumentKind: String, Codable {
    case pdf
    case epub

    var displayName: String {
        switch self {
        case .pdf:
            "PDF"
        case .epub:
            "EPUB"
        }
    }
}
