package app.kadrixa

import android.media.MediaMetadataRetriever
import java.io.File

object RecordedVideoMetadata {
    fun read(source: File): Map<String, Int> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(source.absolutePath)
            fun value(key: Int) = retriever.extractMetadata(key)?.toIntOrNull() ?: 0
            val width = value(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val height = value(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            check(width > 0 && height > 0) { "Video has no valid dimensions" }
            return mapOf(
                "width" to width,
                "height" to height,
                "rotation" to value(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION),
            )
        } finally {
            retriever.release()
        }
    }
}
