import com.metaoffice.aigolfcoatch.VoiceCommand
fun main() {
 val starts=listOf("시작", "시작!", "촬영 시작", "골프 촬영 시작", "시작해 주세요", "시작해줘")
 val stops=listOf("종료", "종료.", "촬영 종료", "골프 촬영 종료", "종료해 주세요", "종료해줘")
 val ignored=listOf("시작하지 마", "종료하지 마", "시작 종료", "시작할까", "시작점", "종료시간", "", "아직 시작하지 마세요")
 starts.forEach { check(VoiceCommand.parse(it)=="start") { it } }
 stops.forEach { check(VoiceCommand.parse(it)=="stop") { it } }
 ignored.forEach { check(VoiceCommand.parse(it)==null) { it } }
 check(VoiceCommand.parse(null)==null)
 println("PASS: 21 command/negative/ambiguous cases")
}
