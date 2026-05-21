import AppKit
import CoreGraphics
import CoreText
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
    private let frameSafetyPadding: CGFloat = 12
    private let minimumFrameHeight: CGFloat = 72

    func export(
        pages: [TranslatedTextPage],
        to url: URL,
        options: TextPDFExportOptions = .default
    ) throws {
        Self.registerBundledFontsIfNeeded()

        let sortedPages = pages.sorted { $0.pageIndex < $1.pageIndex }
        guard !sortedPages.isEmpty else {
            throw TextPDFExportServiceError.noPages
        }

        let margin = CGFloat(options.margin)
        let paragraphSpacing = CGFloat(options.paragraphSpacing)
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

            let attributedText = attributedString(for: normalizedText, role: role, options: options)
            let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
            let fullLength = attributedText.length
            var rangeStart = 0

            while rangeStart < fullLength {
                beginPageIfNeeded()

                var availableHeight = pageSize.height - margin - cursorY
                if availableHeight < minimumFrameHeight {
                    endPageIfNeeded()
                    beginPageIfNeeded()
                    availableHeight = pageSize.height - margin - cursorY
                }

                let frameHeight = max(availableHeight - frameSafetyPadding, 1)
                let frameRect = CGRect(
                    x: margin,
                    y: pageSize.height - cursorY - frameHeight,
                    width: pageSize.width - margin * 2,
                    height: frameHeight
                )
                let path = CGPath(rect: frameRect, transform: nil)
                let requestedRange = CFRange(
                    location: rangeStart,
                    length: fullLength - rangeStart
                )
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    requestedRange,
                    path,
                    nil
                )
                let visibleRange = CTFrameGetVisibleStringRange(frame)

                guard visibleRange.length > 0 else {
                    endPageIfNeeded()
                    beginPageIfNeeded()
                    continue
                }

                context.saveGState()
                context.textMatrix = .identity
                CTFrameDraw(frame, context)
                context.restoreGState()

                let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                    framesetter,
                    visibleRange,
                    nil,
                    CGSize(width: frameRect.width, height: .greatestFiniteMagnitude),
                    nil
                )

                let usedHeight = min(
                    frameHeight,
                    max(1, ceil(suggestedSize.height + frameSafetyPadding))
                )

                cursorY += usedHeight + paragraphSpacing
                rangeStart += visibleRange.length
            }
        }

        for page in sortedPages {
            if page.isBlank {
                beginPageIfNeeded()
                endPageIfNeeded()
                continue
            }

            draw("صفحه \(page.pageNumber)", role: .caption)
            for paragraph in page.translatedText.components(separatedBy: .newlines) {
                draw(paragraph, role: .paragraph)
            }
            endPageIfNeeded()
        }

        endPageIfNeeded()
        context.closePDF()
    }

    private func attributedString(
        for text: String,
        role: TextRole,
        options: TextPDFExportOptions
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = CGFloat(options.lineSpacing)
        paragraphStyle.paragraphSpacing = CGFloat(options.paragraphSpacing)

        let bodyFontSize = CGFloat(options.bodyFontSize)
        let fontSize: CGFloat = role == .caption ? max(bodyFontSize - 4, 9) : bodyFontSize
        let weight: NSFont.Weight = role == .caption ? .semibold : .regular

        return NSAttributedString(string: text, attributes: [
            .font: font(for: options.font, role: role, size: fontSize, weight: weight),
            .foregroundColor: NSColor(calibratedWhite: 0.06, alpha: 1),
            .paragraphStyle: paragraphStyle
        ])
    }

    private func font(
        for exportFont: TextPDFExportFont,
        role: TextRole,
        size: CGFloat,
        weight: NSFont.Weight
    ) -> NSFont {
        switch exportFont {
        case .vazirmatn:
            let fontName = role == .caption ? "Vazirmatn-Bold" : "Vazirmatn-Regular"
            return NSFont(name: fontName, size: size) ?? NSFont(name: "Vazirmatn", size: size) ?? .systemFont(ofSize: size, weight: weight)
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        }
    }

    private static func registerBundledFontsIfNeeded() {
        for fontName in ["Vazirmatn-Regular", "Vazirmatn-Bold"] {
            guard let url = bundledFontURL(named: fontName) else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static func bundledFontURL(named fontName: String) -> URL? {
        Bundle.main.url(forResource: fontName, withExtension: "ttf") ??
            Bundle.main.url(forResource: fontName, withExtension: "ttf", subdirectory: "Fonts") ??
            Bundle.main.url(forResource: fontName, withExtension: "ttf", subdirectory: "Resources/Fonts")
    }
}
