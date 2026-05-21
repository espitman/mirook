import AppKit
import Foundation
import PDFKit

enum PDFPageRendererError: LocalizedError {
    case missingPage
    case cannotCreateBitmapContext
    case cannotCreateImage
    case cannotCreatePNGData

    var errorDescription: String? {
        switch self {
        case .missingPage:
            "The selected PDF page could not be found."
        case .cannotCreateBitmapContext:
            "Mirook could not create a rendering context for this page."
        case .cannotCreateImage:
            "Mirook could not render this page as an image."
        case .cannotCreatePNGData:
            "Mirook could not encode the rendered page as PNG."
        }
    }
}

struct PDFPageRenderer {
    var scale: CGFloat = 2.0

    func render(document: PDFDocument, pageIndex: Int) throws -> RenderedPage {
        guard let page = document.page(at: pageIndex) else {
            throw PDFPageRendererError.missingPage
        }

        return try render(page: page, pageIndex: pageIndex)
    }

    func render(page: PDFPage, pageIndex: Int) throws -> RenderedPage {
        let bounds = page.bounds(for: .mediaBox)
        let pixelWidth = max(Int((bounds.width * scale).rounded(.up)), 1)
        let pixelHeight = max(Int((bounds.height * scale).rounded(.up)), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PDFPageRendererError.cannotCreateBitmapContext
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        guard let cgImage = context.makeImage() else {
            throw PDFPageRendererError.cannotCreateImage
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let imageData = bitmap.representation(using: .png, properties: [:]) else {
            throw PDFPageRendererError.cannotCreatePNGData
        }

        return RenderedPage(
            pageIndex: pageIndex,
            imageData: imageData,
            width: CGFloat(pixelWidth),
            height: CGFloat(pixelHeight),
            scale: scale
        )
    }
}
