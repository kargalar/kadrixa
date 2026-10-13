package app.kadrixa

import android.graphics.ImageFormat
import android.media.MediaRecorder
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CameraManager
import android.os.Build
import android.util.Log
import io.flutter.plugins.camera.PhysicalCameraRegistry

/** Discovers public cameras and the physical lenses exposed by logical cameras. */
internal class CameraCatalog(private val cameraManager: CameraManager) {
    fun discover(): List<Map<String, Any>> {
        PhysicalCameraRegistry.clear()
        val publicIds = cameraManager.cameraIdList.toSet()
        val characteristicsById = linkedMapOf<String, CameraCharacteristics>()
        for (id in publicIds) {
            readCharacteristics(id)?.let { characteristicsById[id] = it }
        }
        // Some Xiaomi ROMs filter auxiliary IDs from cameraIdList while still allowing
        // ordinary Camera2 access. Probe a bounded vendor range once at initialization.
        if (Build.MANUFACTURER.lowercase() in AUXILIARY_CAMERA_MANUFACTURERS) {
            for (index in 0 until AUXILIARY_CAMERA_ID_LIMIT) {
                val id = index.toString()
                if (id in characteristicsById) continue
                readCharacteristics(id)?.let { characteristicsById[id] = it }
            }
        }
        val cameras = linkedMapOf<String, Map<String, Any>>()
        Log.d(TAG, "Public camera IDs: $publicIds")

        for ((id, characteristics) in characteristicsById) {
            // Keep public logical cameras as the normal capture/fallback route.
            // Extra vendor containers repeat lenses that are discovered separately.
            if (id !in publicIds && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                characteristics.physicalCameraIds.isNotEmpty()) continue
            describe(id, characteristics)?.let { lens ->
                if (id in publicIds || cameras.values.none { sameLens(it, lens) }) {
                    cameras[id] = lens
                }
            }
        }
        for ((id, characteristics) in characteristicsById) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) continue

            for (physicalId in characteristics.physicalCameraIds.sorted()) {
                if (physicalId in cameras) continue
                val physicalCharacteristics = readCharacteristics(physicalId) ?: continue
                val lens = describe(physicalId, physicalCharacteristics) ?: continue
                if (cameras.values.any { sameLens(it, lens) }) continue
                PhysicalCameraRegistry.register(physicalId, id)
                cameras[physicalId] = lens + ("logicalCameraId" to id)
            }
        }
        Log.d(TAG, "Available lens IDs: ${cameras.keys}")
        return cameras.values.toList()
    }

    private fun readCharacteristics(id: String): CameraCharacteristics? = try {
        cameraManager.getCameraCharacteristics(id)
    } catch (error: Exception) {
        Log.d(TAG, "Camera $id is unavailable: ${error.message}")
        null
    }

    private fun describe(id: String, chars: CameraCharacteristics): Map<String, Any>? {
        val lensFacing = chars.get(CameraCharacteristics.LENS_FACING) ?: return null
        val streams = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val jpegSizes = streams?.getOutputSizes(ImageFormat.JPEG)
        // Depth/infrared-only sensors cannot serve as ordinary photo/video lenses.
        if (jpegSizes.isNullOrEmpty()) return null
        if (streams.getOutputSizes(MediaRecorder::class.java).isNullOrEmpty()) return null
        val maxJpegSize = jpegSizes.maxBy { it.width.toLong() * it.height }
        val details = mutableMapOf<String, Any>(
            "id" to id,
            "lensFacing" to lensFacing,
            "sensorOrientation" to (chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0),
            "supportsManualFocus" to (
                (chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f) > 0f &&
                chars.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)?.contains(CaptureRequest.CONTROL_AF_MODE_OFF) == true &&
                chars.availableCaptureRequestKeys?.contains(CaptureRequest.LENS_FOCUS_DISTANCE) == true
            ),
            "focalLengths" to (chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                ?.map { it.toDouble() } ?: emptyList<Double>()),
            "physicalCameraIds" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                chars.physicalCameraIds.sorted()
            } else {
                emptyList<String>()
            },
            "maxJpegWidth" to maxJpegSize.width,
            "maxJpegHeight" to maxJpegSize.height,
        )
        chars.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)?.let {
            details["sensorWidth"] = it.width.toDouble()
            details["sensorHeight"] = it.height.toDouble()
        }
        chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE)?.let {
            details["minimumFocusDistance"] = it.toDouble()
        }
        Log.d(TAG, "Lens $id: $details")
        return details
    }

    private companion object {
        const val TAG = "CameraProCatalog"
        const val AUXILIARY_CAMERA_ID_LIMIT = 16
        val AUXILIARY_CAMERA_MANUFACTURERS = setOf("xiaomi", "redmi", "poco")
        val LENS_IDENTITY_KEYS = listOf(
            "lensFacing", "sensorOrientation", "focalLengths", "sensorWidth", "sensorHeight",
            "minimumFocusDistance", "maxJpegWidth", "maxJpegHeight",
        )
    }

    private fun sameLens(first: Map<String, Any>, second: Map<String, Any>): Boolean =
        LENS_IDENTITY_KEYS.all { first[it] == second[it] }
}
