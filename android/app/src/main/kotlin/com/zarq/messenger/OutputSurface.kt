package com.zarq.messenger

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.view.Surface

/**
 * Holds state associated with a Surface used for MediaCodec decoder output.
 *
 * The constructor for this class will prepare GL, create a SurfaceTexture,
 * and then create a Surface for that SurfaceTexture. The Surface can be passed to
 * MediaCodec.configure() to receive decoder output. When a frame arrives, we latch the
 * texture with updateTexImage, then render the texture with GL to a pbuffer.
 *
 * The texture is subsequently rendered onto a Surface. A fence is used to ensure that
 * the second render happens after the first.
 *
 * Based on Google's Grafika project.
 */
class OutputSurface(sharedContext: EGLContext = EGL14.EGL_NO_CONTEXT, private val targetWidth: Int = 0, private val targetHeight: Int = 0) : SurfaceTexture.OnFrameAvailableListener {
    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private val sharedEglContext: EGLContext = sharedContext

    private lateinit var surfaceTexture: SurfaceTexture
    private lateinit var surface: Surface
    private lateinit var textureRender: TextureRender

    private val frameSyncObject = Object() // guards frameAvailable
    private var frameAvailable = false

    /**
     * Creates an OutputSurface backed by a pbuffer with the specified dimensions.
     * The new EGL context and surface will be made current.
     */
    init {
        setup()
    }

    /**
     * Creates interconnected instances of TextureRender, SurfaceTexture, and Surface.
     */
    private fun setup() {
        // MUST setup EGL context FIRST before creating TextureRender
        eglSetup()

        // Now create TextureRender (requires EGL context)
        textureRender = TextureRender()
        textureRender.surfaceCreated()

        // Create a Surface from the SurfaceTexture
        surfaceTexture = SurfaceTexture(textureRender.textureId)
        surfaceTexture.setOnFrameAvailableListener(this)
        surface = Surface(surfaceTexture)
    }

    /**
     * Prepares EGL display and context.
     */
    private fun eglSetup() {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) {
            throw RuntimeException("unable to get EGL14 display")
        }

        val version = IntArray(2)
        if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
            eglDisplay = EGL14.EGL_NO_DISPLAY
            throw RuntimeException("unable to initialize EGL14")
        }

        // Configure EGL for pbuffer and OpenGL ES 2.0
        val attribList = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_NONE
        )

        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        if (!EGL14.eglChooseConfig(eglDisplay, attribList, 0, configs, 0, configs.size, numConfigs, 0)) {
            throw RuntimeException("unable to find RGB888+pbuffer EGL config")
        }

        // Configure context for OpenGL ES 2.0
        val contextAttribs = intArrayOf(
            EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL14.EGL_NONE
        )

        // Create context, sharing with provided context if available
        eglContext = EGL14.eglCreateContext(
            eglDisplay, configs[0], sharedEglContext, contextAttribs, 0
        )
        checkEglError("eglCreateContext")
        if (eglContext == EGL14.EGL_NO_CONTEXT) {
            throw RuntimeException("null context")
        }

        // Create a pbuffer surface
        val surfaceAttribs = intArrayOf(
            EGL14.EGL_WIDTH, 1,
            EGL14.EGL_HEIGHT, 1,
            EGL14.EGL_NONE
        )
        eglSurface = EGL14.eglCreatePbufferSurface(eglDisplay, configs[0], surfaceAttribs, 0)
        checkEglError("eglCreatePbufferSurface")
        if (eglSurface == EGL14.EGL_NO_SURFACE) {
            throw RuntimeException("surface was null")
        }

        // Make our context current
        if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
            throw RuntimeException("eglMakeCurrent failed")
        }
    }

    /**
     * Discard all resources held by this class, notably the EGL context.
     */
    fun release() {
        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglDestroySurface(eglDisplay, eglSurface)
            EGL14.eglDestroyContext(eglDisplay, eglContext)
            EGL14.eglReleaseThread()
            EGL14.eglTerminate(eglDisplay)
        }
        eglDisplay = EGL14.EGL_NO_DISPLAY
        eglContext = EGL14.EGL_NO_CONTEXT
        eglSurface = EGL14.EGL_NO_SURFACE

        surface.release()
        surfaceTexture.release()
    }

    /**
     * Returns the Surface that we draw onto.
     */
    fun getSurface(): Surface {
        return surface
    }

    /**
     * Returns the texture ID for use in shared contexts
     */
    fun getTextureId(): Int {
        return textureRender.textureId
    }

    /**
     * Returns the SurfaceTexture for transform matrix
     */
    fun getSurfaceTexture(): SurfaceTexture {
        return surfaceTexture
    }

    /**
     * Latches the next buffer into the texture. Must be called from the thread that created
     * the OutputSurface object, after the onFrameAvailable callback has signaled that new
     * data is available.
     */
    fun awaitNewImage() {
        val TIMEOUT_MS = 2500

        synchronized(frameSyncObject) {
            while (!frameAvailable) {
                try {
                    // Wait for onFrameAvailable() to signal us. Use a timeout to avoid
                    // stalling the test if it doesn't arrive.
                    frameSyncObject.wait(TIMEOUT_MS.toLong())
                    if (!frameAvailable) {
                        // timeout
                        throw RuntimeException("Surface frame wait timed out")
                    }
                } catch (ie: InterruptedException) {
                    // shouldn't happen
                    throw RuntimeException(ie)
                }
            }
            frameAvailable = false
        }

        // Latch the data - THIS MUST BE CALLED BEFORE drawImage()
        // CRITICAL: Make OutputSurface current before updateTexImage
        makeCurrent()
        textureRender.checkGlError("before updateTexImage")
        surfaceTexture.updateTexImage()
    }

    /**
     * Draws the data from SurfaceTexture onto the current EGL surface.
     * IMPORTANT: Must make OutputSurface's EGL context current before calling!
     */
    fun drawImage() {
        textureRender.drawFrame(surfaceTexture, targetWidth, targetHeight)
    }

    /**
     * Draws the texture to a specific EGL surface (for encoder input)
     */
    fun drawImageToSurface(eglDisplay: android.opengl.EGLDisplay, eglSurface: android.opengl.EGLSurface) {
        // Ensure texture update is complete before switching surfaces
        android.opengl.GLES20.glFinish()

        // Make the encoder's surface current in THIS context (where texture lives)
        if (!android.opengl.EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
            throw RuntimeException("eglMakeCurrent to encoder surface failed")
        }

        // Draw using our TextureRender (in our context, to encoder's surface)
        textureRender.drawFrame(surfaceTexture, targetWidth, targetHeight)

        // Ensure drawing is complete
        android.opengl.GLES20.glFinish()
    }

    /**
     * Makes this surface's EGL context current
     */
    fun makeCurrent() {
        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
                throw RuntimeException("eglMakeCurrent failed")
            }
        }
    }

    override fun onFrameAvailable(st: SurfaceTexture) {
        synchronized(frameSyncObject) {
            if (frameAvailable) {
                throw RuntimeException("frameAvailable already set, frame could be dropped")
            }
            frameAvailable = true
            frameSyncObject.notifyAll()
        }
    }

    /**
     * Checks for EGL errors.
     */
    private fun checkEglError(msg: String) {
        val error = EGL14.eglGetError()
        if (error != EGL14.EGL_SUCCESS) {
            throw RuntimeException("$msg: EGL error: 0x${Integer.toHexString(error)}")
        }
    }
}
