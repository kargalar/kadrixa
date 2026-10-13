package app.kadrixa

import kotlin.math.abs
import kotlin.math.roundToInt

data class CropRegion(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
}

object PhotoCropCalculator {
    private const val ASPECT_RATIO_TOLERANCE = 0.005

    fun calculate(
        width: Int,
        height: Int,
        targetEncodedAspectRatio: Double,
    ): CropRegion {
        require(width > 0 && height > 0) { "Image dimensions must be positive" }
        require(targetEncodedAspectRatio.isFinite() && targetEncodedAspectRatio > 0) { "Target aspect ratio must be finite and positive" }

        val currentRawAspectRatio = width.toDouble() / height

        if (abs(currentRawAspectRatio - targetEncodedAspectRatio) < ASPECT_RATIO_TOLERANCE) {
            return CropRegion(0, 0, width, height)
        }

        return if (currentRawAspectRatio > targetEncodedAspectRatio) {
            val cropWidth = (height * targetEncodedAspectRatio).roundToInt().coerceIn(1, width)
            val left = (width - cropWidth) / 2
            CropRegion(left, 0, left + cropWidth, height)
        } else {
            val cropHeight = (width / targetEncodedAspectRatio).roundToInt().coerceIn(1, height)
            val top = (height - cropHeight) / 2
            CropRegion(0, top, width, top + cropHeight)
        }
    }
}
