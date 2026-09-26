package com.metaoffice.aigolfcoatch

import android.app.Activity
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Offline, pinned-model prototype. Executable is packaged in APK native libs. */
class GolfSlmChannel(private val activity: Activity, messenger: BinaryMessenger,
    channelName: String = "com.metaoffice.aigolfcoatch/slm",
    modelName: String = "golf_slm_q8_0.gguf",
    private val expectedSize: Long = 639446720L,
    private val expectedHash: String = "72f3911c4e922c63b2b5ccafabadada241d010e6fb86a6edb3b0daf0e1e251b1") {
    private val channel = MethodChannel(messenger, channelName)
    private val executor = Executors.newSingleThreadExecutor()
    private val model = File(activity.filesDir, "slm/$modelName")
    private val binary = File(activity.applicationInfo.nativeLibraryDir, "libgolf_slm.so")
    @Volatile private var running: Process? = null
    @Volatile private var closed = false
    private var verifiedStamp = -1L

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "isReady") {
                result.success(ready())
            } else if (call.method == "installModel" || call.method == "describe") {
                if (closed) { result.error("CLOSED", "화면이 종료되었습니다.", null); return@setMethodCallHandler }
                val path = call.argument<String>("path")
                val prompt = call.argument<String>("prompt")
                executor.execute {
                    try {
                        val output: Any = if (call.method == "installModel") {
                            require(Build.VERSION.SDK_INT >= 28 && binary.isFile) { "이 기기는 현재 실험 모델을 지원하지 않습니다." }
                            install(path ?: error("모델 파일이 없습니다.")); true
                        } else { infer(prompt ?: error("측정 입력이 없습니다.")) }
                        activity.runOnUiThread { if (!closed) result.success(output) }
                    } catch (error: Exception) {
                        activity.runOnUiThread { if (!closed) result.error("SLM_FAILED", error.message ?: "모델 실행 실패", null) }
                    }
                }
            } else result.notImplemented()
        }
    }

    private fun ready() = Build.VERSION.SDK_INT >= 28 && binary.isFile && model.isFile && model.length() == expectedSize
    private fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    private fun install(path: String) {
        val source = File(path)
        require(source.isFile && source.length() == expectedSize) { "Q8 모델 파일 크기가 일치하지 않습니다." }
        model.parentFile!!.mkdirs()
        val temporary = File.createTempFile("model-", ".part", model.parentFile)
        try {
            source.inputStream().use { input -> temporary.outputStream().use { input.copyTo(it) } }
            require(hash(temporary) == expectedHash) { "모델 검증에 실패했습니다. 원본 파일을 확인해 주세요." }
            Files.move(temporary.toPath(), model.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
            verifiedStamp = model.lastModified()
        } finally { temporary.delete() }
    }
    private fun infer(prompt: String): String {
        require(ready()) { "설명 모델을 먼저 등록해 주세요." }
        require(prompt.toByteArray(Charsets.UTF_8).size in 1..12000) { "측정 입력이 너무 큽니다." }
        if (verifiedStamp != model.lastModified()) {
            require(hash(model) == expectedHash) { "모델 파일 검증에 실패했습니다." }
            verifiedStamp = model.lastModified()
        }
        val directory = Files.createTempDirectory(activity.cacheDir.toPath(), "slm-").toFile()
        try {
            val input = File(directory, "prompt.txt").apply { writeText(prompt, Charsets.UTF_8) }
            val output = File(directory, "response.txt")
            val log = File(directory, "runtime.log")
            val process = ProcessBuilder(binary.absolutePath, "-m", model.absolutePath,
                "-f", input.absolutePath, "-n", "256", "-c", "2048", "-t", "4", "-ngl", "0",
                "--temp", "0", "--no-conversation", "--no-display-prompt", "--simple-io", "--no-escape")
                .redirectOutput(output).redirectError(log).start()
            running = process
            if (!process.waitFor(90, TimeUnit.SECONDS)) { process.destroyForcibly(); error("설명 생성 시간이 초과되었습니다.") }
            require(process.exitValue() == 0) { "설명 모델 실행에 실패했습니다." }
            require(output.length() <= 32768) { "모델 응답이 너무 큽니다." }
            return output.readText(Charsets.UTF_8).trim().removeSuffix("[end of text]").trim()
        } finally {
            running?.destroy(); running = null
            directory.deleteRecursively()
        }
    }
    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        running?.destroyForcibly()
        executor.shutdownNow()
    }
}
