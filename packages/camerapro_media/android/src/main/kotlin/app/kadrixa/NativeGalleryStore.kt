package app.kadrixa

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/** Stable capture filenames make gallery insertion safe to repeat after process death. */
class NativeGalleryStore(private val context: Context) {
    fun save(source: File, isVideo: Boolean, displayName: String = source.name): Uri {
        require(source.isFile && source.length() > 0) { "Media file is empty or missing" }
        if (isVideo) validateVideo(source)
        val mime = if (isVideo) "video/mp4" else "image/jpeg"
        val directory = if (isVideo) Environment.DIRECTORY_MOVIES else "${Environment.DIRECTORY_DCIM}/Camera"
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveModern(source, isVideo, displayName, mime, "$directory/")
        } else {
            saveLegacy(source, displayName, mime, directory)
        }
    }

    private fun validateVideo(source: File) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(source.absolutePath)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            check(duration > 0 && width > 0 && height > 0) { "Video has no valid frames" }
        } finally {
            retriever.release()
        }
    }

    private fun saveModern(source: File, isVideo: Boolean, name: String, mime: String, directory: String): Uri {
        val resolver = context.contentResolver
        val collection = if (isVideo) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        var pendingUri: Uri? = null
        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.IS_PENDING),
            "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.OWNER_PACKAGE_NAME}=?",
            arrayOf(name, directory, context.packageName),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val uri = ContentUris.withAppendedId(collection, cursor.getLong(0))
                if (cursor.getInt(1) == 0) return uri
                pendingUri = uri
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, directory)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = pendingUri ?: resolver.insert(collection, values)
            ?: error("Unable to create gallery item")
        try {
            resolver.openOutputStream(uri, "wt")?.use { output ->
                source.inputStream().use { it.copyTo(output) }
            } ?: error("Unable to open gallery output")
            val published = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            check(resolver.update(uri, published, null, null) == 1) { "Unable to publish gallery item" }
            return uri
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(source: File, name: String, mime: String, directory: String): Uri {
        val targetDirectory = Environment.getExternalStoragePublicDirectory(directory)
        check(targetDirectory.isDirectory || targetDirectory.mkdirs()) { "Unable to create gallery directory" }
        val destination = File(targetDirectory, name)
        if (!destination.isFile || destination.length() != source.length()) {
            val temporary = File(targetDirectory, ".$name.pending")
            source.copyTo(temporary, overwrite = true)
            check(temporary.renameTo(destination)) { "Unable to finalize gallery file" }
        }
        MediaScannerConnection.scanFile(context, arrayOf(destination.path), arrayOf(mime), null)
        return Uri.fromFile(destination)
    }
}
