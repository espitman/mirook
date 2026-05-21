import Foundation

enum EPUBExportServiceError: LocalizedError {
    case noPages
    case cannotWrite(URL)
    case entryTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .noPages:
            "Translate at least one text page before exporting EPUB."
        case .cannotWrite(let url):
            "Mirook could not write an EPUB at \(url.lastPathComponent)."
        case .entryTooLarge(let name):
            "The EPUB entry \(name) is too large to write."
        }
    }
}

struct EPUBExportService {
    func export(
        pages: [TranslatedTextPage],
        displayName: String,
        to url: URL,
        options: TextPDFExportOptions = .default
    ) throws {
        let sortedPages = pages.sorted { $0.pageIndex < $1.pageIndex }
        guard !sortedPages.isEmpty else {
            throw EPUBExportServiceError.noPages
        }

        var entries: [ZIPEntry] = []
        entries.append(ZIPEntry(path: "mimetype", data: Data("application/epub+zip".utf8)))
        entries.append(ZIPEntry(path: "META-INF/container.xml", data: Data(containerXML.utf8)))
        entries.append(ZIPEntry(path: "OEBPS/Styles/book.css", data: Data(stylesheet(options: options).utf8)))

        if let regularFont = bundledFontData(named: "Vazirmatn-Regular") {
            entries.append(ZIPEntry(path: "OEBPS/Fonts/Vazirmatn-Regular.ttf", data: regularFont))
        }
        if let boldFont = bundledFontData(named: "Vazirmatn-Bold") {
            entries.append(ZIPEntry(path: "OEBPS/Fonts/Vazirmatn-Bold.ttf", data: boldFont))
        }

        let pageItems = sortedPages.map { page in
            EPUBPageItem(
                id: "page-\(String(format: "%04d", page.pageNumber))",
                href: "Text/page-\(String(format: "%04d", page.pageNumber)).xhtml",
                label: "Page \(page.pageNumber)",
                page: page
            )
        }

        entries.append(ZIPEntry(path: "OEBPS/nav.xhtml", data: Data(navXHTML(title: displayName, pages: pageItems).utf8)))
        entries.append(ZIPEntry(path: "OEBPS/toc.ncx", data: Data(tocNCX(title: displayName, pages: pageItems).utf8)))
        entries.append(ZIPEntry(path: "OEBPS/package.opf", data: Data(packageOPF(title: displayName, pages: pageItems).utf8)))

        for item in pageItems {
            entries.append(
                ZIPEntry(
                    path: "OEBPS/\(item.href)",
                    data: Data(pageXHTML(title: item.label, page: item.page).utf8)
                )
            )
        }

        do {
            try ZIPArchiveWriter.write(entries: entries, to: url)
        } catch let error as EPUBExportServiceError {
            throw error
        } catch {
            throw EPUBExportServiceError.cannotWrite(url)
        }
    }

