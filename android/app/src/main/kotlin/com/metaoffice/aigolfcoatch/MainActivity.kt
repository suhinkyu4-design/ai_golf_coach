package com.metaoffice.aigolfcoatch

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.graphics.Matrix
import org.json.JSONObject
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

    private var slmChannel: GolfSlmChannel? = null
    private var assistantSlmChannel: GolfSlmChannel? = null
    private var voiceCapture: VoiceCaptureChannel? = null

    override fun onDestroy() {
        voiceCapture?.close()
        slmChannel?.close()
        assistantSlmChannel?.close()
        super.onDestroy()
    }

    private var pendingSave: Pair<String, MethodChannel.Result>? = null
    private var pendingExport: Pair<String, MethodChannel.Result>? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 702) return
        val pending = pendingExport ?: return
        pendingExport = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.second.success(false)
            return
        }
        thread {
            try {
                contentResolver.openOutputStream(uri, "wt")?.use {
                    it.write(pending.first.toByteArray(Charsets.UTF_8))
                } ?: error("내보내기 파일을 열 수 없습니다.")
                runOnUiThread { pending.second.success(true) }
            } catch (e: Exception) {
                runOnUiThread { pending.second.error("EXPORT_FAILED", e.localizedMessage, null) }
            }
        }
    }

    private fun saveRecording(path: String, result: MethodChannel.Result) {
        thread {
            try { val saved = saveRecordingNative(path)
                runOnUiThread { result.success(saved) }
            } catch (e: Exception) {
                runOnUiThread { result.error("GALLERY_SAVE_FAILED", e.localizedMessage, null) }
            }
        }
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code == 703) voiceCapture?.permission(grants)
        if (code == 701) {
            val pending = pendingSave ?: return
            pendingSave = null
            if (grants.isNotEmpty() && grants[0] == PackageManager.PERMISSION_GRANTED) {
                saveRecording(pending.first, pending.second)
            } else pending.second.error("STORAGE_PERMISSION", "갤러리에 저장하려면 저장소 권한이 필요합니다.", null)
        }
    }

    private fun saveRecordingNative(path: String): Map<String, String> {
        val source = File(path)
        require(source.isFile && source.length() > 0) { "촬영 영상이 없습니다." }
        val name = "Golf_${System.currentTimeMillis()}_${System.nanoTime()}.mp4"
        val directory = File(filesDir, "recordings").apply { mkdirs() }
        val analysisFile = File(directory, name)
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= 29) {
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/GolfCoach")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            } else {
                val publicDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "GolfCoach")
                check(publicDir.exists() || publicDir.mkdirs())
                put(MediaStore.Video.Media.DATA, File(publicDir, name).absolutePath)
            }
        }
        val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: error("갤러리 항목 생성 실패")
        try {
            contentResolver.openOutputStream(uri)?.use { output -> source.inputStream().use { it.copyTo(output) } }
                ?: error("갤러리 쓰기 실패")
            // Read the stored gallery video back for the shared file-based analyzer.
            contentResolver.openInputStream(uri)?.use { input -> analysisFile.outputStream().use { input.copyTo(it) } }
                ?: error("저장 영상 읽기 실패")
            check(analysisFile.length() == source.length()) { "저장 영상 크기 불일치" }
            if (Build.VERSION.SDK_INT >= 29) {
                check(contentResolver.update(uri, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null) == 1)
            }
            return mapOf("path" to analysisFile.absolutePath, "uri" to uri.toString(), "name" to name)
        } catch (e: Exception) {
            analysisFile.delete()
            contentResolver.delete(uri, null, null)
            throw e
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voiceCapture = VoiceCaptureChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        slmChannel = GolfSlmChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        assistantSlmChannel = GolfSlmChannel(this, flutterEngine.dartExecutor.binaryMessenger,
            "com.metaoffice.aigolfcoatch/assistant_slm", "golf_assistant_v1_q8_0.gguf",
            639446752L, "0d64feb2fe193da37efd64aeade25726e5b289e907ab1922920258325f199452")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "exportDataset") {
                val json = call.argument<String>("json")
                if (json == null) { result.error("INVALID_DATA", "데이터가 없습니다.", null); return@setMethodCallHandler }
                if (pendingExport != null) { result.error("BUSY", "내보내기 진행 중", null); return@setMethodCallHandler }
                pendingExport = Pair(json, result)
                try {
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, "golf_review_${System.currentTimeMillis()}.json")
                    }, 702)
                } catch (e: Exception) {
                    pendingExport = null
                    result.error("EXPORT_FAILED", e.localizedMessage, null)
                }
            } else if (call.method == "saveRecordingToGallery") {
                val path = call.argument<String>("videoPath")
                if (path.isNullOrEmpty()) { result.error("INVALID_PATH", "영상 경로가 없습니다.", null); return@setMethodCallHandler }
                if (Build.VERSION.SDK_INT in 23..28 && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                    if (pendingSave != null) { result.error("BUSY", "저장 요청 처리 중", null); return@setMethodCallHandler }
                    pendingSave = Pair(path, result)
                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 701)
                } else saveRecording(path, result)
            } else if (call.method == "extractFrames") {
                val videoPath = call.argument<String>("videoPath")
                val sampleCount = call.argument<Int>("sampleCount") ?: 45

                if (videoPath.isNullOrEmpty() || !File(videoPath).exists()) {
                    result.error("INVALID_PATH", "Video file not found", null)
                    return@setMethodCallHandler
                }

                thread {
                    try {
                        val frames = extractFramesNative(videoPath, sampleCount,
                            call.argument<Number>("startMs")?.toLong(),
                            call.argument<Number>("endMs")?.toLong(),
                            call.argument<Number>("maxIntervalMs")?.toLong())
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

    private fun extractFramesNative(
        videoPath: String, sampleCount: Int, startMs: Long?, endMs: Long?, maxIntervalMs: Long?
    ): List<Map<String, Any>> {
        val retriever = MediaMetadataRetriever()
        val framesDir = File(cacheDir, "gallery_frames/${System.nanoTime()}")
        val framesList = mutableListOf<Map<String, Any>>()
        try {
            retriever.setDataSource(videoPath)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            if (duration <= 0) return emptyList()
            val start = (startMs ?: 0L).coerceIn(0L, duration - 1)
            val end = (endMs ?: (duration - 1)).coerceIn(start, duration - 1)
            val count = if (maxIntervalMs != null) {
                val interval = maxIntervalMs.coerceIn(100L, 1000L)
                maxOf(sampleCount, ((end - start + interval - 1) / interval + 1).toInt()).coerceIn(2, 360)
            } else sampleCount.coerceIn(2, 180)
            val orientationFile = File("$videoPath.orientation.json")
            val turns = try {
                if (orientationFile.exists()) JSONObject(orientationFile.readText()).optInt("quarter_turns", 0).coerceIn(0, 3) else 0
            } catch (_: Exception) { 0 }
            framesDir.mkdirs()
            for (i in 0 until count) {
                val tMs = (start + i * (end - start).toDouble() / (count - 1)).toLong()
                val decoded = retriever.getFrameAtTime(tMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST) ?: continue
                val bitmap = if (turns == 0) decoded else {
                    try {
                        Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height,
                            Matrix().apply { postRotate(turns * 90f) }, true)
                    } finally { decoded.recycle() }
                }
                val frameFile = File(framesDir, "frame_${i}_${tMs}.jpg")
                try {
                    FileOutputStream(frameFile).use { out ->
                        check(bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)) { "Frame encoding failed" }
                    }
                    framesList.add(mapOf("t_ms" to tMs.toInt(), "path" to frameFile.absolutePath,
                        "width" to bitmap.width, "height" to bitmap.height))
                } finally {
                    bitmap.recycle()
                }
            }
            return framesList
        } catch (e: Exception) {
            framesDir.listFiles()?.forEach { it.delete() }
            framesDir.delete()
            throw e
        } finally {
            retriever.release()
        }
    }
}
