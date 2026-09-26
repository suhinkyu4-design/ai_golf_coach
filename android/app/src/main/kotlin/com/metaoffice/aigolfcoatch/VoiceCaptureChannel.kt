package com.metaoffice.aigolfcoatch

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.media.ToneGenerator
import android.media.AudioManager
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Foreground, opt-in, on-device command recognition. Never falls back to cloud. */
class VoiceCaptureChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.metaoffice.aigolfcoatch/voice_capture")
    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var enabled = false
    private var pending: MethodChannel.Result? = null
    private var failures = 0
    private var generation = 0
    private var expires = 0L
    private var awaiting = false
    private var cycle = 0
    private var conversationRecognition = false
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT < 31 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)) {
                        result.error("UNAVAILABLE", "이 폰에서 기기 내 음성 인식을 사용할 수 없습니다.", null)
                    } else if (pending != null) result.error("BUSY", "마이크 권한 확인 중입니다.", null)
                    else if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) result.success(true)
                    else { pending = result; activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 703) }
                }
                "enable", "enableConversation" -> {
                    if (Build.VERSION.SDK_INT < 31 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)) {
                        result.error("UNAVAILABLE", "이 폰에서 기기 내 음성 인식을 사용할 수 없습니다.", null)
                    } else if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        result.error("PERMISSION", "설정에서 음성 촬영을 켜고 마이크 권한을 허용해 주세요. 촬영 버튼은 사용할 수 있습니다.", null)
                    } else enable(result, call.method == "enableConversation")
                }
                "disable" -> { stop(); result.success(null) }
                "tone" -> {
                    try { val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 85)
                        tone.startTone(ToneGenerator.TONE_PROP_BEEP, 180)
                        handler.postDelayed({ tone.release() }, 250)
                    } catch (_: Exception) { }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    fun permission(grants: IntArray) {
        val result = pending ?: return
        pending = null
        if (grants.isNotEmpty() && grants[0] == PackageManager.PERMISSION_GRANTED) result.success(true)
        else result.error("PERMISSION", "음성 제어에는 마이크 권한이 필요합니다. 촬영 버튼은 사용할 수 있습니다.", null)
    }
    private fun emit(status: String, command: String? = null) {
        Log.i("GOLF_VOICE", "status=$status command=$command")
        channel.invokeMethod("state", mapOf("status" to status, "command" to command))
    }
    private fun enable(result: MethodChannel.Result, conversation: Boolean = false) {
        stop()
        conversationRecognition = conversation
        try {
            recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
            enabled = true; failures = 0; expires = System.currentTimeMillis() + 120000
            val token = generation
            recognizer!!.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) { if (enabled && token == generation) emit("listening") }
                override fun onBeginningOfSpeech() { }
                override fun onRmsChanged(rmsdB: Float) { }
                override fun onBufferReceived(buffer: ByteArray?) { }
                override fun onEndOfSpeech() { if (enabled && token == generation) emit("processing") }
                override fun onError(error: Int) {
                    if (!enabled || token != generation || !awaiting) return
                    awaiting = false
                    Log.i("GOLF_VOICE", "recognizer_error=$error")
                    if (conversationRecognition) { stop(); emit("unavailable:$error"); return }
                    if (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) retry(token)
                    else if ((error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY || error == SpeechRecognizer.ERROR_SERVER_DISCONNECTED) && ++failures <= 3) retry(token, 1500)
                    else { stop(); emit("unavailable:$error") }
                }
                override fun onResults(results: Bundle?) {
                    if (!enabled || token != generation || !awaiting) return
                    awaiting = false
                    failures = 0
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                    if (conversationRecognition) {
                        stop()
                        channel.invokeMethod("state", mapOf("status" to "transcript", "text" to (text ?: "")))
                        return
                    }
                    val command = VoiceCommand.parse(text)
                    Log.i("GOLF_VOICE", "final_command_match=${command != null}")
                    if (command != null) { expires = System.currentTimeMillis() + 120000; emit("command", command) }
                    retry(token)
                }
                override fun onPartialResults(partialResults: Bundle?) { }
                override fun onEvent(eventType: Int, params: Bundle?) { }
            })
            listen(generation)
            result.success(true)
        } catch (e: Exception) { stop(); result.error("START", "음성 인식을 시작하지 못했습니다. 촬영 버튼을 이용해 주세요.", null) }
    }
    private fun retry(token: Int, delay: Long = 500) {
        if (enabled && token == generation) { emit("restarting"); handler.postDelayed({ listen(token) }, delay) }
    }
    private fun listen(token: Int) {
        if (!enabled || token != generation) return
        if (System.currentTimeMillis() >= expires) { stop(); emit("expired"); return }
        awaiting = true
        val currentCycle = ++cycle
        handler.postDelayed({
            if (enabled && token == generation && awaiting && cycle == currentCycle) {
                stop(); emit("unavailable:timeout")
            }
        }, 25000)
        try { recognizer?.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ko-KR")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }) } catch (_: Exception) { stop(); emit("unavailable") }
    }
    fun stop() { awaiting = false; enabled = false; generation++; recognizer?.cancel(); recognizer?.destroy(); recognizer = null }
    fun close() { stop(); pending?.error("CLOSED", "촬영 화면이 닫혔습니다.", null); pending = null; channel.setMethodCallHandler(null) }
}