    private var containerXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
    }

    private func packageOPF(title: String, pages: [EPUBPageItem]) -> String {
        let modified = ISO8601DateFormatter().string(from: Date())
        let escapedTitle = escapeXML(title)
        let pageManifest = pages.map {
            #"    <item id="\#($0.id)" href="\#($0.href)" media-type="application/xhtml+xml"/>"#
        }.joined(separator: "\n")
        let spine = pages.map {
            #"    <itemref idref="\#($0.id)"/>"#
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="fa" dir="rtl">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="book-id">urn:uuid:\(UUID().uuidString)</dc:identifier>
            <dc:title>\(escapedTitle)</dc:title>
            <dc:language>fa</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="css" href="Styles/book.css" media-type="text/css"/>
            <item id="vazirmatn-regular" href="Fonts/Vazirmatn-Regular.ttf" media-type="font/ttf"/>
            <item id="vazirmatn-bold" href="Fonts/Vazirmatn-Bold.ttf" media-type="font/ttf"/>
        \(pageManifest)
          </manifest>
          <spine toc="ncx" page-progression-direction="rtl">
        \(spine)
          </spine>
        </package>
        """
    }

    private func navXHTML(title: String, pages: [EPUBPageItem]) -> String {
        let escapedTitle = escapeXML(title)
        let links = pages.map {
            #"      <li><a href="\#($0.href)">\#(escapeXML($0.label))</a></li>"#
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="fa" lang="fa" dir="rtl">
        <head>
          <title>\(escapedTitle)</title>
          <link rel="stylesheet" type="text/css" href="Styles/book.css"/>
        </head>
        <body>
          <nav epub:type="toc" id="toc">
            <h1>\(escapedTitle)</h1>
            <ol>
        \(links)
            </ol>
          </nav>
        </body>
        </html>
        """
    }

    private func tocNCX(title: String, pages: [EPUBPageItem]) -> String {
        let navPoints = pages.enumerated().map { index, item in
            """
            <navPoint id="navPoint-\(index + 1)" playOrder="\(index + 1)">
              <navLabel><text>\(escapeXML(item.label))</text></navLabel>
              <content src="\(item.href)"/>
            </navPoint>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head>
            <meta name="dtb:uid" content="urn:uuid:\(UUID().uuidString)"/>
            <meta name="dtb:depth" content="1"/>
            <meta name="dtb:totalPageCount" content="0"/>
            <meta name="dtb:maxPageNumber" content="0"/>
          </head>
          <docTitle><text>\(escapeXML(title))</text></docTitle>
          <navMap>
        \(navPoints)
          </navMap>
        </ncx>
        """
    }

    private func pageXHTML(title: String, page: TranslatedTextPage) -> String {
        let body = paragraphs(for: page).map { paragraph in
            let className = className(for: paragraph.role)
            return #"    <p class="\#(className)">\#(escapeXML(paragraph.text))</p>"#
        }.joined(separator: "\n")
        let pageBody = body.isEmpty ? #"    <div class="blank-page" aria-label="Blank page"></div>"# : body

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="fa" lang="fa" dir="rtl">
        <head>
          <title>\(escapeXML(title))</title>
          <link rel="stylesheet" type="text/css" href="../Styles/book.css"/>
        </head>
        <body>
          <section class="page" id="page-\(page.pageNumber)">
        \(pageBody)
          </section>
        </body>
        </html>
        """
    }

    private func stylesheet(options: TextPDFExportOptions) -> String {
        let bodySize = max(11, min(32, options.bodyFontSize))
        let lineHeight = max(1.2, min(2.4, (bodySize + options.lineSpacing) / bodySize))
        let paragraphMargin = max(0.4, min(3.0, options.paragraphSpacing / bodySize))

        return """
        @font-face {
          font-family: "Vazirmatn";
          src: url("../Fonts/Vazirmatn-Regular.ttf") format("truetype");
          font-weight: 400;
          font-style: normal;
        }
        @font-face {
          font-family: "Vazirmatn";
          src: url("../Fonts/Vazirmatn-Bold.ttf") format("truetype");
          font-weight: 700;
          font-style: normal;
        }
        html, body {
          direction: rtl;
          writing-mode: horizontal-tb;
        }
        body {
          font-family: "Vazirmatn", system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
          font-size: \(String(format: "%.1f", bodySize))px;
          line-height: \(String(format: "%.2f", lineHeight));
          text-align: right;
        }
        .page {
          max-width: 42rem;
          margin: 0 auto;
          padding: 1rem 0;
          page-break-after: always;
          break-after: page;
        }
        p {
          margin: 0 0 \(String(format: "%.2f", paragraphMargin))em;
          text-align: right;
          direction: rtl;
          unicode-bidi: plaintext;
          font-size: 1em;
          font-weight: 400;
        }
        .title, .heading {
          display: block;
          margin: \(String(format: "%.2f", paragraphMargin))em 0 \(String(format: "%.2f", paragraphMargin))em;
          text-align: right;
          direction: rtl;
          unicode-bidi: plaintext;
          font-size: 1em;
          font-weight: 400;
          page-break-inside: avoid;
          break-inside: avoid;
        }
        .caption, .footnote, .source-page-number, .other, .paragraph {
          font-size: 1em;
          font-weight: 400;
          color: inherit;
        }
        .blank-page {
          min-height: 70vh;
        }
        """
    }

    private func paragraphs(for page: TranslatedTextPage) -> [EPUBParagraph] {
        return fallbackParagraphs(from: page.translatedText).map {
            EPUBParagraph(text: $0, role: .paragraph)
        }
    }

    private func fallbackParagraphs(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        return normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func className(for role: TextRole) -> String {
        switch role {
        case .title:
            "title"
        case .heading:
            "heading"
        case .footnote:
            "footnote"
        case .caption:
            "caption"
        case .pageNumber:
            "source-page-number"
        case .other:
            "other"
        case .paragraph:
            "paragraph"
        }
    }

    private func bundledFontData(named fontName: String) -> Data? {
        let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") ??
            Bundle.main.url(forResource: fontName, withExtension: "ttf", subdirectory: "Fonts") ??
            Bundle.main.url(forResource: fontName, withExtension: "ttf", subdirectory: "Resources/Fonts")
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }

    private func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private struct EPUBPageItem {
    let id: String
    let href: String
    let label: String
    let page: TranslatedTextPage
}

private struct EPUBParagraph {
    let text: String
    let role: TextRole
}

private struct ZIPEntry {
    let path: String
    let data: Data
}

private struct ZIPCentralDirectoryEntry {
    let entry: ZIPEntry
    let crc32: UInt32
    let localHeaderOffset: UInt32
}

private enum ZIPArchiveWriter {
    static func write(entries: [ZIPEntry], to url: URL) throws {
        var archive = Data()
        var centralDirectoryEntries: [ZIPCentralDirectoryEntry] = []

        for entry in entries {
            let offset = try checkedUInt32(archive.count, entryName: entry.path)
            let crc = crc32(entry.data)
            try appendLocalFileHeader(entry, crc32: crc, to: &archive)
            archive.append(entry.data)
            centralDirectoryEntries.append(
                ZIPCentralDirectoryEntry(
                    entry: entry,
                    crc32: crc,
                    localHeaderOffset: offset
                )
            )
        }

        let centralDirectoryOffset = try checkedUInt32(archive.count, entryName: "central-directory")
        var centralDirectory = Data()
        for entry in centralDirectoryEntries {
            try appendCentralDirectoryHeader(entry, to: &centralDirectory)
        }
        let centralDirectorySize = try checkedUInt32(centralDirectory.count, entryName: "central-directory")
        archive.append(centralDirectory)
        try appendEndOfCentralDirectory(
            entryCount: centralDirectoryEntries.count,
            centralDirectorySize: centralDirectorySize,
            centralDirectoryOffset: centralDirectoryOffset,
            to: &archive
        )

        let folderURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try archive.write(to: url, options: .atomic)
    }

    private static func appendLocalFileHeader(_ entry: ZIPEntry, crc32: UInt32, to data: inout Data) throws {
        let nameData = Data(entry.path.utf8)
        try validate(entry: entry, nameData: nameData)

        data.appendUInt32LE(0x0403_4b50)
        data.appendUInt16LE(20)
        data.appendUInt16LE(0x0800)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt32LE(crc32)
        data.appendUInt32LE(UInt32(entry.data.count))
        data.appendUInt32LE(UInt32(entry.data.count))
        data.appendUInt16LE(UInt16(nameData.count))
        data.appendUInt16LE(0)
        data.append(nameData)
    }

    private static func appendCentralDirectoryHeader(
        _ item: ZIPCentralDirectoryEntry,
        to data: inout Data
    ) throws {
        let entry = item.entry
        let nameData = Data(entry.path.utf8)
        try validate(entry: entry, nameData: nameData)

        data.appendUInt32LE(0x0201_4b50)
        data.appendUInt16LE(20)
        data.appendUInt16LE(20)
        data.appendUInt16LE(0x0800)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt32LE(item.crc32)
        data.appendUInt32LE(UInt32(entry.data.count))
        data.appendUInt32LE(UInt32(entry.data.count))
        data.appendUInt16LE(UInt16(nameData.count))
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt32LE(0)
        data.appendUInt32LE(item.localHeaderOffset)
        data.append(nameData)
    }

    private static func appendEndOfCentralDirectory(
        entryCount: Int,
        centralDirectorySize: UInt32,
        centralDirectoryOffset: UInt32,
        to data: inout Data
    ) throws {
        guard entryCount <= Int(UInt16.max) else {
            throw EPUBExportServiceError.entryTooLarge("entry-count")
        }

        data.appendUInt32LE(0x0605_4b50)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(UInt16(entryCount))
        data.appendUInt16LE(UInt16(entryCount))
        data.appendUInt32LE(centralDirectorySize)
        data.appendUInt32LE(centralDirectoryOffset)
        data.appendUInt16LE(0)
    }

    private static func validate(entry: ZIPEntry, nameData: Data) throws {
        guard nameData.count <= Int(UInt16.max),
              entry.data.count <= Int(UInt32.max) else {
            throw EPUBExportServiceError.entryTooLarge(entry.path)
        }
    }

    private static func checkedUInt32(_ value: Int, entryName: String) throws -> UInt32 {
        guard value <= Int(UInt32.max) else {
            throw EPUBExportServiceError.entryTooLarge(entryName)
        }
        return UInt32(value)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let tableIndex = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ crcTable[tableIndex]
        }
        return crc ^ 0xffff_ffff
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xedb8_8320
            } else {
                crc >>= 1
            }
        }
        return crc
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
