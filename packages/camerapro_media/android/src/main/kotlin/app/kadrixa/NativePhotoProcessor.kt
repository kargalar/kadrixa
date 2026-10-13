package app.kadrixa

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Matrix
import android.graphics.Rect
import android.media.ExifInterface
import android.net.Uri
import android.system.Os
import java.io.File
import java.io.FileOutputStream

class NativePhotoProcessor(private val context: Context) {
    fun process(
        sourcePath: String,
        targetAspectRatio: Double,
        jpegQuality: Int,
        saveToGallery: Boolean,
        mirrorHorizontally: Boolean = false,
        latitude: Double? = null,
        longitude: Double? = null,
        altitude: Double? = null,
    ): Map<String, Any?> {
        val source = File(sourcePath)
        require(source.isFile) { "Source photo does not exist: $sourcePath" }
        val displayName = source.name

        val sourceExif = ExifInterface(sourcePath)
        val orientation = sourceExif.getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
        val bounds = readBounds(sourcePath)
        val region = PhotoCropCalculator.calculate(
            width = bounds.first,
            height = bounds.second,
            targetEncodedAspectRatio = if (bounds.first >= bounds.second) targetAspectRatio else 1.0 / targetAspectRatio,
        )
        val didCrop = region.width != bounds.first || region.height != bounds.second
        val needsMirror = mirrorHorizontally &&
            sourceExif.getAttribute(ExifInterface.TAG_SOFTWARE) != PREVIEW_MIRROR_SOFTWARE
        val needsProcessing = didCrop || needsMirror
        var temporaryFile: File? = null

        try {
            val fileToSave = if (needsProcessing) {
                temporaryFile = processToTemporaryFile(
                    source = source,
                    sourceExif = sourceExif,
                    orientation = orientation,
                    region = region,
                    jpegQuality = jpegQuality.coerceIn(80, 100),
                    mirrorToPreview = needsMirror,
                )
                temporaryFile
            } else {
                source
            }

            if (latitude != null && longitude != null) {
                val outputExif = ExifInterface(fileToSave.absolutePath)
                outputExif.setAttribute(
                    ExifInterface.TAG_GPS_LATITUDE_REF,
                    if (latitude >= 0) "N" else "S",
                )
                outputExif.setAttribute(
                    ExifInterface.TAG_GPS_LATITUDE,
                    toExifCoordinate(latitude),
                )
                outputExif.setAttribute(
                    ExifInterface.TAG_GPS_LONGITUDE_REF,
                    if (longitude >= 0) "E" else "W",
                )
                outputExif.setAttribute(
                    ExifInterface.TAG_GPS_LONGITUDE,
                    toExifCoordinate(longitude),
                )
                if (altitude != null) {
                    outputExif.setAttribute(
                        ExifInterface.TAG_GPS_ALTITUDE_REF,
                        if (altitude < 0) "1" else "0",
                    )
                    outputExif.setAttribute(
                        ExifInterface.TAG_GPS_ALTITUDE,
                        "${kotlin.math.abs(altitude * 100).toLong()}/100",
                    )
                }
                outputExif.saveAttributes()
            }

            val previewFile = if (needsProcessing) {
                replaceSourceAtomically(source, requireNotNull(temporaryFile))
            } else {
                source
            }
            val galleryUri = if (saveToGallery) {
                saveToGallery(previewFile, displayName)
            } else {
                null
            }

            return mapOf(
                "success" to true,
                "path" to previewFile.absolutePath,
                "galleryUri" to galleryUri?.toString(),
                "didCrop" to didCrop,
            )
        } catch (error: Throwable) {
            temporaryFile?.takeIf { it.exists() }?.delete()
            throw error
        }
    }

