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
    let sourcePath: String
    let blocks: [EPUBSourceBlock]

    var text: String {
        blocks.compactMap { block in
            if case let .text(text) = block {
                return text
            }
            if case let .link(link) = block {
                return link.title
            }
            return nil
        }
        .joined(separator: "\n\n")
    }

    var pageNumber: Int {
        pageIndex + 1
    }
}

enum EPUBSourceBlock: Equatable {
    case text(String)
    case link(EPUBSourceLink)
    case image(EPUBSourceImage)
}

struct EPUBSourceLink: Equatable {
    let title: String
    let href: String
    let url: URL
    let targetPath: String?
}

struct EPUBSourceImage: Equatable {
    let path: String
    let data: Data
    let mimeType: String
    let altText: String?
}
