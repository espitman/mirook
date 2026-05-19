import Foundation

struct TranslatedTextPage: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let sourceText: String
    let translatedText: String

    var pageNumber: Int {
        pageIndex + 1
    }
}
