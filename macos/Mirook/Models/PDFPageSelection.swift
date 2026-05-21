import Foundation

struct PDFPageSelection: Equatable {
    var startPage: Int
    var endPage: Int

    var normalized: ClosedRange<Int> {
        min(startPage, endPage)...max(startPage, endPage)
    }

    static let firstPage = PDFPageSelection(startPage: 1, endPage: 1)
}
