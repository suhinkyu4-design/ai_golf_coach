package com.metaoffice.aigolfcoatch

/** Final utterances only. Reject negatives, questions, and conflicting commands. */
object VoiceCommand {
    fun parse(utterance: String?): String? {
        val text = utterance?.replace(Regex("[\\s.,!?。]"), "") ?: return null
        val match = Regex("^(?:골프)?(?:촬영)?(시작|종료)(?:해|해줘|해주세요|하세요)?$").matchEntire(text) ?: return null
        return if (match.groupValues[1] == "시작") "start" else "stop"
    }
}
