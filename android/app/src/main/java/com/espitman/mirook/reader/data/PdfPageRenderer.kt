package com.espitman.mirook.reader.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class PdfPageRenderer(private val context: Context) {
    suspend fun render(pdfData: ByteArray, pageIndex: Int, targetWidth: Int = 1200): Bitmap? =
        withContext(Dispatchers.IO) {
            val file = File.createTempFile("mirook-source-", ".pdf", context.cacheDir)
            file.writeBytes(pdfData)
            try {
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                    PdfRenderer(descriptor).use { renderer ->
                        if (pageIndex !in 0 until renderer.pageCount) return@withContext null
                        renderer.openPage(pageIndex).use { page ->
                            val width = targetWidth.coerceAtLeast(320)
                            val height = (width.toFloat() / page.width * page.height).toInt().coerceAtLeast(320)
                            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                            bitmap.eraseColor(Color.WHITE)
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            bitmap
                        }
                    }
                }
            } finally {
                file.delete()
            }
        }
}
