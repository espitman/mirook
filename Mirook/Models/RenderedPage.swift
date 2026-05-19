import AppKit
import Foundation

struct RenderedPage: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let imageData: Data
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat

    var pageNumber: Int {
        pageIndex + 1
    }

    var image: NSImage? {
        NSImage(data: imageData)
    }
}
