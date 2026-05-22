package com.espitman.mirook.reader.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import com.espitman.mirook.reader.domain.BookManifest
import com.espitman.mirook.reader.domain.MirookBook
import com.espitman.mirook.reader.domain.SourceDocumentKind
import com.espitman.mirook.reader.domain.TranslatedTextPage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.File
import java.io.ByteArrayOutputStream
import javax.crypto.SecretKey

class MirookBookReader(
    private val context: Context,
    private val json: Json = Json { ignoreUnknownKeys = true }
) {
    private val crypto = BookCrypto(json)
    private val epubReader = EpubSourceReader()

    suspend fun open(uri: Uri, password: String? = null): MirookBook = withContext(Dispatchers.IO) {
        val localFile = copyToCache(uri)
        val database = SQLiteDatabase.openDatabase(localFile.path, null, SQLiteDatabase.OPEN_READONLY)
        try {
            val encryptionData = database.infoBlob("encryption")
            val secretKey = if (encryptionData != null) {
                if (password.isNullOrEmpty()) throw MirookBookError.PasswordRequired
                crypto.checkPassword(crypto.parseMetadata(encryptionData), password)
            } else {
                null
            }

            val manifestData = database.metadataBlob("manifest")?.decryptIfNeeded(secretKey)
                ?: throw MirookBookError.MissingManifest
            val manifest = json.decodeFromString(BookManifest.serializer(), manifestData.decodeToString())
            val sourceKey = when (manifest.kind) {
                SourceDocumentKind.PDF -> "sourcePDF"
                SourceDocumentKind.EPUB -> "sourceEPUB"
            }
            val sourceData = database.metadataBlobChunked(sourceKey)?.decryptIfNeeded(secretKey)
            val pages = database.pageBlobs().associate { (index, data) ->
                val page = json.decodeFromString(
                    TranslatedTextPage.serializer(),
                    data.decryptIfNeeded(secretKey).decodeToString()
                )
                index to page
            }

            MirookBook(
                uri = uri,
                manifest = manifest,
                pages = pages,
                sourcePdf = if (manifest.kind == SourceDocumentKind.PDF) sourceData else null,
                epubPages = if (manifest.kind == SourceDocumentKind.EPUB && sourceData != null) epubReader.read(sourceData) else emptyList(),
                isPasswordProtected = encryptionData != null
            )
        } finally {
            database.close()
            localFile.delete()
        }
    }

    fun isPasswordProtected(uri: Uri): Boolean {
        val localFile = copyToCache(uri)
        val database = SQLiteDatabase.openDatabase(localFile.path, null, SQLiteDatabase.OPEN_READONLY)
        return try {
            database.infoBlob("encryption") != null
        } finally {
            database.close()
            localFile.delete()
        }
    }

    private fun ByteArray.decryptIfNeeded(key: SecretKey?): ByteArray =
        if (key == null) this else crypto.decrypt(this, key)

    private fun copyToCache(uri: Uri): File {
        val target = File.createTempFile("mirook-book-", ".mrbk", context.cacheDir)
        val contentInput = runCatching { context.contentResolver.openInputStream(uri) }.getOrNull()
        val inputStream = contentInput
            ?: uri.path?.takeIf { uri.scheme == "file" }?.let { File(it).inputStream() }
            ?: throw MirookBookError.OpenFailed("Could not read this Mirook book.")
        inputStream.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        return target
    }

    private fun SQLiteDatabase.metadataBlob(key: String): ByteArray? =
        rawQuery("SELECT json FROM metadata WHERE key = ? LIMIT 1", arrayOf(key)).use { cursor ->
            if (cursor.moveToFirst()) cursor.getBlob(0) else null
        }

    private fun SQLiteDatabase.metadataBlobChunked(key: String): ByteArray? {
        val size = rawQuery("SELECT length(json) FROM metadata WHERE key = ? LIMIT 1", arrayOf(key)).use { cursor ->
            if (cursor.moveToFirst()) cursor.getLong(0) else return null
        }
        if (size <= 0L) return ByteArray(0)

        val output = ByteArrayOutputStream(size.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
        var offset = 1L
        val chunkSize = 512 * 1024
        while (offset <= size) {
            rawQuery(
                "SELECT substr(json, ?, ?) FROM metadata WHERE key = ? LIMIT 1",
                arrayOf(offset.toString(), chunkSize.toString(), key)
            ).use { cursor ->
                if (!cursor.moveToFirst()) return null
                output.write(cursor.getBlob(0))
            }
            offset += chunkSize
        }
        return output.toByteArray()
    }

    private fun SQLiteDatabase.infoBlob(key: String): ByteArray? =
        rawQuery("SELECT value FROM book_info WHERE key = ? LIMIT 1", arrayOf(key)).use { cursor ->
            if (cursor.moveToFirst()) cursor.getBlob(0) else null
        }

    private fun SQLiteDatabase.pageBlobs(): List<Pair<Int, ByteArray>> =
        rawQuery("SELECT page_index, json FROM pages ORDER BY page_index ASC", emptyArray()).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.getInt(0) to cursor.getBlob(1))
                }
            }
        }
}
