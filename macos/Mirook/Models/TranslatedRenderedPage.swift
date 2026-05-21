import AppKit
import Foundation

struct TranslatedRenderedPage: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let imageData: Data
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let blockCount: Int

    var pageNumber: Int {
        pageIndex + 1
    }

    var image: NSImage? {
        NSImage(data: imageData)
    }
}
