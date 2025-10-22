package com.zarq.messenger

import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.view.Surface

/**
 * Holds state associated with a Surface used for MediaCodec encoder input.
 *
 * The constructor takes a Surface obtained from MediaCodec.createInputSurface(), and uses that
 * to create an EGL window surface. Calls to eglSwapBuffers() cause a frame of data to be sent
 * to the video encoder.
 *
 * Based on Google's Grafika project and Android CTS tests.
 */
class InputSurface(private val surface: Surface) {
    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private lateinit var textureRender: TextureRender

    init {
        eglSetup()
        // Make context current before creating TextureRender (GL needs active context)
        makeCurrent()
        // Create TextureRender in this context for drawing
        textureRender = TextureRender()
        textureRender.surfaceCreated()
    }

    /**
     * Prepares EGL display and context.
     * Based on Grafika's EglCore.
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

        // Configure EGL for OpenGL ES 2.0 and recordable output
        val attribList = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGLExt.EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_NONE
        )

        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        if (!EGL14.eglChooseConfig(eglDisplay, attribList, 0, configs, 0, configs.size, numConfigs, 0)) {
            throw RuntimeException("unable to find RGB888+recordable ES2 EGL config")
        }

        // Configure EGL context for OpenGL ES 2.0
        val contextAttribs = intArrayOf(
            EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL14.EGL_NONE
        )

        eglContext = EGL14.eglCreateContext(
            eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, contextAttribs, 0
        )
        checkEglError("eglCreateContext")
        if (eglContext == EGL14.EGL_NO_CONTEXT) {
            throw RuntimeException("null context")
        }

        // Create a window surface
        val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
        eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, configs[0], surface, surfaceAttribs, 0)
        checkEglError("eglCreateWindowSurface")
        if (eglSurface == EGL14.EGL_NO_SURFACE) {
            throw RuntimeException("surface was null")
        }
    }

    /**
     * Returns the EGL context for sharing with other surfaces.
     */
    fun getEglContext(): EGLContext {
        return eglContext
    }

    /**
     * Returns the EGL display
     */
    fun getEglDisplay(): EGLDisplay {
        return eglDisplay
    }

    /**
     * Returns the EGL surface (encoder's input surface)
     */
    fun getEglSurface(): EGLSurface {
        return eglSurface
    }

    /**
     * Makes our EGL context current, using the supplied surface for both "draw" and "read".
     */
    fun makeCurrent() {
        if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
            throw RuntimeException("eglMakeCurrent failed")
        }
    }

    /**
     * Calls eglSwapBuffers. Use this to "publish" the current frame.
     */
    fun swapBuffers(): Boolean {
        return EGL14.eglSwapBuffers(eglDisplay, eglSurface)
    }

    /**
     * Sends the presentation time stamp to EGL. Time is expressed in nanoseconds.
     */
    fun setPresentationTime(nsecs: Long) {
        EGLExt.eglPresentationTimeANDROID(eglDisplay, eglSurface, nsecs)
    }

    /**
     * Draws a frame from OutputSurface to the encoder's input surface
     */
    fun drawFrame(outputSurface: OutputSurface, width: Int, height: Int) {
        makeCurrent()
        // Use OutputSurface's texture ID (shared between contexts)
        textureRender.drawFrame(
            outputSurface.getSurfaceTexture(),
            width,
            height,
            outputSurface.getTextureId()
        )
    }

    /**
     * Discards all resources held by this class, notably the EGL context.
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
