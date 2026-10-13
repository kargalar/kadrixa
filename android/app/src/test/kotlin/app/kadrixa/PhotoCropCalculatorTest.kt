package app.kadrixa

import org.junit.Assert.assertEquals
import org.junit.Test

class PhotoCropCalculatorTest {
    @Test
    fun matchingRatioKeepsTheWholeImage() {
        val region = PhotoCropCalculator.calculate(
            width = 4000,
            height = 3000,
            targetEncodedAspectRatio = 4.0 / 3.0,
        )

        assertEquals(CropRegion(0, 0, 4000, 3000), region)
    }

    @Test
    fun squareTargetUsesACenteredRegion() {
        val region = PhotoCropCalculator.calculate(
            width = 4000,
            height = 3000,
            targetEncodedAspectRatio = 1.0,
        )

        assertEquals(CropRegion(500, 0, 3500, 3000), region)
    }

    @Test
    fun exifRotationDoesNotChangeTheEncodedTargetAspectRatio() {
        val region = PhotoCropCalculator.calculate(
            width = 4000,
            height = 3000,
            targetEncodedAspectRatio = 16.0 / 9.0,
        )

        assertEquals(CropRegion(0, 375, 4000, 2625), region)
    }
}
