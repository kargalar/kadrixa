package app.kadrixa

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class CameraIntentHandler(private val activity: Activity, private val cameraIntent: Boolean) {
    private val executor = Executors.newSingleThreadExecutor()
    private val request = activity.intent
    private val photo = request.action != MediaStore.ACTION_VIDEO_CAPTURE &&
        request.action != MediaStore.INTENT_ACTION_VIDEO_CAMERA
    private val returnCapture = request.action == MediaStore.ACTION_IMAGE_CAPTURE ||
        request.action == MediaStore.ACTION_VIDEO_CAPTURE
    private var completing = false

    fun attach(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchRequest" -> result.success(if (cameraIntent) mapOf(
                    "mode" to if (photo) "photo" else "video",
                    "returnCapture" to returnCapture,
                    "durationLimitSeconds" to request.getIntExtra(MediaStore.EXTRA_DURATION_LIMIT, 0).coerceAtLeast(0),
                    "lowVideoQuality" to (request.getIntExtra(MediaStore.EXTRA_VIDEO_QUALITY, 1) == 0),
                ) else null)
                "completeCapture" -> {
                    if (!cameraIntent || !returnCapture || completing) {
                        result.error("NO_CAPTURE_REQUEST", "No pending capture request", null)
                    } else {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_CAPTURE", "Capture path is missing", null)
                        } else {
                            completing = true
                            executor.execute {
                                try {
                                    val response = createResponse(path)
                                    activity.runOnUiThread {
                                        result.success(null)
                                        activity.setResult(Activity.RESULT_OK, response)
                                        activity.finish()
                                    }
                                } catch (error: Exception) {
                                    activity.runOnUiThread {
                                        completing = false
                                        result.error("CAPTURE_DELIVERY_FAILED", error.message, null)
                                    }
                                }
                            }
                        }
                    }
                }
                "cancelCapture" -> {
                    activity.setResult(Activity.RESULT_CANCELED)
                    result.success(null)
                    activity.finish()
                }
                "openCameraSelector" -> {
                    try {
                        activity.startActivity(Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("SETTINGS_UNAVAILABLE", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun outputUri(): Uri? = if (Build.VERSION.SDK_INT >= 33) {
        request.getParcelableExtra(MediaStore.EXTRA_OUTPUT, Uri::class.java)
    } else {
        request.getParcelableExtra(MediaStore.EXTRA_OUTPUT)
    } ?: request.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri

    private fun createResponse(path: String): Intent {
        val source = File(path).canonicalFile
        require(source.path.startsWith(activity.dataDir.canonicalPath + File.separator))
        require(source.isFile && source.length() > 0) { "Capture file is empty" }
        val response = Intent()
        val destination = outputUri()
        if (destination != null) {
            require(destination.scheme == "content") { "Capture output must be a content URI" }
            activity.contentResolver.openOutputStream(destination, "wt")?.use { output ->
                source.inputStream().use { it.copyTo(output) }
            } ?: error("Cannot open requested capture output")
            if (!photo) response.setDataAndType(destination, "video/mp4")
        } else if (!photo) {
            val directory = File(activity.cacheDir, "returned_captures")
            check(directory.isDirectory || directory.mkdirs())
            val retained = File(directory, "video_${System.nanoTime()}.mp4")
            source.copyTo(retained)
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.captures", retained)
            response.setDataAndType(uri, "video/mp4")
            response.clipData = ClipData.newRawUri("Captured video", uri)
            response.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (photo) response.putExtra("data", thumbnail(source))
        source.delete()
        return response
    }

    private fun thumbnail(source: File): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.path, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > THUMBNAIL_EDGE * 2) sample *= 2
        val bitmap = requireNotNull(BitmapFactory.decodeFile(source.path, BitmapFactory.Options().apply {
            inSampleSize = sample
        })) { "Photo cannot be decoded" }
        val orientation = ExifInterface(source.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)
        val matrix = Matrix().apply {
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> postScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { postScale(-1f, 1f); postRotate(90f) }
                ExifInterface.ORIENTATION_TRANSVERSE -> { postScale(-1f, 1f); postRotate(270f) }
            }
            val scale = THUMBNAIL_EDGE.toFloat() / maxOf(bitmap.width, bitmap.height)
            if (scale < 1) postScale(scale, scale)
        }
        val resized = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (resized !== bitmap) bitmap.recycle()
        return resized
    }

    fun dispose() = executor.shutdown()

    companion object {
        private const val THUMBNAIL_EDGE = 256
    }
}
