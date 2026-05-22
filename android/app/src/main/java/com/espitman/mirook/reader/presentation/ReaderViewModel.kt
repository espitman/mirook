package com.espitman.mirook.reader.presentation

import android.app.Application
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.espitman.mirook.reader.data.MirookBookError
import com.espitman.mirook.reader.data.MirookBookReader
import com.espitman.mirook.reader.data.PdfPageRenderer
import com.espitman.mirook.reader.data.RecentBookStore
import com.espitman.mirook.reader.domain.EpubPage
import com.espitman.mirook.reader.domain.MirookBook
import com.espitman.mirook.reader.domain.ReaderMode
import com.espitman.mirook.reader.domain.RecentBook
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

data class ReaderUiState(
    val book: MirookBook? = null,
    val recents: List<RecentBook> = emptyList(),
    val pageIndex: Int = 0,
    val mode: ReaderMode = ReaderMode.Translation,
    val fontSize: Int = 22,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val pendingPasswordUri: Uri? = null,
    val sourceBitmap: Bitmap? = null
) {
    val pageCount: Int = book?.pageCount ?: 0
    val pageNumber: Int = pageIndex + 1
    val canGoPrevious: Boolean = pageIndex > 0
    val canGoNext: Boolean = pageIndex + 1 < pageCount
    val currentTranslation: String = book?.translatedPage(pageIndex)?.translatedText.orEmpty()
    val currentSourceText: String = book?.sourceText(pageIndex).orEmpty()
    val currentEpubPage: EpubPage? = book?.epubPages?.getOrNull(pageIndex)
    val isCurrentPageBlank: Boolean = book?.translatedPage(pageIndex)?.isBlank == true
    val isCurrentPageMissing: Boolean = book != null && book.translatedPage(pageIndex) == null
}

class ReaderViewModel(application: Application) : AndroidViewModel(application) {
    private val reader = MirookBookReader(application)
    private val recents = RecentBookStore(application)
    private val pdfRenderer = PdfPageRenderer(application)
    private val preferences = application.getSharedPreferences("mirook-reader-settings", 0)
    private var renderJob: Job? = null

    var state = androidx.compose.runtime.mutableStateOf(
        ReaderUiState(
            recents = recents.load(),
            fontSize = preferences.getInt(KEY_FONT_SIZE, 22)
        )
    )
        private set

    fun openFromIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        open(uri)
    }

    fun open(uri: Uri, password: String? = null) {
        viewModelScope.launch {
            state.value = state.value.copy(isLoading = true, errorMessage = null, pendingPasswordUri = null)
            runCatching {
                takePersistablePermission(uri)
                reader.open(uri, password)
            }.onSuccess { book ->
                val lastPage = recents.load().firstOrNull { it.uri == uri.toString() }?.lastPageIndex ?: 0
                val safePage = lastPage.coerceIn(0, maxOf(book.pageCount - 1, 0))
                recents.remember(book, safePage)
                state.value = state.value.copy(
                    book = book,
                    recents = recents.load(),
                    pageIndex = safePage,
                    mode = ReaderMode.Translation,
                    isLoading = false,
                    errorMessage = null,
                    pendingPasswordUri = null
                )
                renderSourceIfNeeded()
            }.onFailure { error ->
                if (error is MirookBookError.PasswordRequired) {
                    state.value = state.value.copy(isLoading = false, pendingPasswordUri = uri)
                } else {
                    state.value = state.value.copy(isLoading = false, errorMessage = error.message ?: "Could not open this book.")
                }
            }
        }
    }

    fun submitPassword(password: String) {
        val uri = state.value.pendingPasswordUri ?: return
        open(uri, password)
    }

    fun dismissPassword() {
        state.value = state.value.copy(pendingPasswordUri = null)
    }

    fun openRecent(recent: RecentBook) {
        open(Uri.parse(recent.uri))
    }

    fun setMode(mode: ReaderMode) {
        state.value = state.value.copy(mode = mode)
        renderSourceIfNeeded()
    }

    fun nextPage() {
        val current = state.value
        if (!current.canGoNext) return
        setPage(current.pageIndex + 1)
    }

    fun previousPage() {
        val current = state.value
        if (!current.canGoPrevious) return
        setPage(current.pageIndex - 1)
    }

    fun setPage(index: Int) {
        val current = state.value
        val safeIndex = index.coerceIn(0, maxOf(current.pageCount - 1, 0))
        state.value = current.copy(pageIndex = safeIndex, sourceBitmap = null)
        current.book?.let { recents.updateLastPage(it.uri, safeIndex) }
        renderSourceIfNeeded()
    }

    fun adjustFontSize(delta: Int) {
        val next = (state.value.fontSize + delta).coerceIn(14, 36)
        preferences.edit().putInt(KEY_FONT_SIZE, next).apply()
        state.value = state.value.copy(fontSize = next)
    }

    fun clearError() {
        state.value = state.value.copy(errorMessage = null)
    }

    private fun renderSourceIfNeeded() {
        val current = state.value
        val pdf = current.book?.sourcePdf
        if (pdf == null || current.mode == ReaderMode.Translation) {
            state.value = current.copy(sourceBitmap = null)
            return
        }

        renderJob?.cancel()
        renderJob = viewModelScope.launch {
            val bitmap = pdfRenderer.render(pdf, current.pageIndex)
            state.value = state.value.copy(sourceBitmap = bitmap)
        }
    }

    private fun takePersistablePermission(uri: Uri) {
        runCatching {
            getApplication<Application>().contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
    }

    companion object {
        private const val KEY_FONT_SIZE = "translation-font-size"
    }
}
