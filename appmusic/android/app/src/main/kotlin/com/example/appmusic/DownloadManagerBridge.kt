package com.example.appmusic

import android.app.DownloadManager
import android.content.Context
import android.content.ContentUris
import android.content.ContentValues
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.database.Cursor
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.Locale
import java.util.concurrent.TimeUnit

class DownloadManagerBridge(private val context: Context) {
    private val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val handler = Handler(Looper.getMainLooper())
    private data class DownloadState(
        val title: String,
        var finalized: Boolean = false,
        var lastBytes: Long = 0,
        var lastMeasuredAt: Long = 0,
    )

    private val activeDownloads = linkedMapOf<Long, DownloadState>()
    private var eventSink: EventChannel.EventSink? = null

    val methodHandler = MethodChannel.MethodCallHandler { call, result ->
        when (call.method) {
            "startDownload" -> startDownload(
                call.argument<String>("url"),
                call.argument<String>("title"),
                call.argument<String>("extension"),
                call.argument<Boolean>("useYouTubeHeaders") == true,
                result,
            )
            "cancelDownload" -> cancelDownload(call.argument<Number>("downloadId")?.toLong(), result)
            "restoreDownloads" -> {
                val ids = call.argument<List<Number>>("downloadIds")
                    ?: (call.arguments as? List<Number>)
                restoreDownloads(ids, result)
            }
            "importDownloadedAudio" -> importDownloadedAudio(
                call.argument<String>("filePath"),
                call.argument<String>("title"),
                call.argument<String>("artist"),
                call.argument<String>("album"),
                call.argument<String>("extension"),
                call.argument<String>("artworkPath"),
                result,
            )
            else -> result.notImplemented()
        }
    }

