import AppKit
import CoreGraphics
import Foundation

enum TextPDFExportServiceError: LocalizedError {
    case noPages
    case cannotCreateContext(URL)

    var errorDescription: String? {
        switch self {
        case .noPages:
            "Translate at least one text page before exporting."
        case .cannotCreateContext(let url):
            "Mirook could not create a text PDF at \(url.lastPathComponent)."
        }
    }
}

struct TextPDFExportService {
    private let pageSize = CGSize(width: 595, height: 842)
    private let margin: CGFloat = 56
    private let paragraphSpacing: CGFloat = 12

    func export(pages: [TranslatedTextPage], to url: URL) throws {
        let sortedPages = pages.sorted { $0.pageIndex < $1.pageIndex }
        guard !sortedPages.isEmpty else {
            throw TextPDFExportServiceError.noPages
        }

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw TextPDFExportServiceError.cannotCreateContext(url)
        }

        var cursorY = margin
        var pageStarted = false

        func beginPageIfNeeded() {
            guard !pageStarted else { return }
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: pageSize))
            pageStarted = true
            cursorY = margin
        }

        func endPageIfNeeded() {
            guard pageStarted else { return }
            context.endPDFPage()
            pageStarted = false
        }

        func draw(_ text: String, role: TextRole) {
            beginPageIfNeeded()

            let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else { return }

            let attributes = attributes(for: role)
            let textWidth = pageSize.width - margin * 2
            var remainingWords = normalizedText.split(whereSeparator: \.isWhitespace).map(String.init)

            if remainingWords.isEmpty {
                remainingWords = [normalizedText]
            }

            while !remainingWords.isEmpty {
                let availableHeight = pageSize.height - margin - cursorY
                if availableHeight < 48 {
                    endPageIfNeeded()
                    beginPageIfNeeded()
                    continue
                }

                let fittingCount = bestFittingWordCount(
                    words: remainingWords,
                    width: textWidth,
                    maxHeight: availableHeight,
                    attributes: attributes
                )
                let count = max(1, fittingCount)
                let chunk = remainingWords.prefix(count).joined(separator: " ")
                let height = measuredHeight(for: chunk, width: textWidth, attributes: attributes)
                let drawRect = CGRect(
                    x: margin,
                    y: pageSize.height - cursorY - height,
                    width: textWidth,
                    height: height
                )

                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                NSString(string: chunk).draw(
                    with: drawRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes
                )
                NSGraphicsContext.restoreGraphicsState()

                cursorY += height + paragraphSpacing
                remainingWords.removeFirst(count)
            }
        }

        for page in sortedPages {
            draw("صفحه \(page.pageNumber)", role: .caption)
            for paragraph in page.translatedText.components(separatedBy: .newlines) {
                draw(paragraph, role: .paragraph)
            }
            endPageIfNeeded()
        }

        endPageIfNeeded()
        context.closePDF()
    }

    private func attributes(for role: TextRole) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = paragraphSpacing

        let fontSize: CGFloat = role == .caption ? 11 : 15
        let weight: NSFont.Weight = role == .caption ? .semibold : .regular

        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor(calibratedWhite: 0.06, alpha: 1),
            .paragraphStyle: paragraphStyle
        ]
    }

    private func bestFittingWordCount(
        words: [String],
        width: CGFloat,
        maxHeight: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> Int {
        var low = 1
        var high = words.count
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            let text = words.prefix(mid).joined(separator: " ")
            let height = measuredHeight(for: text, width: width, attributes: attributes)
            if height <= maxHeight {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best
    }

    private func measuredHeight(
        for text: String,
        width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        ceil(
            NSString(string: text).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            ).height
        )
    }
}
