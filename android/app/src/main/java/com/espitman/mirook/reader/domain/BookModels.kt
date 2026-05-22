package com.espitman.mirook.reader.domain

import android.net.Uri
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

enum class SourceDocumentKind(val displayName: String) {
    PDF("PDF"),
    EPUB("EPUB");

    companion object {
        fun fromRaw(raw: String?): SourceDocumentKind =
            when (raw?.lowercase()) {
                "epub" -> EPUB
                else -> PDF
            }
    }
}

@Serializable
data class BookManifest(
    val id: String,
    val sourcePath: String = "",
    val displayName: String,
    val pageCount: Int,
    val targetLanguage: String = "fa",
    val model: String = "",
    val createdAt: String = "",
    val updatedAt: String = "",
    val sourceFingerprint: String? = null,
    val sourceKind: String = "pdf"
) {
    val kind: SourceDocumentKind
        get() = SourceDocumentKind.fromRaw(sourceKind)
}

@Serializable
data class TranslatedTextPage(
    val pageIndex: Int,
    val sourceText: String = "",
    val translatedText: String = "",
    val isBlank: Boolean = false,
    val paragraphBlocks: List<TranslatedTextParagraphBlock> = emptyList(),
    val paragraphLayoutVersion: Int = 0
) {
    val pageNumber: Int
        get() = pageIndex + 1
}

@Serializable
data class TranslatedTextParagraphBlock(
    val id: String,
    val sourceText: String = "",
    val translatedText: String = "",
    val pdfBounds: BoundingBox? = null,
    val role: String = "paragraph",
    val confidence: Double = 0.0
)

@Serializable
data class BoundingBox(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double
)

data class MirookBook(
    val uri: Uri,
    val manifest: BookManifest,
    val pages: Map<Int, TranslatedTextPage>,
    val sourcePdf: ByteArray?,
    val epubPages: List<EpubPage>,
    val isPasswordProtected: Boolean
) {
    val pageCount: Int
        get() = manifest.pageCount

    val kind: SourceDocumentKind
        get() = manifest.kind

    fun translatedPage(index: Int): TranslatedTextPage? = pages[index]

    fun sourceText(index: Int): String =
        epubPages.getOrNull(index)?.plainText.orEmpty().ifBlank {
            translatedPage(index)?.sourceText.orEmpty()
        }
}

data class EpubPage(
    val index: Int,
    val title: String?,
    val blocks: List<EpubBlock>
) {
    val plainText: String
        get() = blocks.mapNotNull { block ->
            when (block) {
                is EpubBlock.Text -> block.text
                is EpubBlock.Link -> block.title
                is EpubBlock.Image -> null
            }
        }.joinToString("\n\n")
}

sealed interface EpubBlock {
    data class Text(val text: String) : EpubBlock
    data class Link(val title: String, val href: String) : EpubBlock
    data class Image(val bytes: ByteArray, val mimeType: String, val altText: String?) : EpubBlock
}

@Serializable
data class RecentBook(
    val uri: String,
    val displayName: String,
    val pageCount: Int,
    val sourceKind: String,
    val lastOpenedAt: Long,
    val lastPageIndex: Int = 0
) {
    val kind: SourceDocumentKind
        get() = SourceDocumentKind.fromRaw(sourceKind)
}
