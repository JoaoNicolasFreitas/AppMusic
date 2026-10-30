package com.example.appmusic

import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var downloadManagerBridge: DownloadManagerBridge? = null
    private val channelName = "appmusic/media_deletion"
    private val deleteRequestCode = 9471
    private var pendingDeleteUri: Uri? = null
    private var pendingDeleteResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "appmusic/media_library")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "querySongs" -> {
                        try {
                            result.success(querySongs())
                        } catch (error: Exception) {
                            result.error("media_query_failed", error.message, null)
                        }
                    }
                    "getArtwork" -> {
                        val mediaId = call.argument<Number>("id")?.toLong()
                        if (mediaId == null) {
                            result.error("invalid_id", "Identificador de mídia inválido.", null)
                        } else {
                            try {
                                result.success(queryArtwork(mediaId))
                            } catch (error: Exception) {
                                result.error("artwork_query_failed", error.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        downloadManagerBridge = DownloadManagerBridge(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "appmusic/media_downloader"
        ).setMethodCallHandler(downloadManagerBridge!!.methodHandler)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "appmusic/media_downloader/events"
        ).setStreamHandler(downloadManagerBridge!!.streamHandler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "deleteAudio") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val mediaId = call.argument<Number>("id")?.toLong()
                if (mediaId == null) {
                    result.error("invalid_id", "Identificador de mídia inválido.", null)
                    return@setMethodCallHandler
                }

                deleteAudio(mediaId, result)
            }
    }

    override fun detachFromFlutterEngine() {
        downloadManagerBridge?.detach()
        downloadManagerBridge = null
        super.detachFromFlutterEngine()
    }

    private fun querySongs(): List<Map<String, Any?>> {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DISPLAY_NAME
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"
        val rows = mutableListOf<Map<String, Any?>>()

        contentResolver.query(
            audioCollection(),
            projection,
            selection,
            null,
            sortOrder
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dateAddedColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val displayNameColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)

            while (cursor.moveToNext()) {
                val displayName = cursor.getString(displayNameColumn) ?: ""
                if (displayName.startsWith("AUD-", ignoreCase = true)) {
                    continue
                }

                val id = cursor.getLong(idColumn)
                val uri = ContentUris.withAppendedId(audioCollection(), id)
                rows.add(
                    mapOf(
                        "id" to id,
                        "uri" to uri.toString(),
                        "title" to cursor.getString(titleColumn),
                        "artist" to cursor.getString(artistColumn),
                        "album" to cursor.getString(albumColumn),
                        "duration" to cursor.getLong(durationColumn),
                        "dateAdded" to cursor.getLong(dateAddedColumn),
                        "displayName" to displayName
                    )
                )
            }
        }
        return rows
    }

    private fun queryArtwork(mediaId: Long): ByteArray? {
        // 1. Tenta capa salva em cache local (artwork_{mediaId}.jpg)
        try {
            val cachedArtwork = File(applicationContext.filesDir, "artwork_$mediaId.jpg")
            if (cachedArtwork.exists() && cachedArtwork.length() > 0) {
                return cachedArtwork.readBytes()
            }
        } catch (_: Exception) {}

        val mediaUri = ContentUris.withAppendedId(audioCollection(), mediaId)

        // 2. Tenta extrair a capa embutida no arquivo diretamente via MediaMetadataRetriever (ID3 / MP4 tags)
        try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(applicationContext, mediaUri)
            val picture = retriever.embeddedPicture
            retriever.release()
            if (picture != null && picture.isNotEmpty()) {
                return picture
            }
        } catch (_: Exception) {}

        // 3. Se não encontrou, tenta via ContentResolver.loadThumbnail (Android 10+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val bitmap = contentResolver.loadThumbnail(mediaUri, Size(512, 512), null)
                return ByteArrayOutputStream().use { output ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, output)
                    bitmap.recycle()
                    output.toByteArray()
                }
            } catch (_: Exception) {}
        }

        // 4. Fallback clássico para Android 9 ou inferior
        try {
            val albumIdColumn = arrayOf(MediaStore.Audio.Media.ALBUM_ID)
            val albumId = contentResolver.query(mediaUri, albumIdColumn, null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getLong(0) else null
                } ?: return null
            val artworkUri = Uri.parse("content://media/external/audio/albumart/$albumId")
            return contentResolver.openInputStream(artworkUri)?.use { it.readBytes() }
        } catch (_: Exception) {
            return null
        }
    }

    private fun audioCollection(): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

    private fun deleteAudio(mediaId: Long, result: MethodChannel.Result) {
        try {
            val cachedArtwork = File(applicationContext.filesDir, "artwork_$mediaId.jpg")
            if (cachedArtwork.exists()) cachedArtwork.delete()
        } catch (_: Exception) {}

        val uri = ContentUris.withAppendedId(audioCollection(), mediaId)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            pendingDeleteResult = result
            try {
                val request = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
                startIntentSenderForResult(
                    request.intentSender,
                    deleteRequestCode,
                    null,
                    0,
                    0,
                    0
                )
            } catch (error: Exception) {
                pendingDeleteResult = null
                result.error("delete_request_failed", error.message, null)
            }
            return
        }

        try {
            result.success(contentResolver.delete(uri, null, null) > 0)
        } catch (error: RecoverableSecurityException) {
            pendingDeleteUri = uri
            pendingDeleteResult = result
            try {
                startIntentSenderForResult(
                    error.userAction.actionIntent.intentSender,
                    deleteRequestCode,
                    null,
                    0,
                    0,
                    0
                )
            } catch (launchError: Exception) {
                pendingDeleteUri = null
                pendingDeleteResult = null
                result.error("delete_request_failed", launchError.message, null)
            }
        } catch (error: Exception) {
            result.error("delete_failed", error.message, null)
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != deleteRequestCode) return

        val result = pendingDeleteResult ?: return
        val uri = pendingDeleteUri
        pendingDeleteResult = null
        pendingDeleteUri = null

        if (resultCode != RESULT_OK) {
            result.success(false)
            return
        }

        if (uri == null) {
            result.success(true)
            return
        }

        result.success(true)
    }
}
