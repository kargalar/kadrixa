package app.kadrixa

import android.graphics.SurfaceTexture
import android.opengl.*
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import android.util.Size
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

/** Composes both live camera inputs once, for identical preview and encoded output. */
internal class DualCameraRenderer(
    previewSurface: Surface,
    private val inputSizes: List<Size>,
    private val rotations: IntArray,
    private var width: Int,
    private var height: Int,
    private var orientationRotation: Int,
    private val onFailure: (Throwable) -> Unit,
) {
    companion object {
        const val FPS = 30
        private const val INSET_FRACTION = 0.30f
        private const val INSET_MARGIN = 24
        private const val BORDER = 3
        private const val FRAME_INTERVAL_NS = 1_000_000_000L / FPS
        private const val VERTEX = """
            attribute vec2 position;
            attribute vec2 uv;
            uniform mat4 textureMatrix;
            uniform mat4 geometryMatrix;
            varying vec2 textureUv;
            void main() {
                textureUv = (textureMatrix * vec4(uv, 0.0, 1.0)).xy;
                gl_Position = geometryMatrix * vec4(position, 0.0, 1.0);
            }
        """
        private const val FRAGMENT = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            uniform samplerExternalOES cameraTexture;
            varying vec2 textureUv;
            void main() { gl_FragColor = texture2D(cameraTexture, textureUv); }
        """
    }

    private val thread = HandlerThread("DualCameraGL").apply { start() }
    private val handler = Handler(thread.looper)
    private val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    private lateinit var config: EGLConfig
    private lateinit var context: EGLContext
    private lateinit var preview: EGLSurface
    private var recording: EGLSurface? = null
    private var recordingActive = false
    private var frontIsMain = false
    private var closed = false
    private var lastFrameTime = 0L
    private var program = 0
    private val textureIds = IntArray(2)
    private val inputs = arrayOfNulls<SurfaceTexture>(2)
    private val surfaces = arrayOfNulls<Surface>(2)
    private val received = BooleanArray(2)
    private val textureMatrices = Array(2) { FloatArray(16) }
    private val vertices = ByteBuffer.allocateDirect(16 * 4).order(ByteOrder.nativeOrder())
        .asFloatBuffer().apply {
            put(floatArrayOf(-1f, -1f, 0f, 0f, 1f, -1f, 1f, 0f, -1f, 1f, 0f, 1f, 1f, 1f, 1f, 1f))
            position(0)
        }

    init {
        try { call { initialize(previewSurface) } }
        catch (error: Exception) { thread.quitSafely(); throw error }
    }

    fun inputSurface(index: Int): Surface = requireNotNull(surfaces[index])
    fun swap(frontIsMain: Boolean) = call { this.frontIsMain = frontIsMain; render() }
    fun configure(width: Int, height: Int, rotation: Int) = call {
        check(recording == null)
        this.width = width
        this.height = height
        orientationRotation = rotation
        render()
    }
    fun attachRecorder(surface: Surface) = call {
        check(recording == null)
        recording = createWindow(surface)
    }
    fun resumeRecording() = call { recordingActive = true; render() }
    fun pauseRecording() = call {
        recordingActive = false
        GLES20.glFinish()
    }
    fun detachRecorder() = call {
        recordingActive = false
        recording?.let { EGL14.eglDestroySurface(display, it) }
        recording = null
        makeCurrent(preview)
    }

    fun close() {
        if (closed) return
        try { call {
            closed = true
            recording?.let { EGL14.eglDestroySurface(display, it) }
            inputs.forEach { it?.setOnFrameAvailableListener(null); it?.release() }
            surfaces.forEach { it?.release() }
            GLES20.glDeleteTextures(2, textureIds, 0)
            GLES20.glDeleteProgram(program)
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroySurface(display, preview)
            EGL14.eglDestroyContext(display, context)
            EGL14.eglReleaseThread()
            // The default EGL display is shared with Flutter; only our own
            // contexts, surfaces and GL objects belong to this renderer.
        } } finally { thread.quitSafely() }
    }

    private fun initialize(surface: Surface) {
        check(display != EGL14.EGL_NO_DISPLAY)
        check(EGL14.eglInitialize(display, IntArray(2), 0, IntArray(2), 1))
        val configs = arrayOfNulls<EGLConfig>(1)
        val attributes = intArrayOf(
            EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGLExt.EGL_RECORDABLE_ANDROID, 1, EGL14.EGL_NONE,
        )
        check(EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, IntArray(1), 0))
        config = requireNotNull(configs[0])
        context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
        check(context != EGL14.EGL_NO_CONTEXT)
        preview = createWindow(surface)
        makeCurrent(preview)
        program = GLES20.glCreateProgram()
        val vertex = shader(GLES20.GL_VERTEX_SHADER, VERTEX)
        val fragment = shader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT)
        GLES20.glAttachShader(program, vertex)
        GLES20.glAttachShader(program, fragment)
        GLES20.glLinkProgram(program)
        val linked = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linked, 0)
        check(linked[0] != 0) { GLES20.glGetProgramInfoLog(program) }
        GLES20.glDeleteShader(vertex)
        GLES20.glDeleteShader(fragment)
        GLES20.glGenTextures(2, textureIds, 0)
        for (index in textureIds.indices) {
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureIds[index])
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            val input = SurfaceTexture(textureIds[index])
            input.setDefaultBufferSize(inputSizes[index].width, inputSizes[index].height)
            inputs[index] = input
            surfaces[index] = Surface(input)
            input.setOnFrameAvailableListener({
                if (!closed) {
                    try {
                        makeCurrent(preview)
                        input.updateTexImage()
                        input.getTransformMatrix(textureMatrices[index])
                        received[index] = true
                        val now = System.nanoTime()
                        if (received.all { it } && now - lastFrameTime >= FRAME_INTERVAL_NS) {
                            lastFrameTime = now
                            render()
                        }
                    } catch (error: Exception) { onFailure(error) }
                }
            }, handler)
        }
    }

    private fun render() {
        if (!received.all { it } || closed) return
        draw(preview, false)
        if (recordingActive) recording?.let { draw(it, true) }
    }

    private fun draw(target: EGLSurface, encoded: Boolean) {
        makeCurrent(target)
        GLES20.glDisable(GLES20.GL_SCISSOR_TEST)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        val mainIndex = if (frontIsMain) 1 else 0
        drawCamera(mainIndex, 0, 0, width, height)
        val insetWidth = (width * INSET_FRACTION).toInt()
        val insetHeight = (height * INSET_FRACTION).toInt()
        val left = width - insetWidth - INSET_MARGIN
        val bottom = height - insetHeight - INSET_MARGIN
        GLES20.glEnable(GLES20.GL_SCISSOR_TEST)
        GLES20.glScissor(left - BORDER, bottom - BORDER, insetWidth + BORDER * 2, insetHeight + BORDER * 2)
        GLES20.glClearColor(1f, 1f, 1f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glDisable(GLES20.GL_SCISSOR_TEST)
        drawCamera(1 - mainIndex, left, bottom, insetWidth, insetHeight)
        if (encoded) EGLExt.eglPresentationTimeANDROID(display, target, System.nanoTime())
        check(EGL14.eglSwapBuffers(display, target)) { DualCameraMessages.FRAME_FAILED }
    }

    private fun drawCamera(index: Int, x: Int, y: Int, width: Int, height: Int) {
        GLES20.glViewport(x, y, width, height)
        GLES20.glEnable(GLES20.GL_SCISSOR_TEST)
        GLES20.glScissor(x, y, width, height)
        GLES20.glUseProgram(program)
        val position = GLES20.glGetAttribLocation(program, "position")
        val uv = GLES20.glGetAttribLocation(program, "uv")
        vertices.position(0)
        GLES20.glVertexAttribPointer(position, 2, GLES20.GL_FLOAT, false, 16, vertices)
        vertices.position(2)
        GLES20.glVertexAttribPointer(uv, 2, GLES20.GL_FLOAT, false, 16, vertices)
        GLES20.glEnableVertexAttribArray(position)
        GLES20.glEnableVertexAttribArray(uv)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureIds[index])
        GLES20.glUniform1i(GLES20.glGetUniformLocation(program, "cameraTexture"), 0)
        GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(program, "textureMatrix"), 1, false, textureMatrices[index], 0)
        val geometry = FloatArray(16)
        Matrix.setIdentityM(geometry, 0)
        val rotated = (rotations[index] + orientationRotation) % 180 != 0
        val size = inputSizes[index]
        val sourceAspect = if (rotated) size.height.toFloat() / size.width else size.width.toFloat() / size.height
        val targetAspect = width.toFloat() / height
        val scaleX = maxOf(1f, sourceAspect / targetAspect)
        val scaleY = maxOf(1f, targetAspect / sourceAspect)
        // Camera2 includes sensor rotation and front-camera mirroring in the
        // SurfaceTexture producer transform. Do not apply them a second time.
        Matrix.scaleM(geometry, 0, scaleX, scaleY, 1f)
        Matrix.rotateM(geometry, 0, orientationRotation.toFloat(), 0f, 0f, 1f)
        GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(program, "geometryMatrix"), 1, false, geometry, 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisable(GLES20.GL_SCISSOR_TEST)
    }

    private fun createWindow(surface: Surface): EGLSurface =
        EGL14.eglCreateWindowSurface(display, config, surface, intArrayOf(EGL14.EGL_NONE), 0).also {
            check(it != EGL14.EGL_NO_SURFACE)
        }
    private fun makeCurrent(surface: EGLSurface) {
        check(EGL14.eglMakeCurrent(display, surface, surface, context))
    }
    private fun shader(type: Int, source: String): Int = GLES20.glCreateShader(type).also {
        GLES20.glShaderSource(it, source)
        GLES20.glCompileShader(it)
        val compiled = IntArray(1)
        GLES20.glGetShaderiv(it, GLES20.GL_COMPILE_STATUS, compiled, 0)
        check(compiled[0] != 0) { GLES20.glGetShaderInfoLog(it) }
    }
    private fun <T> call(action: () -> T): T {
        val task = FutureTask(action)
        check(handler.post(task)) { "The image processor is closed." }
        return task.get(5, TimeUnit.SECONDS)
    }
}