    private fun readBounds(path: String): Pair<Int, Int> {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, options)
        check(options.outWidth > 0 && options.outHeight > 0) {
            "Unable to read JPEG dimensions"
        }
        return options.outWidth to options.outHeight
    }

    @Suppress("DEPRECATION")
    private fun processToTemporaryFile(
        source: File,
        sourceExif: ExifInterface,
        orientation: Int,
        region: CropRegion,
        jpegQuality: Int,
        mirrorToPreview: Boolean,
    ): File {
        val decoder = BitmapRegionDecoder.newInstance(source.absolutePath, false)
        val bitmap = try {
            decoder.decodeRegion(
                Rect(region.left, region.top, region.right, region.bottom),
                BitmapFactory.Options().apply {
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                },
            ) ?: error("Unable to decode JPEG crop region")
        } finally {
            decoder.recycle()
        }

        var processedBitmap = bitmap
        val output = File.createTempFile("processed_", ".jpg", source.parentFile)
        try {
            if (mirrorToPreview) {
                processedBitmap = Bitmap.createBitmap(
                    bitmap, 0, 0, bitmap.width, bitmap.height,
                    previewMirrorMatrix(orientation), false,
                )
            }
            FileOutputStream(output).use { stream ->
                check(processedBitmap.compress(Bitmap.CompressFormat.JPEG, jpegQuality, stream)) {
                    "Unable to encode processed JPEG"
                }
            }
            copyExif(
                sourceExif, output,
                if (mirrorToPreview) ExifInterface.ORIENTATION_NORMAL else orientation,
                mirrorToPreview,
            )
            return output
        } catch (error: Throwable) {
            output.delete()
            throw error
        } finally {
            if (processedBitmap !== bitmap) processedBitmap.recycle()
            bitmap.recycle()
        }
    }

    private fun previewMirrorMatrix(orientation: Int): Matrix = Matrix().apply {
        val rotation = when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_180,
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> 180f
            ExifInterface.ORIENTATION_ROTATE_90,
            ExifInterface.ORIENTATION_TRANSPOSE -> 90f
            ExifInterface.ORIENTATION_ROTATE_270,
            ExifInterface.ORIENTATION_TRANSVERSE -> 270f
            else -> 0f
        }
        setRotate(rotation)
        // Apply reflection after rotation so left/right refer to the image
        // as displayed, including portrait and both landscape directions.
        postScale(-1f, 1f)
    }

    private fun copyExif(
        sourceExif: ExifInterface,
        output: File,
        orientation: Int,
        mirrorToPreview: Boolean,
    ) {
        val outputExif = ExifInterface(output.absolutePath)
        EXIF_TAGS_TO_COPY.forEach { tag ->
            sourceExif.getAttribute(tag)?.let { outputExif.setAttribute(tag, it) }
        }
        outputExif.setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
        if (mirrorToPreview) {
            // Stored with the pixels in the atomic replacement: a retried
            // background job must never mirror the same photo a second time.
            outputExif.setAttribute(ExifInterface.TAG_SOFTWARE, PREVIEW_MIRROR_SOFTWARE)
        }
        outputExif.saveAttributes()
    }

    private fun saveToGallery(source: File, displayName: String): Uri =
        NativeGalleryStore(context).save(source, isVideo = false, displayName = displayName)

    private fun replaceSourceAtomically(source: File, processed: File): File {
        return try {
            Os.rename(processed.absolutePath, source.absolutePath)
            source
        } catch (_: Throwable) {
            processed
        }
    }

    private fun toExifCoordinate(value: Double): String {
        val absolute = kotlin.math.abs(value)
        val degrees = absolute.toInt()
        val minutesWithFraction = (absolute - degrees) * 60.0
        val minutes = minutesWithFraction.toInt()
        val seconds = (minutesWithFraction - minutes) * 60.0
        val denominator = 1_000_000L
        val numerator = kotlin.math.round(seconds * denominator).toLong()
        return "$degrees/1,$minutes/1,$numerator/$denominator"
    }

    companion object {
        private const val PREVIEW_MIRROR_SOFTWARE = "Kadrixa:preview-mirrored:v1"
        private val EXIF_TAGS_TO_COPY = arrayOf(
            ExifInterface.TAG_DATETIME,
            ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_DATETIME_DIGITIZED,
            ExifInterface.TAG_MAKE,
            ExifInterface.TAG_MODEL,
            ExifInterface.TAG_F_NUMBER,
            ExifInterface.TAG_EXPOSURE_TIME,
            ExifInterface.TAG_ISO_SPEED_RATINGS,
            ExifInterface.TAG_FOCAL_LENGTH,
            ExifInterface.TAG_FLASH,
            ExifInterface.TAG_WHITE_BALANCE,
            ExifInterface.TAG_SOFTWARE,
            ExifInterface.TAG_GPS_LATITUDE,
            ExifInterface.TAG_GPS_LATITUDE_REF,
            ExifInterface.TAG_GPS_LONGITUDE,
            ExifInterface.TAG_GPS_LONGITUDE_REF,
            ExifInterface.TAG_GPS_ALTITUDE,
            ExifInterface.TAG_GPS_ALTITUDE_REF,
        )
    }
}
