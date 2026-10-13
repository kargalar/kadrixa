package app.kadrixa

import android.app.Activity
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.SystemClock
import android.provider.MediaStore
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Runs actual Camera2 captures and verifies the Android capture-for-result contract. */
@RunWith(AndroidJUnit4::class)
class CameraIntentIntegrationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val resolver = context.contentResolver

    @Test
    fun photoWithoutOutputReturnsSmallBitmap() {
        launch(MediaStore.ACTION_IMAGE_CAPTURE).use { scenario ->
            clickCapture("Take photo")
            awaitFinished(scenario)
            val result = scenario.result
            assertEquals(Activity.RESULT_OK, result.resultCode)
            @Suppress("DEPRECATION")
            val bitmap = result.resultData?.getParcelableExtra<Bitmap>("data")
            assertNotNull(bitmap)
            assertTrue(maxOf(bitmap!!.width, bitmap.height) <= 256)
        }
    }

    @Test
    fun photoWithOutputWritesFullImageToCallerUri() {
        val uri = createOutput(false)
        try {
            launch(MediaStore.ACTION_IMAGE_CAPTURE, uri).use { scenario ->
                clickCapture("Take photo")
                awaitFinished(scenario)
                assertEquals(Activity.RESULT_OK, scenario.result.resultCode)
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                resolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, options) }
                assertTrue(options.outWidth >= 1000)
                assertTrue(options.outHeight >= 1000)
            }
        } finally {
            resolver.delete(uri, null, null)
        }
    }

    @Test
    fun videoWithOutputHonorsDurationAndReturnsPlayableAudioVideo() {
        val uri = createOutput(true)
        try {
            launch(MediaStore.ACTION_VIDEO_CAPTURE, uri).use { scenario ->
                clickCapture("Start recording")
                awaitFinished(scenario)
                assertEquals(Activity.RESULT_OK, scenario.result.resultCode)
                assertEquals(uri, scenario.result.resultData?.data)
                verifyVideo(uri)
            }
        } finally {
            resolver.delete(uri, null, null)
        }
    }

    @Test
    fun videoWithoutOutputReturnsReadableGrantedContentUri() {
        launch(MediaStore.ACTION_VIDEO_CAPTURE).use { scenario ->
            clickCapture("Start recording")
            awaitFinished(scenario)
            val result = scenario.result
            assertEquals(Activity.RESULT_OK, result.resultCode)
            val data = requireNotNull(result.resultData)
            val uri = requireNotNull(data.data)
            assertEquals("content", uri.scheme)
            assertTrue(data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
            verifyVideo(uri)
            // This URI was created specifically for this test.
            resolver.delete(uri, null, null)
        }
    }

    private fun launch(action: String, output: Uri? = null): ActivityScenario<CameraIntentActivity> {
        val intent = Intent(context, CameraIntentActivity::class.java).apply {
            this.action = action
            putExtra(MediaStore.EXTRA_VIDEO_QUALITY, 0)
            putExtra(MediaStore.EXTRA_DURATION_LIMIT, 2)
            if (output != null) {
                putExtra(MediaStore.EXTRA_OUTPUT, output)
                clipData = ClipData.newRawUri("CameraPro test output", output)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
        }
        return ActivityScenario.launchActivityForResult(intent)
    }

    private fun createOutput(video: Boolean): Uri {
        val collection = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "camerapro_intent_test_${System.nanoTime()}.${if (video) "mp4" else "jpg"}")
            put(MediaStore.MediaColumns.MIME_TYPE, if (video) "video/mp4" else "image/jpeg")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        return requireNotNull(resolver.insert(collection, values))
    }

    private fun verifyVideo(uri: Uri) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
            assertTrue("Duration must obey the caller limit: $duration", duration in 500..3500)
            assertEquals("yes", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO))
            assertEquals("yes", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO))
            assertNotNull(retriever.getFrameAtTime(0))
        } finally {
            retriever.release()
        }
    }

    private fun clickCapture(label: String) {
        val deadline = SystemClock.uptimeMillis() + TIMEOUT_MS
        while (SystemClock.uptimeMillis() < deadline) {
            val node = findNode(instrumentation.uiAutomation.rootInActiveWindow, label)
            if (node != null && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return
            SystemClock.sleep(100)
        }
        fail("Camera capture button unavailable: $label")
    }

    private fun findNode(node: AccessibilityNodeInfo?, label: String): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.contentDescription?.contains(label) == true && node.isClickable) return node
        for (index in 0 until node.childCount) {
            findNode(node.getChild(index), label)?.let { return it }
        }
        return null
    }

    private fun awaitFinished(scenario: ActivityScenario<CameraIntentActivity>) {
        val deadline = SystemClock.uptimeMillis() + TIMEOUT_MS
        while (scenario.state != androidx.lifecycle.Lifecycle.State.DESTROYED && SystemClock.uptimeMillis() < deadline) {
            SystemClock.sleep(100)
        }
        assertEquals(androidx.lifecycle.Lifecycle.State.DESTROYED, scenario.state)
    }

    companion object { private const val TIMEOUT_MS = 30_000L }
}
