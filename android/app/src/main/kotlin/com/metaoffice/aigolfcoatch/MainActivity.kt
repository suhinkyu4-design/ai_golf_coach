package com.metaoffice.aigolfcoatch

import android.graphics.Bitmap
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
                val sampleCount = call.argument<Int>("sampleCount") ?: 25

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

        val framesDir = File(cacheDir, "gallery_frames")
        if (!framesDir.exists()) framesDir.mkdirs()

        val framesList = mutableListOf<Map<String, Any>>()
        val intervalMs = durationMs / sampleCount.coerceAtLeast(1)

        for (i in 0 until sampleCount) {
            val tMs = (i * intervalMs).toInt()
            val timeUs = tMs * 1000L

            val bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: continue
            val frameFile = File(framesDir, "frame_${i}_${tMs}.jpg")

            try {
                FileOutputStream(frameFile).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                }

                val frameMap = mapOf<String, Any>(
                    "t_ms" to tMs,
                    "path" to frameFile.absolutePath,
                    "width" to bitmap.width,
                    "height" to bitmap.height
                )
                framesList.add(frameMap)
            } catch (_: Exception) {
                // Ignore single frame write failure
            }
        }

        try { retriever.release() } catch (_: Exception) {}
        return framesList
    }
}
