import AppKit
import Foundation

enum TranslatedPageRendererError: LocalizedError {
    case missingSourceImage
    case cannotCreateImage
    case cannotCreatePNGData

    var errorDescription: String? {
        switch self {
        case .missingSourceImage:
            "Mirook could not load the rendered source page image."
        case .cannotCreateImage:
            "Mirook could not create the translated page image."
        case .cannotCreatePNGData:
            "Mirook could not encode the translated page as PNG."
        }
    }
}

struct TranslatedPageRenderer {
    private let textLayoutEngine = PersianTextLayoutEngine()

    func render(renderedPage: RenderedPage, translatedPage: TranslatedPage) throws -> TranslatedRenderedPage {
        guard let sourceImage = NSImage(data: renderedPage.imageData) else {
            throw TranslatedPageRendererError.missingSourceImage
        }

        let canvasSize = CGSize(width: renderedPage.width, height: renderedPage.height)
        let outputImage = NSImage(size: canvasSize)
        var renderedBlockCount = 0

        outputImage.lockFocusFlipped(false)
        sourceImage.draw(in: CGRect(origin: .zero, size: canvasSize))
        for block in translatedPage.blocks {
            let box = normalizedRect(for: block.bbox, pageWidth: renderedPage.width, pageHeight: renderedPage.height)
            guard shouldRenderBlock(in: box, canvasSize: canvasSize) else {
                continue
            }
            coverOriginalText(in: box)
            textLayoutEngine.draw(block.translatedText, role: block.role, in: box)
            renderedBlockCount += 1
        }
        outputImage.unlockFocus()

        guard let tiffData = outputImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw TranslatedPageRendererError.cannotCreateImage
        }
        guard let imageData = bitmap.representation(using: .png, properties: [:]) else {
            throw TranslatedPageRendererError.cannotCreatePNGData
        }

        return TranslatedRenderedPage(
            pageIndex: renderedPage.pageIndex,
            imageData: imageData,
            width: renderedPage.width,
            height: renderedPage.height,
            scale: renderedPage.scale,
            blockCount: renderedBlockCount
        )
    }

    private func normalizedRect(for bbox: BoundingBox, pageWidth: CGFloat, pageHeight: CGFloat) -> CGRect {
        let x = max(0, CGFloat(bbox.x))
        let y = max(0, CGFloat(bbox.y))
        let width = max(1, min(CGFloat(bbox.width), pageWidth - x))
        let height = max(1, min(CGFloat(bbox.height), pageHeight - y))

        return CGRect(
            x: x,
            y: pageHeight - y - height,
            width: width,
            height: height
        )
    }

    private func coverOriginalText(in rect: CGRect) {
        let coverRect = rect.insetBy(dx: -2, dy: -2)
        NSColor.white.setFill()
        NSBezierPath(rect: coverRect).fill()
    }

    private func shouldRenderBlock(in rect: CGRect, canvasSize: CGSize) -> Bool {
        let canvasArea = canvasSize.width * canvasSize.height
        let rectArea = rect.width * rect.height

        guard rect.width > 1,
              rect.height > 1,
              rect.width < canvasSize.width * 0.98,
              rect.height < canvasSize.height * 0.98,
              rectArea < canvasArea * 0.6 else {
            return false
        }

        return true
    }
}
