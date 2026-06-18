package com.example.okuyombenya

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Environment
import android.util.Log
import androidx.annotation.WorkerThread
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipFile
import kotlin.text.Regex
import kotlin.text.RegexOption

class ThumbnailGenerator {

    companion object {
        private const val TAG = "ThumbnailGenerator"
        private const val THUMBNAIL_WIDTH = 300
        private const val THUMBNAIL_HEIGHT = 400

        // ==================== ANA METOT ====================

        @WorkerThread
        fun generateThumbnail(filePath: String): String? {
            return try {
                val file = File(filePath)
                if (!file.exists()) return null

                val extension = file.extension.lowercase()
                val bitmap = when (extension) {
                    "pdf" -> generatePdfThumbnail(file)
                    "epub" -> generateEpubThumbnail(file)
                    "docx", "doc" -> generateDocxThumbnail(file)
                    "pptx", "ppt" -> generateOfficeThumbnail(file, "ppt/media/")
                    "xlsx", "xls" -> generateOfficeThumbnail(file, "xl/media/")
                    else -> null
                }

                bitmap?.let { saveBitmapToCache(it, filePath) }
            } catch (e: Exception) {
                Log.e(TAG, "Thumbnail oluşturma hatası: ${e.message}")
                null
            }
        }

        // ==================== DOSYA BİLGİLERİ ====================

        @WorkerThread
        fun getFileInfo(filePath: String): Map<String, Any> {
            val result = mutableMapOf<String, Any>()
            try {
                val file = File(filePath)
                if (!file.exists()) {
                    result["error"] = "File not found"
                    return result
                }
                result["size"] = file.length()
                result["name"] = file.name
                result["extension"] = file.extension.lowercase()
                result["lastModified"] = file.lastModified()

                val extension = file.extension.lowercase()
                when (extension) {
                    "pdf" -> {
                        try {
                            val renderer = android.graphics.pdf.PdfRenderer(
                                android.os.ParcelFileDescriptor.open(file, android.os.ParcelFileDescriptor.MODE_READ_ONLY)
                            )
                            result["pageCount"] = renderer.pageCount
                            renderer.close()
                        } catch (e: Exception) {
                            result["pageCount"] = 0
                        }
                    }
                    "epub", "docx", "pptx", "xlsx" -> {
                        try {
                            ZipFile(file).use { zip ->
                                result["entryCount"] = zip.entries().toList().size
                            }
                        } catch (e: Exception) {
                            result["entryCount"] = 0
                        }
                    }
                    else -> {
                        result["pageCount"] = 0
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "getFileInfo hatası: ${e.message}")
                result["error"] = e.message ?: "Unknown error"
            }
            return result
        }

        // ==================== PDF THUMBNAIL ====================

        @WorkerThread
        private fun generatePdfThumbnail(file: File): Bitmap? {
            return try {
                val renderer = android.graphics.pdf.PdfRenderer(
                    android.os.ParcelFileDescriptor.open(file, android.os.ParcelFileDescriptor.MODE_READ_ONLY)
                )
                if (renderer.pageCount == 0) {
                    renderer.close()
                    return null
                }
                val page = renderer.openPage(0)
                val bitmap = Bitmap.createBitmap(THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT, Bitmap.Config.ARGB_8888)
                page.render(bitmap, null, null, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                page.close()
                renderer.close()
                bitmap
            } catch (e: Exception) {
                Log.e(TAG, "PDF thumbnail hatası: ${e.message}")
                null
            }
        }

        // ==================== EPUB THUMBNAIL ====================

        @WorkerThread
        private fun generateEpubThumbnail(file: File): Bitmap? {
            return try {
                ZipFile(file).use { zip ->
                    val coverNames = listOf(
                        "cover.jpg", "cover.jpeg", "cover.png", "cover.webp",
                        "META-INF/cover.jpg", "META-INF/cover.png",
                        "OEBPS/cover.jpg", "OEBPS/cover.png",
                        "EPUB/cover.jpg", "EPUB/cover.png"
                    )
                    for (name in coverNames) {
                        val entry = zip.getEntry(name)
                        if (entry != null) {
                            val bytes = zip.getInputStream(entry).readBytes()
                            return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        }
                    }
                    null
                }
            } catch (e: Exception) {
                Log.e(TAG, "EPUB thumbnail hatası: ${e.message}")
                null
            }
        }

        // ==================== OFFICE THUMBNAIL (PPTX, XLSX) ====================

        @WorkerThread
        private fun generateOfficeThumbnail(file: File, mediaPath: String): Bitmap? {
            return try {
                ZipFile(file).use { zip ->
                    val priorityNames = listOf("cover", "image1", "img1", "picture1")
                    val entries = zip.entries().toList()

                    for (priority in priorityNames) {
                        for (entry in entries) {
                            if (!entry.isDirectory && entry.name.startsWith(mediaPath)) {
                                val name = entry.name.lowercase()
                                if (name.contains(priority) &&
                                    (name.endsWith(".jpg") || name.endsWith(".jpeg") ||
                                            name.endsWith(".png") || name.endsWith(".gif") || name.endsWith(".webp"))) {
                                    val bytes = zip.getInputStream(entry).readBytes()
                                    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                }
                            }
                        }
                    }

                    for (entry in entries) {
                        if (!entry.isDirectory && entry.name.startsWith(mediaPath)) {
                            val name = entry.name.lowercase()
                            if (name.endsWith(".jpg") || name.endsWith(".jpeg") ||
                                name.endsWith(".png") || name.endsWith(".gif") || name.endsWith(".webp")) {
                                val bytes = zip.getInputStream(entry).readBytes()
                                return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            }
                        }
                    }
                    null
                }
            } catch (e: Exception) {
                Log.e(TAG, "Office thumbnail hatası: ${e.message}")
                null
            }
        }

        // ==================== 📄 DOCX THUMBNAIL (YENİ ALGORİTMA) ====================

        @WorkerThread
        private fun generateDocxThumbnail(file: File): Bitmap? {
            return try {
                ZipFile(file).use { zip ->
                    // 1. document.xml'i bul
                    val documentEntry = zip.getEntry("word/document.xml")
                    if (documentEntry == null) {
                        Log.e(TAG, "DOCX'te document.xml bulunamadı, fallback")
                        return generateOfficeThumbnail(file, "word/media/")
                    }

                    // 2. XML'i oku
                    val xmlContent = zip.getInputStream(documentEntry).reader().readText()

                    // 3. İlk paragrafı bul
                    val paragraphPattern = Regex("<w:p[^>]*>.*?</w:p>", RegexOption.DOT_MATCHES_ALL)
                    val paragraphs = paragraphPattern.findAll(xmlContent).toList()
                    if (paragraphs.isEmpty()) {
                        Log.e(TAG, "DOCX'te paragraf bulunamadı, fallback")
                        return generateOfficeThumbnail(file, "word/media/")
                    }

                    // 4. İlk paragrafın metnini çıkar
                    val firstParagraph = paragraphs.first().value
                    val textPattern = Regex("<w:t[^>]*>(.*?)</w:t>")
                    val textMatches = textPattern.findAll(firstParagraph)
                    val text = textMatches.map { it.groupValues[1] }.joinToString(" ")

                    // 5. İlk resmi bul (word/media/)
                    var imageBytes: ByteArray? = null
                    val mediaEntries = zip.entries().filter {
                        !it.isDirectory && it.name.startsWith("word/media/") &&
                                (it.name.endsWith(".jpg") || it.name.endsWith(".jpeg") ||
                                        it.name.endsWith(".png") || it.name.endsWith(".gif") || it.name.endsWith(".webp"))
                    }
                    if (mediaEntries.isNotEmpty()) {
                        imageBytes = zip.getInputStream(mediaEntries.first()).readBytes()
                    }

                    // 6. Bitmap oluştur (Canvas ile)
                    val bitmap = Bitmap.createBitmap(THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bitmap)
                    val paint = Paint()

                    // Arka plan (koyu gri)
                    paint.color = Color.parseColor("#1A1A1A")
                    canvas.drawRect(0f, 0f, THUMBNAIL_WIDTH.toFloat(), THUMBNAIL_HEIGHT.toFloat(), paint)

                    // Resim varsa ortala (üst kısımda)
                    var hasImage = false
                    if (imageBytes != null) {
                        val options = BitmapFactory.Options()
                        options.inSampleSize = 4  // Boyut küçült
                        val imageBitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, options)
                        if (imageBitmap != null) {
                            val scaledBitmap = Bitmap.createScaledBitmap(imageBitmap, 200, 200, true)
                            canvas.drawBitmap(scaledBitmap, (THUMBNAIL_WIDTH - 200) / 2f, 10f, paint)
                            hasImage = true
                        }
                    }

                    // Metni çiz (resmin altına)
                    paint.color = Color.WHITE
                    paint.textSize = 16f
                    paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                    paint.isAntiAlias = true

                    val yStart = if (hasImage) 230f else 40f
                    val lines = breakTextIntoLines(text, 260, paint)
                    var y = yStart
                    for (line in lines) {
                        canvas.drawText(line, 10f, y, paint)
                        y += paint.textSize + 6f
                        if (y > THUMBNAIL_HEIGHT - 20) break
                    }

                    // Dosya uzantısı etiketi
                    paint.color = Color.parseColor("#2196F3")
                    paint.textSize = 12f
                    paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
                    canvas.drawText("DOCX", 10f, THUMBNAIL_HEIGHT - 15f, paint)

                    bitmap
                }
            } catch (e: Exception) {
                Log.e(TAG, "DOCX thumbnail (yeni) hatası: ${e.message}, fallback")
                generateOfficeThumbnail(file, "word/media/")
            }
        }

        // Metni satırlara bölen yardımcı
        private fun breakTextIntoLines(text: String, maxWidth: Int, paint: Paint): List<String> {
            val lines = mutableListOf<String>()
            var currentLine = ""
            for (word in text.split(" ")) {
                val testLine = if (currentLine.isEmpty()) word else "$currentLine $word"
                if (paint.measureText(testLine) <= maxWidth) {
                    currentLine = testLine
                } else {
                    if (currentLine.isNotEmpty()) lines.add(currentLine)
                    currentLine = word
                }
            }
            if (currentLine.isNotEmpty()) lines.add(currentLine)
            return lines
        }

        // ==================== CACHE'E KAYDET ====================

        @WorkerThread
        private fun saveBitmapToCache(bitmap: Bitmap, filePath: String): String? {
            return try {
                val cacheDir = File(Environment.getExternalStorageDirectory(), "covers")
                if (!cacheDir.exists()) cacheDir.mkdirs()

                val hash = filePath.hashCode().toString()
                val coverFile = File(cacheDir, "$hash.png")
                FileOutputStream(coverFile).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.PNG, 85, out)
                }
                coverFile.absolutePath
            } catch (e: Exception) {
                Log.e(TAG, "Cache kaydetme hatası: ${e.message}")
                null
            }
        }
    }
}