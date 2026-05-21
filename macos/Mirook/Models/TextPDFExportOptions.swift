import Foundation

enum TextPDFExportFont: String, CaseIterable, Codable, Identifiable {
    case vazirmatn
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vazirmatn:
            "Vazirmatn"
        case .system:
            "System"
        }
    }
}

struct TextPDFExportOptions: Codable {
    var font: TextPDFExportFont
    var bodyFontSize: Double
    var lineSpacing: Double
    var paragraphSpacing: Double
    var margin: Double

    static let `default` = TextPDFExportOptions(
        font: .vazirmatn,
        bodyFontSize: 15,
        lineSpacing: 6,
        paragraphSpacing: 14,
        margin: 56
    )
}
