package app.kadrixa

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.ExifInterface
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativePhotoProcessorTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val processor = NativePhotoProcessor(context)
    private val red = Color.rgb(230, 20, 20)
    private val green = Color.rgb(20, 210, 20)
    private val blue = Color.rgb(20, 20, 230)
    private val yellow = Color.rgb(230, 210, 20)

    @Test
    fun mirrorsDisplayCoordinatesForEveryExifOrientationAndSurvivesRetry() {
        val expectedCorners = mapOf(
            1 to listOf(green, red, yellow, blue),
            2 to listOf(green, red, yellow, blue),
            3 to listOf(blue, yellow, red, green),
            4 to listOf(blue, yellow, red, green),
            5 to listOf(red, blue, green, yellow),
            6 to listOf(red, blue, green, yellow),
            7 to listOf(yellow, green, blue, red),
            8 to listOf(yellow, green, blue, red),
        )
        expectedCorners.forEach { (orientation, corners) ->
            withCapture(orientation) { source ->
                process(source, 4.0 / 3.0, mirror = true)
                val bitmap = BitmapFactory.decodeFile(source.path)
                try {
                    assertEquals(if (orientation >= 5) 60 else 80, bitmap.width)
                    assertEquals(if (orientation >= 5) 80 else 60, bitmap.height)
                    assertCorners(bitmap, corners)
                } finally {
                    bitmap.recycle()
                }
                assertEquals(
                    ExifInterface.ORIENTATION_NORMAL,
                    ExifInterface(source.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 0),
                )
                val original = source.readBytes()
                process(source, 4.0 / 3.0, mirror = true)
                assertArrayEquals(original, source.readBytes())
                process(source, 1.0, mirror = true)
                val square = BitmapFactory.decodeFile(source.path)
                try {
                    assertEquals(square.width, square.height)
                    assertCorners(square, corners)
                } finally {
                    square.recycle()
                }
            }
        }
    }

    @Test
    fun cropsAndMirrorsInOnePassAndPublishesTheSamePixelsToGallery() {
        withCapture(ExifInterface.ORIENTATION_ROTATE_90) { source ->
            val result = process(source, 1.0, mirror = true, saveToGallery = true)
            val uri = Uri.parse(result["galleryUri"] as String)
            try {
                assertTrue(result["didCrop"] == true)
                val savedBytes = context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                assertArrayEquals(source.readBytes(), savedBytes)
                val bitmap = BitmapFactory.decodeByteArray(savedBytes, 0, savedBytes.size)
                try {
                    assertEquals(60, bitmap.width)
                    assertEquals(60, bitmap.height)
                    assertCorners(bitmap, listOf(red, blue, green, yellow))
                } finally {
                    bitmap.recycle()
                }
            } finally {
                context.contentResolver.delete(uri, null, null)
            }
        }
    }

    @Test
    fun rearCameraCaptureKeepsItsOriginalPixelsAndExif() {
        withCapture(ExifInterface.ORIENTATION_ROTATE_90) { source ->
            val original = source.readBytes()
            process(source, 4.0 / 3.0, mirror = false)
            assertArrayEquals(original, source.readBytes())
        }
    }

    private fun process(
        source: File,
        ratio: Double,
        mirror: Boolean,
        saveToGallery: Boolean = false,
    ) = processor.process(
        sourcePath = source.path,
        targetAspectRatio = ratio,
        jpegQuality = 100,
        saveToGallery = saveToGallery,
        mirrorHorizontally = mirror,
    )

    private fun withCapture(orientation: Int, verify: (File) -> Unit) {
        val source = File.createTempFile("mirroring_test_", ".jpg", context.cacheDir)
        val bitmap = Bitmap.createBitmap(80, 60, Bitmap.Config.ARGB_8888)
        try {
            for (y in 0 until bitmap.height) {
                for (x in 0 until bitmap.width) {
                    val color = if (y < 30) {
                        if (x < 40) red else green
                    } else {
                        if (x < 40) blue else yellow
                    }
                    bitmap.setPixel(x, y, color)
                }
            }
            source.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it) }
            ExifInterface(source.path).apply {
                setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
                saveAttributes()
            }
            verify(source)
        } finally {
            bitmap.recycle()
            source.delete()
        }
    }

    private fun assertCorners(bitmap: Bitmap, expected: List<Int>) {
        val actual = listOf(
            bitmap.getPixel(8, 8),
            bitmap.getPixel(bitmap.width - 9, 8),
            bitmap.getPixel(8, bitmap.height - 9),
            bitmap.getPixel(bitmap.width - 9, bitmap.height - 9),
        )
        actual.zip(expected).forEach { (pixel, color) ->
            assertTrue(kotlin.math.abs(Color.red(pixel) - Color.red(color)) < 15)
            assertTrue(kotlin.math.abs(Color.green(pixel) - Color.green(color)) < 15)
            assertTrue(kotlin.math.abs(Color.blue(pixel) - Color.blue(color)) < 15)
        }
    }
}
