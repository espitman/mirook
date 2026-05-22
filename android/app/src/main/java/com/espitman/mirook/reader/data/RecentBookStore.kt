package com.espitman.mirook.reader.data

import android.content.Context
import android.net.Uri
import com.espitman.mirook.reader.domain.MirookBook
import com.espitman.mirook.reader.domain.RecentBook
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

class RecentBookStore(
    context: Context,
    private val json: Json = Json { ignoreUnknownKeys = true }
) {
    private val preferences = context.getSharedPreferences("mirook-reader", Context.MODE_PRIVATE)

    fun load(): List<RecentBook> {
        val raw = preferences.getString(KEY_RECENTS, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString(ListSerializer(RecentBook.serializer()), raw)
        }.getOrDefault(emptyList())
    }

    fun remember(book: MirookBook, pageIndex: Int = 0) {
        val existing = load().filterNot { it.uri == book.uri.toString() }
        val recent = RecentBook(
            uri = book.uri.toString(),
            displayName = book.manifest.displayName,
            pageCount = book.pageCount,
            sourceKind = book.kind.name.lowercase(),
            lastOpenedAt = System.currentTimeMillis(),
            lastPageIndex = pageIndex.coerceIn(0, maxOf(book.pageCount - 1, 0))
        )
        save((listOf(recent) + existing).take(20))
    }

    fun updateLastPage(uri: Uri, pageIndex: Int) {
        val updated = load().map {
            if (it.uri == uri.toString()) it.copy(lastPageIndex = pageIndex, lastOpenedAt = System.currentTimeMillis()) else it
        }
        save(updated)
    }

    private fun save(recents: List<RecentBook>) {
        preferences.edit()
            .putString(KEY_RECENTS, json.encodeToString(ListSerializer(RecentBook.serializer()), recents))
            .apply()
    }

    companion object {
        private const val KEY_RECENTS = "recent-books"
    }
}
