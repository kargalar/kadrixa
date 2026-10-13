package app.kadrixa

import android.content.Context
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import io.flutter.plugins.camera.CameraPlugin
import io.flutter.plugins.camera.CameraAccessor
import io.flutter.plugins.camera.features.resolution.PhotoAspectRatioStore

open class MainActivity : FlutterActivity() {
    private val CHANNEL = "app.kadrixa/cameras"
    private var cameraIntentHandler: CameraIntentHandler? = null
    private var dualCameraController: DualCameraController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dualCameraController = DualCameraController(this, flutterEngine.renderer, flutterEngine.dartExecutor.binaryMessenger)
        cameraIntentHandler = CameraIntentHandler(this, this is CameraIntentActivity).also {
            it.attach(MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.kadrixa/camera_intents"))
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllPhysicalCameras" -> {
                    val cameraList = getAllPhysicalCameras()
                    result.success(cameraList)
                }
                "setRecordingMicrophone" -> {
                    val deviceId = call.argument<String>("deviceId")
                    try {
                        val plugin = flutterEngine?.plugins?.get(CameraPlugin::class.java) as? CameraPlugin
                            ?: throw IllegalStateException("Camera plugin is unavailable.")
                        CameraAccessor.setPreferredAudioDeviceId(plugin, deviceId)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("MICROPHONE_SELECTION_FAILED", error.message, null)
                    }
                }
                "configureVideoRecording" -> {
                    try {
                        val preset = requireNotNull(call.argument<String>("preset"))
                        val plugin = flutterEngine?.plugins?.get(CameraPlugin::class.java) as? CameraPlugin
                            ?: throw IllegalStateException("Camera plugin is unavailable.")
                        CameraAccessor.configureVideoRecording(plugin, preset, call.argument<Boolean>("allowStillCapture") ?: true)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("VIDEO_RESOLUTION_FAILED", error.message, null)
                    }
                }
                "getRoutedRecordingMicrophone" -> {
                    val plugin = flutterEngine?.plugins?.get(CameraPlugin::class.java) as? CameraPlugin
                    result.success(plugin?.let(CameraAccessor::getRoutedAudioDeviceId))
                }
                "isVideoRecordingStarted" -> {
                    val plugin = flutterEngine?.plugins?.get(CameraPlugin::class.java) as? CameraPlugin
                    result.success(plugin?.let(CameraAccessor::isVideoRecordingStarted) ?: false)
                }
                "getRecordingAmplitudeDb" -> {
                    val plugin = flutterEngine?.plugins?.get(CameraPlugin::class.java) as? CameraPlugin
                    result.success(plugin?.let(CameraAccessor::getRecordingAmplitudeDb) ?: -50.0)
                }
                "setManualISO" -> {
                    val iso = call.argument<Int>("iso")
                    if (iso != null) {
                        setCaptureRequestOption(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_OFF)
                        setCaptureRequestOption(CaptureRequest.SENSOR_SENSITIVITY, iso)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "ISO value is null", null)
                    }
                }
                "setManualShutter" -> {
                    val shutterNanos = call.argument<Number>("shutterNanos")?.toLong()
                    if (shutterNanos != null) {
                        setCaptureRequestOption(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_OFF)
                        setCaptureRequestOption(CaptureRequest.SENSOR_EXPOSURE_TIME, shutterNanos)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Shutter value is null", null)
                    }
                }
                "setManualFocus" -> {
                    val focusDistance = call.argument<Double>("focusDistance")?.toFloat()
                    try {
                        require(focusDistance != null && focusDistance.isFinite()) { "Focus distance must be finite." }
                        val plugin = flutterEngine.plugins.get(CameraPlugin::class.java) as? CameraPlugin
                            ?: error("Camera plugin is unavailable.")
                        CameraAccessor.setManualFocusDistance(plugin, focusDistance, result)
                    } catch (error: Exception) {
                        result.error("MANUAL_FOCUS_FAILED", error.message, null)
                    }
                }
                "setAutoMode" -> {
                    setCaptureRequestOption(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                    try {
                        val plugin = flutterEngine.plugins.get(CameraPlugin::class.java) as? CameraPlugin
                            ?: error("Camera plugin is unavailable.")
                        CameraAccessor.setManualFocusDistance(plugin, null, result)
                    } catch (error: Exception) {
                        result.error("AUTO_FOCUS_FAILED", error.message, null)
                    }
                }
                "setPhotoCaptureAspectRatio" -> {
                    val ratio = call.argument<Double>("ratio")
                    if (ratio != null && ratio.isFinite() && ratio > 0.0) {
                        PhotoAspectRatioStore.setTargetAspectRatio(ratio)
                        PhotoAspectRatioStore.setVideoPreviewEnabled(call.argument<Boolean>("videoPreview") ?: false)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Aspect ratio must be positive", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

    }

    override fun onDestroy() {
        dualCameraController?.detach()
        cameraIntentHandler?.dispose()
        super.onDestroy()
    }

    private fun setCaptureRequestOption(key: CaptureRequest.Key<*>, value: Any) {
        try {
            val plugin = flutterEngine?.plugins?.get(CameraPlugin::class.java) as? CameraPlugin
            if (plugin != null) {
                CameraAccessor.setCaptureRequestOption(plugin, key, value)
            }
        } catch (e: Exception) {
            Log.e("CameraProMainActivity", "Error setting capture request option", e)
        }
    }

    private fun getAllPhysicalCameras(): List<Map<String, Any>> = try {
        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        CameraCatalog(cameraManager).discover()
    } catch (error: Exception) {
        Log.e("CameraProMainActivity", "Cannot discover cameras", error)
        emptyList()
    }
}
