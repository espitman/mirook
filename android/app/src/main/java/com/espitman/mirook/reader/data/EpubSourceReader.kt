package com.espitman.mirook.reader.data

import com.espitman.mirook.reader.domain.EpubBlock
import com.espitman.mirook.reader.domain.EpubPage
import org.jsoup.parser.Parser
import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

class EpubSourceReader {
    fun read(epubData: ByteArray): List<EpubPage> {
        val entries = unzip(epubData)
        val htmlPaths = entries.keys
            .filter { path -> path.endsWith(".xhtml", true) || path.endsWith(".html", true) || path.endsWith(".htm", true) }
            .filterNot { path -> path.contains("nav", true) || path.contains("toc", true) }
            .sortedWith(compareBy({ spineRank(it, entries) }, { it }))

        return htmlPaths.mapIndexed { index, path ->
            val html = entries[path]?.decodeToString() ?: ""
            EpubPage(index = index, title = null, blocks = blocksFromHtml(path, html, entries))
        }
    }

    private fun blocksFromHtml(path: String, html: String, entries: Map<String, ByteArray>): List<EpubBlock> {
        val images = mutableListOf<EpubBlock.Image?>()
        val links = mutableListOf<EpubBlock.Link?>()
        var markedHtml = html

        linkRegex.findAll(markedHtml).toList().asReversed().forEach { match ->
            val tag = match.value
            val href = hrefRegex.find(tag)?.groupValues?.getOrNull(1) ?: return@forEach
            val title = readableText(tag)
            val linkIndex = links.size
            links.add(EpubBlock.Link(title = title, href = href))
            markedHtml = markedHtml.replaceRange(match.range, "\n\n[[MIROOK_LINK_$linkIndex]]\n\n")
        }

        imageRegex.findAll(markedHtml).toList().asReversed().forEach { match ->
            val tag = match.value
            val source = srcRegex.find(tag)?.groupValues?.getOrNull(1) ?: return@forEach
            val alt = altRegex.find(tag)?.groupValues?.getOrNull(1).orEmpty()
            val imageIndex = images.size
            images.add(imageBlock(path, source, alt, entries))
            markedHtml = markedHtml.replaceRange(match.range, "\n\n[[MIROOK_IMAGE_$imageIndex]]\n\n")
        }

        val textWithMarkers = readableText(markedHtml)
        val blocks = mutableListOf<EpubBlock>()
        var cursor = 0
        markerRegex.findAll(textWithMarkers).forEach { match ->
            if (match.range.first > cursor) {
                appendTextBlocks(textWithMarkers.substring(cursor, match.range.first), blocks)
            }

            val markerType = match.groupValues.getOrNull(1)
            val markerIndex = match.groupValues.getOrNull(2)?.toIntOrNull()
            if (markerType == "IMAGE" && markerIndex != null) {
                images.getOrNull(markerIndex)?.let(blocks::add)
            } else if (markerType == "LINK" && markerIndex != null) {
                links.getOrNull(markerIndex)?.let { link ->
                    if (link.title.isNotBlank()) blocks.add(link)
                }
            }

            cursor = match.range.last + 1
        }

        if (cursor < textWithMarkers.length) {
            appendTextBlocks(textWithMarkers.substring(cursor), blocks)
        }

        return blocks
    }

    private fun appendTextBlocks(text: String, blocks: MutableList<EpubBlock>) {
        text.split("\n\n")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .forEach { blocks.add(EpubBlock.Text(it)) }
    }

    private fun imageBlock(
        htmlPath: String,
        rawSource: String,
        altText: String,
        entries: Map<String, ByteArray>
    ): EpubBlock.Image? {
        val source = rawSource.substringBefore("#").substringBefore("?").trim()
        if (source.isEmpty()) return null

        val resolved = normalizePath(parentPath(htmlPath), source)
        val data = entries[resolved] ?: entries.entries.firstOrNull { it.key.endsWith(source.substringAfterLast("/")) }?.value ?: return null
        return EpubBlock.Image(
            bytes = data,
            mimeType = mimeType(resolved),
            altText = decodeEntities(altText).takeIf { it.isNotBlank() }
        )
    }

    private fun readableText(html: String): String {
        var text = html
            .replace(Regex("""(?is)<(head|script|style|svg|math)\b.*?</\1>"""), " ")
            .replace(Regex("""(?i)<\s*br\s*/?\s*>"""), "\n")
            .replace(Regex("""(?i)</\s*(p|div|section|article|header|footer|blockquote|li|h[1-6])\s*>"""), "\n\n")
            .replace(Regex("""(?s)<[^>]+>"""), " ")
        text = decodeEntities(text)
        return text
            .replace(Regex("""[ \t\f]+"""), " ")
            .replace(Regex("""[ \t]*\n[ \t]*"""), "\n")
            .replace(Regex("""\n{3,}"""), "\n\n")
            .trim()
    }

    private fun decodeEntities(text: String): String =
        Parser.unescapeEntities(text.replace("&nbsp;", " ").replace("&#160;", " "), false).trim()

    private fun unzip(data: ByteArray): Map<String, ByteArray> {
        val entries = linkedMapOf<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(data)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (!entry.isDirectory) {
                    entries[entry.name] = zip.readBytes()
                }
                zip.closeEntry()
            }
        }
        return entries
    }

    private fun spineRank(path: String, entries: Map<String, ByteArray>): Int {
        val opf = entries.entries.firstOrNull { it.key.endsWith(".opf", true) } ?: return Int.MAX_VALUE
        val opfText = opf.value.decodeToString()
        val fileName = path.substringAfterLast("/")
        val index = opfText.indexOf(fileName)
        return if (index >= 0) index else Int.MAX_VALUE
    }

    private fun parentPath(path: String): String = path.substringBeforeLast("/", missingDelimiterValue = "")

    private fun normalizePath(parent: String, child: String): String {
        val decoded = runCatching { java.net.URLDecoder.decode(child, Charsets.UTF_8.name()) }.getOrDefault(child)
        val raw = if (decoded.startsWith("/")) decoded.drop(1) else listOf(parent, decoded).filter { it.isNotBlank() }.joinToString("/")
        val parts = mutableListOf<String>()
        raw.split("/").forEach { part ->
            when (part) {
                "", "." -> Unit
                ".." -> if (parts.isNotEmpty()) parts.removeAt(parts.lastIndex)
                else -> parts.add(part)
            }
        }
        return parts.joinToString("/")
    }

    private fun mimeType(path: String): String =
        when (path.substringAfterLast(".", "").lowercase()) {
            "jpg", "jpeg" -> "image/jpeg"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "svg" -> "image/svg+xml"
            else -> "image/png"
        }

    private companion object {
        val linkRegex = Regex("""(?is)<a\b[^>]*href\s*=\s*["'][^"']+["'][^>]*>.*?</a>""")
        val imageRegex = Regex("""(?is)<img\b[^>]*>""")
        val hrefRegex = Regex("""(?i)\bhref\s*=\s*["']([^"']+)["']""")
        val srcRegex = Regex("""(?i)\bsrc\s*=\s*["']([^"']+)["']""")
        val altRegex = Regex("""(?i)\balt\s*=\s*["']([^"']*)["']""")
        val markerRegex = Regex("""\[\[MIROOK_(IMAGE|LINK)_(\d+)]]""")
    }
}
