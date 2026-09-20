package com.metaoffice.aigolfcoatch

import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.metaoffice.aigolfcoatch/frame_extractor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "extractFrames") {
                val videoPath = call.argument<String>("videoPath")
                val sampleCount = call.argument<Int>("sampleCount") ?: 45

                if (videoPath.isNullOrEmpty() || !File(videoPath).exists()) {
                    result.error("INVALID_PATH", "Video file not found", null)
                    return@setMethodCallHandler
                }

                thread {
                    try {
                        val frames = extractFramesNative(videoPath, sampleCount)
                        runOnUiThread {
                            result.success(frames)
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("FRAME_ERROR", e.localizedMessage, null)
                        }
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun extractFramesNative(videoPath: String, sampleCount: Int): List<Map<String, Any>> {
        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(videoPath)

        val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
        val durationMs = durationStr?.toLongOrNull() ?: 0L
        if (durationMs <= 0) {
            try { retriever.release() } catch (_: Exception) {}
            return emptyList()
        }

        // Get video rotation metadata (e.g. 90, 180, 270 degrees for portrait videos)
        val rotationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
        val rotation = rotationStr?.toIntOrNull() ?: 0

        val framesDir = File(cacheDir, "gallery_frames")
        if (!framesDir.exists()) framesDir.mkdirs()

        val framesList = mutableListOf<Map<String, Any>>()
        val frameCount = sampleCount.coerceAtLeast(2)
        val intervalMs = durationMs.toDouble() / (frameCount - 1).toDouble()

        for (i in 0 until frameCount) {
            val tMs = (i * intervalMs).toLong().coerceIn(0L, durationMs).toInt()
            val timeUs = tMs * 1000L

            val rawBitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST) ?: continue

            val finalBitmap = if (rotation != 0) {
                val matrix = Matrix()
                matrix.postRotate(rotation.toFloat())
                val rotated = Bitmap.createBitmap(rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true)
                if (rotated != rawBitmap) {
                    rawBitmap.recycle()
                }
                rotated
            } else {
                rawBitmap
            }

            val frameFile = File(framesDir, "frame_${i}_${tMs}.jpg")

            try {
                FileOutputStream(frameFile).use { out ->
                    finalBitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                }

                val frameMap = mapOf<String, Any>(
                    "t_ms" to tMs,
                    "path" to frameFile.absolutePath,
                    "width" to finalBitmap.width,
                    "height" to finalBitmap.height
                )
                framesList.add(frameMap)
            } catch (_: Exception) {
                // Ignore single frame write failure
            } finally {
                finalBitmap.recycle()
            }
        }

        try { retriever.release() } catch (_: Exception) {}
        return framesList
    }
}
