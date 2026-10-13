package app.kadrixa

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.util.Size
import android.view.Surface
import android.view.OrientationEventListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File

internal object DualCameraMessages {
    const val CLOSED = "The dual-camera session is closed."
    const val CANCELLED = "Dual-camera startup was cancelled."
    const val UNSUPPORTED = "This device does not support simultaneous access to the front and rear cameras."
    const val TIMEOUT = "Could not start both cameras in time."
    const val INITIALIZATION_FAILED = "Could not initialize dual-camera mode."
    const val OPEN_FAILED = "Could not open both cameras."
    const val SESSION_FAILED = "Could not start simultaneous camera streaming on this device."
    const val STREAM_FAILED = "Could not start the camera stream."
    const val RENDER_FAILED = "Could not process the image."
    const val FRAME_FAILED = "Could not draw the image frame."
    const val CONNECTION_LOST = "Camera connection was lost."
    const val RECORDER_LOST = "Video recorder connection was lost."
    const val NOT_READY = "The cameras are not ready to record."
    const val MICROPHONE_UNAVAILABLE = "The selected microphone is unavailable."
    const val VIDEO_FAILED = "Could not save the video."
}

/** Owns both cameras independently of the single-camera Flutter plugin. */
internal class DualCameraController(
    private val context: Context,
    private val textures: TextureRegistry,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "app.kadrixa/dual_camera"
        private const val INITIALIZATION_TIMEOUT_MS = 12_000L
        private const val VIDEO_BIT_RATE = 5_000_000
        private const val AUDIO_BIT_RATE = 128_000
        private const val AUDIO_SAMPLE_RATE = 48_000
        private const val MAX_INPUT_WIDTH = 1280
        private const val MAX_INPUT_HEIGHT = 720
    }

    private val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val main = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("DualCameraSessions").apply { start() }
    private val handler = Handler(thread.looper)
    private val channel = MethodChannel(messenger, CHANNEL)
    private val events = EventChannel(messenger, "$CHANNEL/events")
    private var eventSink: EventChannel.EventSink? = null
    private var texture: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurface: Surface? = null
    private var renderer: DualCameraRenderer? = null
    private val devices = arrayOfNulls<CameraDevice>(2)
    private val sessions = arrayOfNulls<CameraCaptureSession>(2)
    private var initialized = false
    private var pendingInitialization: MethodChannel.Result? = null
    private var recorder: MediaRecorder? = null
    private var output: File? = null
    private var generation = 0
    private var closed = false
    private var frameWidth = 720
    private var frameHeight = 1280
    private var frameRotation = 0
    private var lastSensorOrientation = -1
    private val orientationListener = object : OrientationEventListener(context) {
        override fun onOrientationChanged(angle: Int) {
            if (angle == ORIENTATION_UNKNOWN) return
            val quadrant = ((angle + 45) / 90) % 4
            if (quadrant == lastSensorOrientation) return
            lastSensorOrientation = quadrant
            val orientation = arrayOf("portraitUp", "landscapeLeft", "portraitDown", "landscapeRight")[quadrant]
            eventSink?.success(mapOf("orientation" to orientation))
        }
    }
    private val initializationTimeout = Runnable { fail(DualCameraMessages.TIMEOUT) }

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { eventSink = sink }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })
        channel.setMethodCallHandler { call, result ->
            if (closed) {
                result.error("dualCameraClosed", DualCameraMessages.CLOSED, null)
            } else handler.post {
                try {
                    when (call.method) {
                        "initialize" -> {
                            readConfiguration(call.argument<Int>("width"), call.argument<Int>("height"), call.argument<Int>("rotation"))
                            initialize(result)
                        }
                        "configure" -> {
                            check(recorder == null)
                            readConfiguration(call.argument<Int>("width"), call.argument<Int>("height"), call.argument<Int>("rotation"))
                            texture?.surfaceTexture()?.setDefaultBufferSize(frameWidth, frameHeight)
                            requireNotNull(renderer).configure(frameWidth, frameHeight, frameRotation)
                            success(result, previewInfo())
                        }
                        "swap" -> {
                            requireNotNull(renderer).swap(call.argument<Boolean>("frontIsMain") ?: false)
                            success(result, null)
                        }
                        "startRecording" -> {
                            startRecording(call.argument<String>("microphoneId"))
                            success(result, null)
                        }
                        "stopRecording" -> success(result, stopRecording())
                        "dispose" -> { cancelInitialization(); release(); success(result, null) }
                        else -> main.post { result.notImplemented() }
                    }
                } catch (error: Exception) {
                    Log.e("DualCamera", "${call.method} failed", error)
                    if (call.method == "initialize") {
                        fail(DualCameraMessages.INITIALIZATION_FAILED)
                    } else main.post { result.error("dualCameraFailed", error.message, null) }
                }
            }
        }
    }

    private fun readConfiguration(width: Int?, height: Int?, rotation: Int?) {
        val newWidth = width ?: 720
        val newHeight = height ?: 1280
        require(newWidth in 2..1280 && newHeight in 2..1280 && newWidth % 2 == 0 && newHeight % 2 == 0)
        require(rotation == null || rotation in setOf(0, 90, 180, 270))
        frameWidth = newWidth
        frameHeight = newHeight
        frameRotation = rotation ?: 0
    }

    private fun previewInfo(): Map<String, Any> = mapOf(
        "textureId" to requireNotNull(texture).id(), "width" to frameWidth, "height" to frameHeight,
    )

    private fun findPair(): Pair<String, String>? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val combinations = manager.concurrentCameraIds
            Log.i("DualCamera", "Advertised concurrent camera combinations: $combinations")
            for (combination in combinations) {
                val rear = combination.firstOrNull { facing(it) == CameraCharacteristics.LENS_FACING_BACK }
                val front = combination.firstOrNull { facing(it) == CameraCharacteristics.LENS_FACING_FRONT }
                if (rear != null && front != null &&
                    inputSize(manager.getCameraCharacteristics(rear)) != null &&
                    inputSize(manager.getCameraCharacteristics(front)) != null) return rear to front
            }
        }
        return null
    }

    private fun facing(id: String): Int? =
        runCatching { manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) }.getOrNull()

    private fun inputSize(characteristics: CameraCharacteristics): Size? =
        characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?.getOutputSizes(SurfaceTexture::class.java)?.filter {
                it.width <= MAX_INPUT_WIDTH && it.height <= MAX_INPUT_HEIGHT
            }?.maxByOrNull { it.width.toLong() * it.height }

    @SuppressLint("MissingPermission")
    private fun initialize(result: MethodChannel.Result) {
        cancelInitialization()
        release()
        pendingInitialization = result
        val pair = findPair()
        if (pair == null) {
            fail(DualCameraMessages.UNSUPPORTED)
            return
        }
        val ids = listOf(pair.first, pair.second)
        val characteristics = ids.map(manager::getCameraCharacteristics)
        val inputSizes = characteristics.map { requireNotNull(inputSize(it)) }
        val activeGeneration = generation
        main.post {
            if (orientationListener.canDetectOrientation()) orientationListener.enable()
            val entry = textures.createSurfaceTexture()
            entry.surfaceTexture().setDefaultBufferSize(frameWidth, frameHeight)
            handler.post initializeTexture@{
                if (generation != activeGeneration) { main.post { entry.release() }; return@initializeTexture }
                try {
                    texture = entry
                    previewSurface = Surface(entry.surfaceTexture())
                    renderer = DualCameraRenderer(requireNotNull(previewSurface), inputSizes, characteristics.map {
                        it.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
                    }.toIntArray(), frameWidth, frameHeight, frameRotation) { error -> handler.post {
                        if (generation == activeGeneration) {
                            Log.e("DualCamera", "Rendering failed", error)
                            fail(DualCameraMessages.RENDER_FAILED)
                        }
                    } }
                    handler.postDelayed(initializationTimeout, INITIALIZATION_TIMEOUT_MS)
                    for ((index, id) in ids.withIndex()) {
                        manager.openCamera(id, object : CameraDevice.StateCallback() {
                            override fun onOpened(device: CameraDevice) {
                                if (generation != activeGeneration) { device.close(); return }
                                devices[index] = device
                                // Open both devices before reserving stream resources.
                                if (devices.all { it != null }) {
                                    try { configureSessions(activeGeneration) }
                                    catch (error: Exception) {
                                        Log.e("DualCamera", "Session creation failed", error)
                                        fail(DualCameraMessages.SESSION_FAILED)
                                    }
                                }
                            }
                            override fun onDisconnected(device: CameraDevice) {
                                device.close()
                                if (generation == activeGeneration) fail(DualCameraMessages.CONNECTION_LOST)
                            }
                            override fun onError(device: CameraDevice, error: Int) {
                                device.close()
                                if (generation == activeGeneration) {
                                    Log.e("DualCamera", "Camera open failed: $error")
                                    fail(DualCameraMessages.OPEN_FAILED)
                                }
                            }
                        }, handler)
                    }
                } catch (error: Exception) {
                    Log.e("DualCamera", "Initialization failed", error)
                    fail(DualCameraMessages.INITIALIZATION_FAILED)
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun configureSessions(activeGeneration: Int) {
        for (index in devices.indices) {
            val device = requireNotNull(devices[index])
            val surface = requireNotNull(renderer).inputSurface(index)
            device.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (generation != activeGeneration) { session.close(); return }
                    try {
                        sessions[index] = session
                        val request = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                            addTarget(surface)
                            set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                            val characteristics = manager.getCameraCharacteristics(device.id)
                            val modes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
                            if (modes?.contains(CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO) == true) {
                                set(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                            }
                        }
                        session.setRepeatingRequest(request.build(), object : CameraCaptureSession.CaptureCallback() {
                            override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
                                if (generation != activeGeneration || receivedFrames[index]) return
                                receivedFrames[index] = true
                                if (receivedFrames.all { it } && pendingInitialization != null) {
                                    initialized = true
                                    handler.removeCallbacks(initializationTimeout)
                                    val pending = pendingInitialization
                                    pendingInitialization = null
                                    pending?.let { success(it, mapOf(
                                        "textureId" to requireNotNull(texture).id(),
                                        "width" to frameWidth,
                                        "height" to frameHeight,
                                        "rearCameraId" to requireNotNull(devices[0]).id,
                                        "frontCameraId" to requireNotNull(devices[1]).id,
                                    )) }
                                }
                            }
                        }, handler)
                    } catch (error: Exception) {
                        Log.e("DualCamera", "Stream failed", error)
                        fail(DualCameraMessages.STREAM_FAILED)
                    }
                }
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    session.close()
                    if (generation == activeGeneration) fail(DualCameraMessages.SESSION_FAILED)
                }
            }, handler)
        }
    }

    private val receivedFrames = BooleanArray(2)

    @Suppress("DEPRECATION")
    private fun startRecording(microphoneId: String?) {
        check(initialized && recorder == null) { DualCameraMessages.NOT_READY }
        val file = File.createTempFile("DUAL_", ".mp4", context.cacheDir)
        val recording = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else MediaRecorder()
        try {
            recording.setAudioSource(MediaRecorder.AudioSource.MIC)
            recording.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            recording.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recording.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            recording.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recording.setVideoSize(frameWidth, frameHeight)
            recording.setVideoFrameRate(DualCameraRenderer.FPS)
            recording.setVideoEncodingBitRate(VIDEO_BIT_RATE)
            recording.setAudioEncodingBitRate(AUDIO_BIT_RATE)
            recording.setAudioSamplingRate(AUDIO_SAMPLE_RATE)
            recording.setOutputFile(file.absolutePath)
            recording.setOnErrorListener { _, _, _ -> handler.post { fail(DualCameraMessages.RECORDER_LOST) } }
            if (microphoneId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val device = audio.getDevices(AudioManager.GET_DEVICES_INPUTS).firstOrNull { it.id.toString() == microphoneId }
                check(device != null && recording.setPreferredDevice(device)) { DualCameraMessages.MICROPHONE_UNAVAILABLE }
            }
            recording.prepare()
            requireNotNull(renderer).attachRecorder(recording.surface)
            recording.start()
            requireNotNull(renderer).resumeRecording()
            recorder = recording
            output = file
        } catch (error: Exception) {
            renderer?.detachRecorder()
            recording.release()
            file.delete()
            throw error
        }
    }

    private fun stopRecording(): String? {
        val active = recorder ?: return null
        val file = output
        recorder = null
        output = null
        try {
            renderer?.pauseRecording()
            active.stop()
            check(file != null && file.length() > 0) { DualCameraMessages.VIDEO_FAILED }
            return file.absolutePath
        } catch (error: Exception) {
            file?.delete()
            throw error
        } finally {
            renderer?.detachRecorder()
            active.release()
        }
    }

    private fun fail(message: String) {
        val pending = pendingInitialization
        pendingInitialization = null
        release()
        main.post {
            if (pending != null) pending.error("dualCameraUnavailable", message, null)
            else eventSink?.success(mapOf("error" to message))
        }
    }

    private fun release() {
        main.post { orientationListener.disable() }
        generation++
        initialized = false
        receivedFrames.fill(false)
        handler.removeCallbacks(initializationTimeout)
        sessions.indices.forEach { index ->
            runCatching { sessions[index]?.close() }
            sessions[index] = null
            runCatching { devices[index]?.close() }
            devices[index] = null
        }
        runCatching { renderer?.pauseRecording() }
        runCatching { recorder?.stop() }
        runCatching { renderer?.detachRecorder() }
        recorder?.release()
        recorder = null
        output?.delete()
        output = null
        runCatching { renderer?.close() }
        renderer = null
        previewSurface?.release()
        previewSurface = null
        val entry = texture
        texture = null
        entry?.let { main.post { it.release() } }
    }

    fun detach() {
        closed = true
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
        handler.post { cancelInitialization(); release(); thread.quitSafely() }
    }
    private fun cancelInitialization() {
        val pending = pendingInitialization
        pendingInitialization = null
        pending?.let { main.post { it.error("dualCameraCancelled", DualCameraMessages.CANCELLED, null) } }
    }
    private fun success(result: MethodChannel.Result, value: Any?) { main.post { result.success(value) } }
}
