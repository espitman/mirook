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
            let blocks = try readableBlocks(fromHTML: html, contentPath: contentPath, archive: archive)
            let chunks = pageChunks(from: blocks)
            for chunk in chunks {
                sourcePages.append(
                    EPUBSourcePage(
                        pageIndex: sourcePages.count,
                        title: documentTitle,
                        sourcePath: contentPath,
                        blocks: chunk
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

    private func pageChunks(from blocks: [EPUBSourceBlock]) -> [[EPUBSourceBlock]] {
        var chunks: [[EPUBSourceBlock]] = []
        var current: [EPUBSourceBlock] = []
        var currentCount = 0

        for block in blocks {
            let blockCount = switch block {
            case let .text(text):
                text.count
            case let .link(link):
                link.title.count
            case .image:
                420
            }

            if !current.isEmpty, currentCount + blockCount > Self.pageCharacterTarget {
                chunks.append(current)
                current = []
                currentCount = 0
            }

            current.append(block)
            currentCount += blockCount
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private func readableBlocks(
        fromHTML html: String,
        contentPath: String,
        archive: EPUBArchive
    ) throws -> [EPUBSourceBlock] {
        let contentBasePath = (contentPath as NSString).deletingLastPathComponent
        var markedHTML = html
        var images: [EPUBSourceImage?] = []
        var links: [EPUBSourceLink?] = []

        for match in regexMatches(in: markedHTML, pattern: #"(?is)<a\b[^>]*href\s*=\s*["'][^"']+["'][^>]*>.*?</a>"#).reversed() {
            let tag = (markedHTML as NSString).substring(with: match.range)
            guard let href = firstCapture(in: tag, pattern: #"(?i)\bhref\s*=\s*["']([^"']+)["']"#) else {
                continue
            }

            let title = readableText(fromHTML: tag)
            guard let link = sourceLink(from: href, title: title, contentPath: contentPath) else {
                markedHTML = (markedHTML as NSString).replacingCharacters(in: match.range, with: title)
                continue
            }

            let linkIndex = links.count
            links.append(link)
            markedHTML = (markedHTML as NSString).replacingCharacters(
                in: match.range,
                with: "\n\n[[MIROOK_LINK_\(linkIndex)]]\n\n"
            )
        }

        for match in regexMatches(in: markedHTML, pattern: #"(?is)<img\b[^>]*>"#).reversed() {
            let tag = (markedHTML as NSString).substring(with: match.range)
            guard let source = firstCapture(in: tag, pattern: #"(?i)\bsrc\s*=\s*["']([^"']+)["']"#) else {
                continue
            }

            let imageIndex = images.count
            images.append(try sourceImage(from: source, tag: tag, contentBasePath: contentBasePath, archive: archive))
            markedHTML = (markedHTML as NSString).replacingCharacters(
                in: match.range,
                with: "\n\n[[MIROOK_IMAGE_\(imageIndex)]]\n\n"
            )
        }

        let textWithMarkers = readableText(fromHTML: markedHTML)
        var blocks: [EPUBSourceBlock] = []
        var cursor = 0
        let nsText = textWithMarkers as NSString
        let markerMatches = regexMatches(in: textWithMarkers, pattern: #"\[\[MIROOK_(IMAGE|LINK)_(\d+)\]\]"#)

        for match in markerMatches {
            if match.range.location > cursor {
                appendTextBlocks(
                    from: nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                    to: &blocks
                )
            }

            if match.numberOfRanges > 2 {
                let markerType = nsText.substring(with: match.range(at: 1))
                let indexText = nsText.substring(with: match.range(at: 2))
                if let index = Int(indexText),
                   markerType == "IMAGE",
                   images.indices.contains(index),
                   let image = images[index] {
                    blocks.append(.image(image))
                } else if let index = Int(indexText),
                          markerType == "LINK",
                          links.indices.contains(index),
                          let link = links[index] {
                    blocks.append(.link(link))
                }
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsText.length {
            appendTextBlocks(
                from: nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor)),
                to: &blocks
            )
        }

        return blocks
    }

    private func sourceLink(from href: String, title: String, contentPath: String) -> EPUBSourceLink? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return nil
        }

        let decodedHref = href.removingPercentEncoding ?? href
        if let url = URL(string: decodedHref),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto"].contains(scheme) {
            return EPUBSourceLink(title: trimmedTitle, href: decodedHref, url: url, targetPath: nil)
        }

        let cleanedHref = decodedHref
            .components(separatedBy: "#").first?
            .components(separatedBy: "?").first ?? decodedHref
        let contentBasePath = (contentPath as NSString).deletingLastPathComponent
        let normalized = cleanedHref.isEmpty ? contentPath : normalizedPath(basePath: contentBasePath, href: cleanedHref)
        guard let fileURL = URL(string: "file:///\(normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalized)") else {
            return nil
        }
        return EPUBSourceLink(title: trimmedTitle, href: decodedHref, url: fileURL, targetPath: normalized)
    }

    private func appendTextBlocks(from text: String, to blocks: inout [EPUBSourceBlock]) {
        for paragraph in text.components(separatedBy: "\n\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            blocks.append(.text(trimmed))
        }
    }

    private func sourceImage(
        from source: String,
        tag: String,
        contentBasePath: String,
        archive: EPUBArchive
    ) throws -> EPUBSourceImage? {
        let cleanedSource = source
            .components(separatedBy: "#").first?
            .components(separatedBy: "?").first ?? source
        let normalizedSource = cleanedSource.hasPrefix("/") ? String(cleanedSource.dropFirst()) : cleanedSource
        let path = normalizedPath(basePath: contentBasePath, href: normalizedSource)

        guard let data = try archive.data(for: path) else {
            return nil
        }

        let altText = firstCapture(in: tag, pattern: #"(?i)\balt\s*=\s*["']([^"']*)["']"#)
            .map(decodeEntitiesAndTrim)

        return EPUBSourceImage(
            path: path,
            data: data,
            mimeType: mimeType(for: path),
            altText: altText?.isEmpty == true ? nil : altText
        )
    }

    private func mimeType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "jpg", "jpeg":
            "image/jpeg"
        case "png":
            "image/png"
        case "gif":
            "image/gif"
        case "webp":
            "image/webp"
        case "svg":
            "image/svg+xml"
        default:
            "application/octet-stream"
        }
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
        regexMatches(in: string, pattern: pattern, options: options).map {
            (string as NSString).substring(with: $0.range)
        }
    }

    private func regexMatches(
        in string: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let nsString = string as NSString
        return regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
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
