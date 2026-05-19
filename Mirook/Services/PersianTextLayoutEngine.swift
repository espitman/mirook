import AppKit
import Foundation

struct PersianTextLayoutEngine {
    private let minimumFontSize: CGFloat = 6
    private let maximumFontSize: CGFloat = 28

    func draw(_ text: String, role: TextRole, in rect: CGRect) {
        let insetRect = rect.insetBy(dx: 4, dy: 3)
        guard insetRect.width > 4, insetRect.height > 4 else { return }

        let fontSize = fittingFontSize(for: text, role: role, in: insetRect)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.alignment = alignment(for: role)
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 1

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: role, size: fontSize),
            .foregroundColor: NSColor(calibratedWhite: 0.06, alpha: 1),
            .paragraphStyle: paragraphStyle
        ]

        NSString(string: text).draw(
            with: insetRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }

    private func fittingFontSize(for text: String, role: TextRole, in rect: CGRect) -> CGFloat {
        let preferredSize = min(maximumFontSize, max(minimumFontSize, rect.height * preferredHeightRatio(for: role)))
        var size = preferredSize

        while size > minimumFontSize {
            if measuredSize(for: text, role: role, fontSize: size, width: rect.width).height <= rect.height {
                return size
            }
            size -= 1
        }

        return minimumFontSize
    }

    private func measuredSize(for text: String, role: TextRole, fontSize: CGFloat, width: CGFloat) -> CGSize {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.alignment = alignment(for: role)
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 1

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: role, size: fontSize),
            .paragraphStyle: paragraphStyle
        ]

        return NSString(string: text).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).size
    }

    private func font(for role: TextRole, size: CGFloat) -> NSFont {
        let weight: NSFont.Weight = switch role {
        case .title:
            .bold
        case .heading:
            .semibold
        default:
            .regular
        }

        if let font = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.default) {
            return NSFont(descriptor: font, size: size) ?? .systemFont(ofSize: size, weight: weight)
        }

        return .systemFont(ofSize: size, weight: weight)
    }

    private func alignment(for role: TextRole) -> NSTextAlignment {
        switch role {
        case .title, .heading:
            .center
        default:
            .right
        }
    }

    private func preferredHeightRatio(for role: TextRole) -> CGFloat {
        switch role {
        case .title:
            0.42
        case .heading:
            0.36
        case .footnote, .caption, .pageNumber:
            0.28
        default:
            0.32
        }
    }
}
