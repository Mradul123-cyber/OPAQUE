package com.zarq.messenger

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import kotlin.math.min

/**
 * WhatsApp/Telegram-style Video Compression using Surface-to-Surface MediaCodec
 * - Uses OpenGL EGL for zero-copy frame transfer
 * - Handles video resizing via GPU (1920x1080 → 720p)
 * - Production-grade reliability
 */
class VideoCompressionHelper(private val context: Context) {

    companion object {
        private const val TAG = "VideoCompression"
        private const val TIMEOUT_USEC = 10000L
        private const val MIME_TYPE = "video/avc" // H.264
        private const val FRAME_RATE = 30
        private const val I_FRAME_INTERVAL = 2
    }

    enum class Quality(val bitrate: Int, val maxDimension: Int) {
        LOW(500_000, 480),
        MEDIUM(1_000_000, 720),
        HIGH(2_000_000, 1080)
    }

    /**
     * Compress video using Surface-to-Surface transcoding (WhatsApp/Telegram approach)
     */
    fun compressVideo(
        inputPath: String,
        outputPath: String,
        quality: Quality = Quality.MEDIUM,
        progressCallback: ((Int) -> Unit)? = null
    ): Boolean {
        var extractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var inputSurface: InputSurface? = null
        var outputSurface: OutputSurface? = null

        return try {
            Log.d(TAG, "🎬 Starting Surface-to-Surface video compression: $inputPath")

            // Get video metadata
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(inputPath)
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            retriever.release()

            Log.d(TAG, "Original: ${width}x${height}, Duration: ${durationMs}ms, Rotation: $rotation")

            // Calculate target dimensions
            val (targetWidth, targetHeight) = calculateTargetDimensions(width, height, quality.maxDimension)
            Log.d(TAG, "Target: ${targetWidth}x${targetHeight}, Bitrate: ${quality.bitrate}")

            // Setup extractor
            extractor = MediaExtractor()
            extractor.setDataSource(inputPath)

            // Find video track
            var videoTrackIndex = -1
            var videoFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) {
                    videoTrackIndex = i
                    videoFormat = format
                    break
                }
            }

            if (videoTrackIndex == -1 || videoFormat == null) {
                Log.e(TAG, "No video track found")
                return false
            }

            extractor.selectTrack(videoTrackIndex)

