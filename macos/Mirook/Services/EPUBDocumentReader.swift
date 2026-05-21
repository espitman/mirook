import Compression
import Foundation

enum EPUBDocumentReaderError: LocalizedError {
    case invalidArchive
    case missingContainer
    case missingPackage
    case missingReadableContent
    case unsupportedCompressionMethod(UInt16)
    case corruptEntry(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            "The selected EPUB could not be opened."
        case .missingContainer:
            "The EPUB container file is missing."
        case .missingPackage:
            "The EPUB package file is missing."
        case .missingReadableContent:
            "Mirook could not find readable text content in this EPUB."
        case .unsupportedCompressionMethod(let method):
            "This EPUB uses unsupported ZIP compression method \(method)."
        case .corruptEntry(let name):
            "The EPUB entry \(name) could not be read."
        }
    }
}

struct EPUBDocumentReader {
    private static let pageCharacterTarget = 2_800

    func load(from url: URL) throws -> EPUBDocument {
        let data = try Data(contentsOf: url)
        return try load(data: data, displayName: url.deletingPathExtension().lastPathComponent)
    }

    func load(data: Data, displayName: String) throws -> EPUBDocument {
        let archive = try EPUBArchive(data: data)
        guard let containerData = try archive.data(for: "META-INF/container.xml") else {
            throw EPUBDocumentReaderError.missingContainer
        }

        let containerXML = decodedString(containerData)
        guard let packagePath = firstCapture(
            in: containerXML,
            pattern: #"full-path\s*=\s*["']([^"']+)["']"#
        ) else {
            throw EPUBDocumentReaderError.missingPackage
        }

        guard let packageData = try archive.data(for: packagePath) else {
            throw EPUBDocumentReaderError.missingPackage
        }

        let packageXML = decodedString(packageData)
        let basePath = (packagePath as NSString).deletingLastPathComponent
        let title = firstCapture(
            in: packageXML,
            pattern: #"<dc:title[^>]*>(.*?)</dc:title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ).map(decodeEntitiesAndTrim) ?? displayName

        let manifest = manifestItems(from: packageXML)
        let spineIDs = spineItemIDs(from: packageXML)
        let orderedItems = spineIDs.compactMap { manifest[$0] }
        let readableItems = orderedItems.isEmpty ? Array(manifest.values) : orderedItems

        var sourcePages: [EPUBSourcePage] = []
        for item in readableItems where item.isReadableDocument {
            let contentPath = normalizedPath(basePath: basePath, href: item.href)
            guard let contentData = try archive.data(for: contentPath) else {
                continue
            }

            let html = decodedString(contentData)
            let documentTitle = firstCapture(
                in: html,
                pattern: #"<title[^>]*>(.*?)</title>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ).map(decodeEntitiesAndTrim)
            let text = readableText(fromHTML: html)
            let chunks = pageChunks(from: text)
            for chunk in chunks {
                sourcePages.append(
                    EPUBSourcePage(
                        pageIndex: sourcePages.count,
                        title: documentTitle,
                        text: chunk
                    )
                )
            }
        }

        guard !sourcePages.isEmpty else {
            throw EPUBDocumentReaderError.missingReadableContent
        }

        return EPUBDocument(displayName: displayName, title: title, pages: sourcePages)
    }

    private func manifestItems(from packageXML: String) -> [String: EPUBManifestItem] {
        let pattern = #"<item\b([^>]*)/?>"#
        return matches(in: packageXML, pattern: pattern, options: [.caseInsensitive]).reduce(into: [:]) { result, itemTag in
            guard let id = firstCapture(in: itemTag, pattern: #"id\s*=\s*["']([^"']+)["']"#),
                  let href = firstCapture(in: itemTag, pattern: #"href\s*=\s*["']([^"']+)["']"#) else {
                return
            }

            let mediaType = firstCapture(in: itemTag, pattern: #"media-type\s*=\s*["']([^"']+)["']"#) ?? ""
            result[id] = EPUBManifestItem(id: id, href: href, mediaType: mediaType)
        }
    }

    private func spineItemIDs(from packageXML: String) -> [String] {
        matches(in: packageXML, pattern: #"<itemref\b([^>]*)/?>"#, options: [.caseInsensitive]).compactMap { itemref in
            firstCapture(in: itemref, pattern: #"idref\s*=\s*["']([^"']+)["']"#)
        }
    }

    private func pageChunks(from text: String) -> [String] {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current: [String] = []
        var currentCount = 0

        for paragraph in paragraphs {
            if !current.isEmpty, currentCount + paragraph.count > Self.pageCharacterTarget {
                chunks.append(current.joined(separator: "\n\n"))
                current = []
                currentCount = 0
            }

            current.append(paragraph)
            currentCount += paragraph.count
        }

        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n\n"))
        }

        return chunks
    }

    private func readableText(fromHTML html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: #"(?is)<(head|script|style|svg|math)\b.*?</\1>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?i)<\s*br\s*/?\s*>"#,
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?i)</\s*(p|div|section|article|header|footer|blockquote|li|h[1-6])\s*>"#,
            with: "\n\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
        text = decodeEntitiesAndTrim(text)
        text = text.replacingOccurrences(of: #"[ \t\f]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodedString(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)
    }

    private func decodeEntitiesAndTrim(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")

        decoded = replacingNumericEntities(in: decoded, pattern: #"&#(\d+);"#, radix: 10)
        decoded = replacingNumericEntities(in: decoded, pattern: #"&#x([0-9a-fA-F]+);"#, radix: 16)
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacingNumericEntities(in text: String, pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length)).reversed()
        var result = text
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let valueText = nsString.substring(with: match.range(at: 1))
            guard let scalarValue = UInt32(valueText, radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            result = (result as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
        }
        return result
    }

    private func normalizedPath(basePath: String, href: String) -> String {
        let decodedHref = href.removingPercentEncoding ?? href
        guard !basePath.isEmpty else {
            return decodedHref
        }

        let combined = (basePath as NSString).appendingPathComponent(decodedHref)
        let components = combined.split(separator: "/").reduce(into: [String]()) { result, part in
            switch part {
            case ".":
                return
            case "..":
                _ = result.popLast()
            default:
                result.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }

    private func firstCapture(
        in string: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let nsString = string as NSString
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: nsString.length)),
              match.numberOfRanges > 1 else {
            return nil
        }

        return nsString.substring(with: match.range(at: 1))
    }

    private func matches(
        in string: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let nsString = string as NSString
        return regex.matches(in: string, range: NSRange(location: 0, length: nsString.length)).map {
            nsString.substring(with: $0.range)
        }
    }
}

private struct EPUBManifestItem {
    let id: String
    let href: String
    let mediaType: String

    var isReadableDocument: Bool {
        let lowercasedType = mediaType.lowercased()
        let lowercasedHref = href.lowercased()
        return lowercasedType == "application/xhtml+xml"
            || lowercasedType == "text/html"
            || lowercasedHref.hasSuffix(".xhtml")
            || lowercasedHref.hasSuffix(".html")
            || lowercasedHref.hasSuffix(".htm")
    }
}

private struct EPUBArchive {
    private let data: Data
    private let entries: [String: EPUBArchiveEntry]

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readEntries(from: data)
    }

    func data(for path: String) throws -> Data? {
        guard let entry = entries[path] ?? entries[path.removingPercentEncoding ?? path] else {
            return nil
        }

        guard entry.localHeaderOffset + 30 <= data.count else {
            throw EPUBDocumentReaderError.corruptEntry(path)
        }

        let nameLength = Int(data.uint16LE(at: entry.localHeaderOffset + 26))
        let extraLength = Int(data.uint16LE(at: entry.localHeaderOffset + 28))
        let start = entry.localHeaderOffset + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= data.count else {
            throw EPUBDocumentReaderError.corruptEntry(path)
        }

        let compressedData = data[start..<end]
        switch entry.compressionMethod {
        case 0:
            return Data(compressedData)
        case 8:
            return try inflate(compressedData, outputSize: entry.uncompressedSize, path: path)
        default:
            throw EPUBDocumentReaderError.unsupportedCompressionMethod(entry.compressionMethod)
        }
    }

    private func inflate(_ compressedData: Data.SubSequence, outputSize: Int, path: String) throws -> Data {
        guard outputSize > 0 else {
            return Data()
        }

        var output = Data(count: outputSize)
        let decodedCount = output.withUnsafeMutableBytes { outputBuffer in
            compressedData.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    outputSize,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    compressedData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decodedCount == outputSize else {
            throw EPUBDocumentReaderError.corruptEntry(path)
        }

        return output
    }

    private static func readEntries(from data: Data) throws -> [String: EPUBArchiveEntry] {
        guard let eocdOffset = data.lastOffset(of: 0x06054b50),
              eocdOffset + 22 <= data.count else {
            throw EPUBDocumentReaderError.invalidArchive
        }

        let entryCount = Int(data.uint16LE(at: eocdOffset + 10))
        let centralDirectoryOffset = Int(data.uint32LE(at: eocdOffset + 16))
        var cursor = centralDirectoryOffset
        var result: [String: EPUBArchiveEntry] = [:]

        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count,
                  data.uint32LE(at: cursor) == 0x02014b50 else {
                throw EPUBDocumentReaderError.invalidArchive
            }

            let compressionMethod = data.uint16LE(at: cursor + 10)
            let compressedSize = Int(data.uint32LE(at: cursor + 20))
            let uncompressedSize = Int(data.uint32LE(at: cursor + 24))
            let nameLength = Int(data.uint16LE(at: cursor + 28))
            let extraLength = Int(data.uint16LE(at: cursor + 30))
            let commentLength = Int(data.uint16LE(at: cursor + 32))
            let localHeaderOffset = Int(data.uint32LE(at: cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength

            guard nameEnd <= data.count else {
                throw EPUBDocumentReaderError.invalidArchive
            }

            if let name = String(data: data[nameStart..<nameEnd], encoding: .utf8),
               !name.hasSuffix("/") {
                result[name] = EPUBArchiveEntry(
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            }

            cursor = nameEnd + extraLength + commentLength
        }

        return result
    }
}

private struct EPUBArchiveEntry {
    let compressionMethod: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1]) << 8
        return b0 | b1
    }

    func uint32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1]) << 8
        let b2 = UInt32(self[offset + 2]) << 16
        let b3 = UInt32(self[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    func lastOffset(of signature: UInt32) -> Int? {
        guard count >= 4 else { return nil }

        var offset = count - 4
        while offset >= 0 {
            if uint32LE(at: offset) == signature {
                return offset
            }
            offset -= 1
        }

        return nil
    }
}
