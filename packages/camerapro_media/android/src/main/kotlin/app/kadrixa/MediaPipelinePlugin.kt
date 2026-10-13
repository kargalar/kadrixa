package app.kadrixa

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class MediaPipelinePlugin : FlutterPlugin {
    private lateinit var context: Context
    private lateinit var mediaChannel: MethodChannel
    private lateinit var photoChannel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private var executor = Executors.newSingleThreadExecutor()
    private val lockTokens = ConcurrentHashMap.newKeySet<String>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        if (executor.isShutdown) executor = Executors.newSingleThreadExecutor()
        mediaChannel = MethodChannel(binding.binaryMessenger, "app.kadrixa/media_pipeline")
        photoChannel = MethodChannel(binding.binaryMessenger, "app.kadrixa/photo_processing")
        mediaChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "tryAcquireJobLock" -> {
                        val file = privateFile(requireNotNull(call.argument<String>("path")))
                        val token = ProcessingLocks.tryAcquire(file)
                        if (token != null) lockTokens.add(token)
                        result.success(token)
                    }
                    "releaseJobLock" -> {
                        val token = requireNotNull(call.argument<String>("token"))
                        if (lockTokens.remove(token)) ProcessingLocks.release(token)
                        result.success(null)
                    }
                    "inspectVideo" -> execute(result) {
                        val file = privateFile(requireNotNull(call.argument<String>("path")))
                        RecordedVideoMetadata.read(file)
                    }
                    "saveVideoToGallery", "saveImageToGallery" -> execute(result) {
                        val file = privateFile(requireNotNull(call.argument<String>("path")))
                        NativeGalleryStore(context).save(file, call.method == "saveVideoToGallery").toString()
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("MEDIA_PIPELINE_FAILED", error.message, null)
            }
        }
        photoChannel.setMethodCallHandler { call, result ->
            if (call.method != "processAndSavePhoto") {
                result.notImplemented()
            } else {
                execute(result) { processPhoto(call) }
            }
        }
    }

    private fun processPhoto(call: MethodCall): Map<String, Any?> {
        val source = privateFile(requireNotNull(call.argument<String>("sourcePath")))
        val ratio = requireNotNull(call.argument<Double>("targetAspectRatio"))
        require(ratio.isFinite() && ratio > 0) { "Aspect ratio must be finite and positive" }
        return NativePhotoProcessor(context).process(
            sourcePath = source.absolutePath,
            targetAspectRatio = ratio,
            jpegQuality = call.argument<Int>("jpegQuality") ?: 95,
            saveToGallery = call.argument<Boolean>("saveToGallery") ?: true,
            mirrorHorizontally = call.argument<Boolean>("mirrorHorizontally") ?: false,
            latitude = call.argument<Double>("latitude"),
            longitude = call.argument<Double>("longitude"),
            altitude = call.argument<Double>("altitude"),
        )
    }

    private fun privateFile(path: String): File {
        val file = File(path).canonicalFile
        val root = context.dataDir.canonicalPath + File.separator
        require(file.path.startsWith(root)) { "Media path must be inside the app data directory" }
        return file
    }

    private fun execute(result: MethodChannel.Result, work: () -> Any?) {
        executor.execute {
            try {
                val output = work()
                mainHandler.post { result.success(output) }
            } catch (error: Exception) {
                mainHandler.post { result.error("MEDIA_PROCESSING_FAILED", error.message, null) }
            } catch (error: OutOfMemoryError) {
                mainHandler.post { result.error("MEDIA_MEMORY_EXHAUSTED", "Insufficient memory to process this photo", null) }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        mediaChannel.setMethodCallHandler(null)
        photoChannel.setMethodCallHandler(null)
        // Finish an in-flight native copy before releasing its job lock.
        executor.execute {
            lockTokens.toList().forEach(ProcessingLocks::release)
            lockTokens.clear()
        }
        executor.shutdown()
    }
}