    val streamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
        }

        override fun onCancel(arguments: Any?) {
            eventSink = null
        }
    }

    fun detach() {
        handler.removeCallbacksAndMessages(null)
        eventSink = null
    }

    private fun hasVideoTrack(sourceFile: File): Boolean {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(sourceFile.absolutePath)
            for (i in 0 until extractor.trackCount) {
                val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) {
                    return true
                }
            }
            false
        } catch (_: Exception) {
            false
        } finally {
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    private fun extractAudioTrack(sourceFile: File, outputFile: File): Boolean {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            extractor.setDataSource(sourceFile.absolutePath)
            val numTracks = extractor.trackCount
            var audioTrackIndex = -1
            var audioFormat: MediaFormat? = null

            for (i in 0 until numTracks) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    audioFormat = format
                    break
                }
            }

            if (audioTrackIndex == -1 || audioFormat == null) {
                return false
            }

            extractor.selectTrack(audioTrackIndex)

            muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val muxerAudioTrack = muxer.addTrack(audioFormat)
            muxer.start()

            val maxBufferSize = if (audioFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE).coerceAtLeast(64 * 1024)
            } else {
                64 * 1024
            }
            val buffer = ByteBuffer.allocate(maxBufferSize)
            val bufferInfo = MediaCodec.BufferInfo()

            while (true) {
                bufferInfo.offset = 0
                bufferInfo.size = extractor.readSampleData(buffer, 0)
                if (bufferInfo.size < 0) {
                    break
                }
                bufferInfo.presentationTimeUs = extractor.sampleTime
                bufferInfo.flags = extractor.sampleFlags
                muxer.writeSampleData(muxerAudioTrack, buffer, bufferInfo)
                extractor.advance()
            }

            muxer.stop()
            muxer.release()
            muxer = null
            extractor.release()

            return outputFile.exists() && outputFile.length() > 0
        } catch (e: Exception) {
            try { muxer?.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
            try { if (outputFile.exists()) outputFile.delete() } catch (_: Exception) {}
            return false
        }
    }

    private fun importDownloadedAudio(
        filePath: String?,
        title: String?,
        artist: String?,
        album: String?,
        extension: String?,
        artworkPath: String?,
        result: MethodChannel.Result,
    ) {
        if (filePath.isNullOrBlank()) {
            result.error("invalid_path", "Caminho do arquivo baixado é inválido.", null)
            return
        }
        val sourceFile = File(filePath)
        if (!sourceFile.exists()) {
            result.error("file_not_found", "Arquivo temporário não encontrado.", null)
            return
        }

        try {
            val trackTitle = title?.trim()?.ifEmpty { "Música baixada" } ?: "Música baixada"
            val trackArtist = artist?.trim()?.ifEmpty { "Artista desconhecido" } ?: "Artista desconhecido"
            val trackAlbum = album?.trim()?.ifEmpty { "Downloads" } ?: "Downloads"
            var effectiveExtension = (extension ?: sourceFile.extension).lowercase(Locale.ROOT)

            // Se for áudio (m4a, aac, mp3) e o container contiver vídeo (fluxo progressivo do YouTube),
            // extrai apenas a faixa AAC de áudio nativa para reduzir o arquivo de ~16 MB para ~3 MB.
            var fileToImport = sourceFile
            var extractedTempFile: File? = null
            val isAudioTarget = effectiveExtension in listOf("m4a", "aac", "mp3")
            if (isAudioTarget && hasVideoTrack(sourceFile)) {
                val tempTarget = File(sourceFile.parentFile, "extracted_${System.nanoTime()}.m4a")
                if (extractAudioTrack(sourceFile, tempTarget)) {
                    fileToImport = tempTarget
                    extractedTempFile = tempTarget
                    effectiveExtension = "m4a"
                }
            }

            val fileName = safeFileName(trackTitle, effectiveExtension)
            val mimeType = normalizedMime(null, fileName)

            val contentValues = ContentValues().apply {
                put(MediaStore.Audio.Media.TITLE, trackTitle)
                put(MediaStore.Audio.Media.ARTIST, trackArtist)
                put(MediaStore.Audio.Media.ALBUM, trackAlbum)
                put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                put(MediaStore.Audio.Media.IS_MUSIC, 1)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    put(MediaStore.Audio.Media.IS_PENDING, 1)
                }
            }
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }
            val outputUri = context.contentResolver.insert(collection, contentValues)
                ?: throw IllegalStateException("Não foi possível criar a entrada na biblioteca.")

            context.contentResolver.openOutputStream(outputUri)?.use { output ->
                fileToImport.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Não foi possível gravar na biblioteca.")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                context.contentResolver.update(outputUri, ContentValues().apply {
                    put(MediaStore.Audio.Media.IS_PENDING, 0)
                }, null, null)
            }
            val mediaId = ContentUris.parseId(outputUri)

            // Limpeza dos arquivos temporários
            extractedTempFile?.delete()
            sourceFile.delete()

            // Salva a capa do YouTube associada ao mediaId
            if (!artworkPath.isNullOrBlank()) {
                val artFile = File(artworkPath)
                if (artFile.exists() && artFile.length() > 0) {
                    try {
                        val cachedArt = File(context.filesDir, "artwork_$mediaId.jpg")
                        artFile.copyTo(cachedArt, overwrite = true)
                    } catch (_: Exception) {}
                    try { artFile.delete() } catch (_: Exception) {}
                }
            }

            // Dispara escaneamento para atualizar o catálogo do MediaStore
            val pathColumn = arrayOf(MediaStore.Audio.Media.DATA)
            val actualPath = context.contentResolver.query(outputUri, pathColumn, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
            if (!actualPath.isNullOrBlank()) {
                try {
                    MediaScannerConnection.scanFile(
                        context,
                        arrayOf(actualPath),
                        arrayOf(mimeType),
                        null,
                    )
                } catch (_: Exception) {}
            }

            result.success(
                mapOf(
                    "mediaId" to mediaId,
                    "outputUri" to outputUri.toString(),
                )
            )
        } catch (error: Exception) {
            result.error("import_failed", error.message ?: "Falha ao importar o áudio.", null)
        }
    }

    private fun startDownload(
        url: String?,
        title: String?,
        extension: String?,
        useYouTubeHeaders: Boolean,
        result: MethodChannel.Result,
    ) {
        if (url.isNullOrBlank()) {
            result.error("invalid_url", "A URL do download é inválida.", null)
            return
        }
        val fileName = safeFileName(title ?: "Música baixada", extension)
        val destinationDirectory = context.getExternalFilesDir(Environment.DIRECTORY_MUSIC)
            ?.let { File(it, "AppMusic/downloads") }
            ?: throw IllegalStateException("O armazenamento externo do aplicativo não está disponível.")
        if (!destinationDirectory.exists() && !destinationDirectory.mkdirs()) {
            throw IllegalStateException("Não foi possível criar a pasta de downloads.")
        }
        val destination = Uri.fromFile(
            File(destinationDirectory, "${System.nanoTime()}-$fileName")
        )
        val request = try {
            DownloadManager.Request(Uri.parse(url)).apply {
                setTitle(title ?: "Música baixada")
                setDescription("Baixando música")
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                setAllowedOverMetered(true)
                setAllowedOverRoaming(false)
                if (useYouTubeHeaders) {
                    addRequestHeader("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36")
                    addRequestHeader("Referer", "https://www.youtube.com/")
                    addRequestHeader("Origin", "https://www.youtube.com")
                    addRequestHeader("Accept", "*/*")
                }
                setDestinationUri(destination)
            }
        } catch (error: Exception) {
            result.error("invalid_url", error.message, null)
            return
        }
        try {
            val id = manager.enqueue(request)
            activeDownloads[id] = DownloadState(title ?: "Música baixada")
            schedulePoll()
            result.success(id)
        } catch (error: Exception) {
            result.error("enqueue_failed", error.message, null)
        }
    }

    private fun cancelDownload(downloadId: Long?, result: MethodChannel.Result) {
        if (downloadId == null) {
            result.error("invalid_id", "ID de download inválido.", null)
            return
        }
        activeDownloads.remove(downloadId)
        manager.remove(downloadId)
        result.success(null)
    }

    private fun restoreDownloads(ids: List<Number>?, result: MethodChannel.Result) {
        ids.orEmpty().forEach {
            activeDownloads[it.toLong()] = DownloadState("Música baixada")
        }
        schedulePoll()
        result.success(null)
    }

    private fun schedulePoll() {
        handler.removeCallbacks(pollTask)
        handler.postDelayed(pollTask, 250)
    }

    private val pollTask = object : Runnable {
        override fun run() {
            val iterator = activeDownloads.entries.iterator()
            while (iterator.hasNext()) {
                val entry = iterator.next()
                val downloadId = entry.key
                val query = DownloadManager.Query().setFilterById(downloadId)
                manager.query(query)?.use { cursor ->
                    if (!cursor.moveToFirst()) {
                        iterator.remove()
                        emit(downloadId, "failed", error = "Download perdido pelo Android.")
                        return@use
                    }
                    val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                    val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                    val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                    when (status) {
                        DownloadManager.STATUS_RUNNING,
                        DownloadManager.STATUS_PAUSED,
                        DownloadManager.STATUS_PENDING -> {
                            val now = System.currentTimeMillis()
                            val elapsedMillis = if (entry.value.lastMeasuredAt > 0) {
                                (now - entry.value.lastMeasuredAt).coerceAtLeast(1)
                            } else {
                                750
                            }
                            val speedBytesPerSecond = ((downloaded - entry.value.lastBytes) * 1000L /
                                elapsedMillis).coerceAtLeast(0)
                            val remainingSeconds = if (speedBytesPerSecond > 0 && total > downloaded) {
                                (total - downloaded) / speedBytesPerSecond
                            } else {
                                null
                            }
                            entry.value.lastBytes = downloaded
                            entry.value.lastMeasuredAt = now
                            emit(
                                downloadId,
                                if (status == DownloadManager.STATUS_PAUSED) "paused" else "running",
                                downloaded,
                                total,
                                speedBytesPerSecond = speedBytesPerSecond,
                                remainingSeconds = remainingSeconds,
                            )
                        }
                        DownloadManager.STATUS_SUCCESSFUL -> {
                            if (!entry.value.finalized) {
                                entry.value.finalized = true
                                finalizeDownload(downloadId, entry.value.title, cursor, iterator)
                            }
                        }
                        DownloadManager.STATUS_FAILED -> {
                            val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                            iterator.remove()
                            val reasonText = when (reason) {
                                403 -> "HTTP 403: o link temporário do YouTube foi rejeitado. Consulte o link novamente."
                                429 -> "HTTP 429: muitas solicitações. Aguarde antes de tentar novamente."
                                408 -> "HTTP 408: o servidor não respondeu a tempo."
                                else -> when {
                                    reason in 400..599 -> "HTTP $reason ao acessar o link da música."
                                    else -> "Falha no download (código $reason)."
                                }
                            }
                            emit(downloadId, "failed", error = reasonText)
                        }
                    }
                }
            }
            if (activeDownloads.isNotEmpty()) handler.postDelayed(this, 750)
        }
    }

    private fun finalizeDownload(
        downloadId: Long,
        title: String,
        cursor: Cursor,
        iterator: MutableIterator<MutableMap.MutableEntry<Long, DownloadState>>,
    ) {
        try {
            val uri = manager.getUriForDownloadedFile(downloadId)
            val mimeTypeColumn = cursor.getColumnIndex(DownloadManager.COLUMN_MEDIA_TYPE)
            val mimeType = if (mimeTypeColumn >= 0) cursor.getString(mimeTypeColumn) else null
            val localPath = uri.path
            val source = context.contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Não foi possível abrir o arquivo baixado.")
            val contentValues = ContentValues().apply {
                put(MediaStore.Audio.Media.TITLE, title)
                put(MediaStore.Audio.Media.ARTIST, "Artista desconhecido")
                put(MediaStore.Audio.Media.ALBUM, "Downloads")
                put(MediaStore.Audio.Media.DISPLAY_NAME, safeFileName(title))
                put(MediaStore.Audio.Media.MIME_TYPE, normalizedMime(mimeType, localPath))
                put(MediaStore.Audio.Media.IS_MUSIC, 1)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    put(MediaStore.Audio.Media.IS_PENDING, 1)
                }
            }
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }
            val outputUri = context.contentResolver.insert(collection, contentValues)
                ?: throw IllegalStateException("Não foi possível criar a entrada na biblioteca.")
            context.contentResolver.openOutputStream(outputUri)?.use { output ->
                source.use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Não foi possível gravar na biblioteca.")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                context.contentResolver.update(outputUri, ContentValues().apply {
                    put(MediaStore.Audio.Media.IS_PENDING, 0)
                }, null, null)
            }
            val mediaId = ContentUris.parseId(outputUri)
            iterator.remove()
            emit(downloadId, "completed", outputUri = outputUri.toString(), mediaId = mediaId)
            localPath?.let { File(it).delete() }
        } catch (error: Exception) {
            iterator.remove()
            emit(downloadId, "failed", error = error.message ?: "Falha ao importar a música.")
        }
    }

    private fun readableTitle(uri: Uri): String {
        val name = uri.pathSegments.lastOrNull()?.substringAfterLast('-') ?: "Música baixada"
        val title = name.substringBeforeLast('.')
        return title.ifBlank { "Música baixada" }
    }

    private fun normalizedMime(mimeType: String?, path: String?): String {
        val extension = path?.substringAfterLast('.', missingDelimiterValue = "")
            ?.lowercase(Locale.ROOT) ?: ""
        return when (extension) {
            "mp3" -> "audio/mpeg"
            "m4a", "mp4" -> "audio/mp4"
            "webm" -> "audio/webm"
            "ogg", "opus" -> "audio/ogg"
            "wav" -> "audio/wav"
            "flac" -> "audio/flac"
            "aac" -> "audio/aac"
            else -> {
                if (!mimeType.isNullOrBlank() && mimeType.startsWith("audio/")) mimeType
                else "audio/mpeg"
            }
        }
    }

    private fun safeFileName(value: String, extension: String? = null): String {
        val normalized = value
            .replace(Regex("[^\\p{L}\\p{N}._ -]"), "_")
            .replace(Regex("\\s+"), " ")
            .trim()
            .ifEmpty { "musica" }
            .take(120)
        val existingExtension = normalized.substringAfterLast('.', "")
        val allowedExtensions = listOf("mp3", "m4a", "mp4", "aac", "ogg", "opus", "wav", "flac", "webm")
        val selectedExtension = extension
            ?.substringAfterLast('.')
            ?.lowercase(Locale.ROOT)
            ?.takeIf { it in allowedExtensions }
            ?: "mp3"
        val baseName = if (existingExtension.lowercase(Locale.ROOT) in allowedExtensions) {
            normalized.substringBeforeLast('.')
        } else {
            normalized
        }
        return "$baseName.$selectedExtension"
    }

    private fun emit(
        downloadId: Long,
        status: String,
        bytesDownloaded: Long = 0,
        totalBytes: Long = -1,
        speedBytesPerSecond: Long = 0,
        remainingSeconds: Long? = null,
        outputUri: String? = null,
        mediaId: Long? = null,
        error: String? = null,
    ) {
        val progress = if (totalBytes > 0) {
            (bytesDownloaded.toDouble() / totalBytes.toDouble()).coerceIn(0.0, 1.0)
        } else {
            0.0
        }
        val payload = linkedMapOf<String, Any?>(
            "downloadId" to downloadId,
            "status" to status,
            "bytesDownloaded" to bytesDownloaded,
            "totalBytes" to if (totalBytes > 0) totalBytes else null,
            "progress" to progress,
            "speedBytesPerSecond" to speedBytesPerSecond,
            "remainingSeconds" to remainingSeconds,
            "outputUri" to outputUri,
            "mediaId" to mediaId,
            "error" to error,
        )
        handler.post { eventSink?.success(payload) }
    }
}