            // Create encoder first
            val encoderFormat = MediaFormat.createVideoFormat(MIME_TYPE, targetWidth, targetHeight)
            encoderFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            encoderFormat.setInteger(MediaFormat.KEY_BIT_RATE, quality.bitrate)
            encoderFormat.setInteger(MediaFormat.KEY_FRAME_RATE, FRAME_RATE)
            encoderFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL)

            // Set standard BT.709 color metadata to fix green screen issue
            // BT.709 is the standard for HD video (720p/1080p)
            encoderFormat.setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
            encoderFormat.setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
            encoderFormat.setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
            Log.d(TAG, "Set color metadata: BT.709, Limited Range, SDR")

            encoder = MediaCodec.createEncoderByType(MIME_TYPE)
            encoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)

            // Setup input surface (encoder input) - creates EGL context
            inputSurface = InputSurface(encoder.createInputSurface())
            encoder.start()

            // Setup output surface (decoder output) - shares EGL context with InputSurface
            // Pass target dimensions for proper viewport setting
            outputSurface = OutputSurface(inputSurface.getEglContext(), targetWidth, targetHeight)

            // Create decoder
            val decoderMime = videoFormat.getString(MediaFormat.KEY_MIME) ?: MIME_TYPE
            decoder = MediaCodec.createDecoderByType(decoderMime)
            decoder.configure(videoFormat, outputSurface.getSurface(), null, 0)
            decoder.start()

            // Create muxer
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            if (rotation != 0) {
                muxer.setOrientationHint(rotation)
            }

            // Transcode video using surfaces
            val success = transcodeSurfaceToSurface(
                extractor = extractor,
                decoder = decoder,
                encoder = encoder,
                inputSurface = inputSurface,
                outputSurface = outputSurface,
                muxer = muxer,
                durationMs = durationMs,
                targetWidth = targetWidth,
                targetHeight = targetHeight,
                progressCallback = progressCallback
            )

            if (success) {
                val originalSize = File(inputPath).length() / 1024
                val compressedSize = File(outputPath).length() / 1024
                val compressionRatio = if (originalSize > 0) {
                    ((originalSize - compressedSize).toFloat() / originalSize * 100).toInt()
                } else {
                    0
                }
                Log.d(TAG, "📦 Original: ${originalSize}KB → Compressed: ${compressedSize}KB (${compressionRatio}% reduction)")
            }

            success

        } catch (e: Exception) {
            Log.e(TAG, "❌ Compression failed: ${e.message}", e)
            e.printStackTrace()
            false
        } finally {
            // Cleanup
            try {
                decoder?.stop()
                decoder?.release()
            } catch (e: Exception) {
                Log.w(TAG, "Error releasing decoder: ${e.message}")
            }
            try {
                encoder?.stop()
                encoder?.release()
            } catch (e: Exception) {
                Log.w(TAG, "Error releasing encoder: ${e.message}")
            }
            try {
                muxer?.stop()
                muxer?.release()
            } catch (e: Exception) {
                Log.w(TAG, "Error releasing muxer: ${e.message}")
            }
            inputSurface?.release()
            outputSurface?.release()
            extractor?.release()
        }
    }

    /**
     * Surface-to-Surface transcoding with OpenGL (WhatsApp/Telegram method)
     */
    private fun transcodeSurfaceToSurface(
        extractor: MediaExtractor,
        decoder: MediaCodec,
        encoder: MediaCodec,
        inputSurface: InputSurface,
        outputSurface: OutputSurface,
        muxer: MediaMuxer,
        durationMs: Long,
        targetWidth: Int,
        targetHeight: Int,
        progressCallback: ((Int) -> Unit)?
    ): Boolean {
        val decoderBufferInfo = MediaCodec.BufferInfo()
        val encoderBufferInfo = MediaCodec.BufferInfo()

        var muxerStarted = false
        var videoTrackIndex = -1

        var extractorDone = false
        var decoderDone = false
        var encoderDone = false

        val durationUs = durationMs * 1000
        var lastProgressPercent = -1

        Log.d(TAG, "Starting Surface-to-Surface transcoding loop")

        while (!encoderDone) {
            // 1. Feed extractor data to decoder
            if (!extractorDone) {
                val decoderInputIndex = decoder.dequeueInputBuffer(TIMEOUT_USEC)
                if (decoderInputIndex >= 0) {
                    val decoderInputBuffer = decoder.getInputBuffer(decoderInputIndex)!!
                    val sampleSize = extractor.readSampleData(decoderInputBuffer, 0)

                    if (sampleSize < 0) {
                        Log.d(TAG, "📥 Extractor done, sending EOS to decoder")
                        decoder.queueInputBuffer(decoderInputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        extractorDone = true
                    } else {
                        val presentationTime = extractor.sampleTime
                        decoder.queueInputBuffer(decoderInputIndex, 0, sampleSize, presentationTime, 0)
                        extractor.advance()
                    }
                }
            }

            // 2. Get decoded frame from decoder and render to encoder via surfaces
            if (!decoderDone) {
                val decoderOutputIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, TIMEOUT_USEC)

                when {
                    decoderOutputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        // No output available yet
                    }
                    decoderOutputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        Log.d(TAG, "Decoder output format changed: ${decoder.outputFormat}")
                    }
                    decoderOutputIndex >= 0 -> {
                        val doRender = decoderBufferInfo.size != 0

                        // Release decoder buffer with render=true to send frame to Surface
                        decoder.releaseOutputBuffer(decoderOutputIndex, doRender)

                        if (doRender) {
                            // 1. Wait for new frame and update texture (in OutputSurface's context)
                            outputSurface.awaitNewImage()

                            // 2. Draw in OutputSurface's context, but TO encoder's surface
                            // This is the key fix: texture must be drawn in the context where it was created
                            outputSurface.drawImageToSurface(
                                inputSurface.getEglDisplay(),
                                inputSurface.getEglSurface()
                            )

                            // 3. Send frame to encoder
                            inputSurface.setPresentationTime(decoderBufferInfo.presentationTimeUs * 1000)
                            inputSurface.swapBuffers()

                            // Update progress
                            if (durationUs > 0 && decoderBufferInfo.presentationTimeUs > 0) {
                                val progressPercent = min(99, (decoderBufferInfo.presentationTimeUs * 100 / durationUs).toInt())
                                if (progressPercent != lastProgressPercent) {
                                    lastProgressPercent = progressPercent
                                    progressCallback?.invoke(progressPercent)
                                }
                            }
                        }

                        // Check for decoder EOS
                        if ((decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            Log.d(TAG, "✅ Decoder finished, signaling encoder EOS")
                            encoder.signalEndOfInputStream()
                            decoderDone = true
                        }
                    }
                }
            }

            // 3. Get encoded data from encoder
            val encoderOutputIndex = encoder.dequeueOutputBuffer(encoderBufferInfo, TIMEOUT_USEC)

            when {
                encoderOutputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    // No output available yet
                }
                encoderOutputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (muxerStarted) {
                        Log.e(TAG, "⚠️ Encoder format changed after muxer started")
                    } else {
                        val newFormat = encoder.outputFormat
                        videoTrackIndex = muxer.addTrack(newFormat)
                        muxer.start()
                        muxerStarted = true
                        Log.d(TAG, "🎬 Muxer started with format: $newFormat")
                    }
                }
                encoderOutputIndex >= 0 -> {
                    val encoderOutputBuffer = encoder.getOutputBuffer(encoderOutputIndex)!!

                    if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                        Log.d(TAG, "Ignoring codec config buffer")
                        encoderBufferInfo.size = 0
                    }

                    if (encoderBufferInfo.size > 0 && muxerStarted) {
                        encoderOutputBuffer.position(encoderBufferInfo.offset)
                        encoderOutputBuffer.limit(encoderBufferInfo.offset + encoderBufferInfo.size)
                        muxer.writeSampleData(videoTrackIndex, encoderOutputBuffer, encoderBufferInfo)
                    }

                    encoder.releaseOutputBuffer(encoderOutputIndex, false)

                    // Check for encoder EOS
                    if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        Log.d(TAG, "✅ Encoder finished")
                        encoderDone = true
                        progressCallback?.invoke(100)
                    }
                }
            }
        }

        Log.d(TAG, "✅ Video compression completed successfully")
        return true
    }

    /**
     * Calculate target dimensions while maintaining aspect ratio
     */
    private fun calculateTargetDimensions(width: Int, height: Int, maxDimension: Int): Pair<Int, Int> {
        if (width <= maxDimension && height <= maxDimension) {
            return Pair(align2(width), align2(height))
        }

        val aspectRatio = width.toFloat() / height.toFloat()
        val targetWidth: Int
        val targetHeight: Int

        if (width > height) {
            targetWidth = maxDimension
            targetHeight = (maxDimension / aspectRatio).toInt()
        } else {
            targetHeight = maxDimension
            targetWidth = (maxDimension * aspectRatio).toInt()
        }

        return Pair(align2(targetWidth), align2(targetHeight))
    }

    /**
     * Align to even number (required by most codecs)
     */
    private fun align2(value: Int): Int {
        return (value + 1) / 2 * 2
    }

    /**
     * Get video metadata
     */
    fun getVideoMetadata(videoPath: String): Map<String, Any>? {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(videoPath)

            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val fileSize = File(videoPath).length()

            retriever.release()

            mapOf(
                "duration" to duration.toInt(),
                "width" to width,
                "height" to height,
                "filesize" to fileSize
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error getting video metadata: ${e.message}")
            null
        }
    }
}
