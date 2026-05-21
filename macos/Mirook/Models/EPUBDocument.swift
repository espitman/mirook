import Foundation

struct EPUBDocument {
    let displayName: String
    let title: String
    let pages: [EPUBSourcePage]

    var pageCount: Int {
        pages.count
    }
}

struct EPUBSourcePage: Identifiable, Equatable {
    var id: Int { pageIndex }
    let pageIndex: Int
    let title: String?
    let text: String

    var pageNumber: Int {
        pageIndex + 1
    }
}
