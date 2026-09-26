import '../lib/services/assistant_intent.dart';
void main(){
 const cases={'새 영상 촬영':'camera','갤러리에서 가져오기':'gallery','촬영 방법 설명해줘':'help','화면 어둡게 해줘':'dark','어둡게 하지 마':'clarify','시작 종료':'unknown','왼손잡이로 설정해':'left','배치기 설명해줘':'explain','샷 기록 추가':'shot','메뉴 모드':'menu','이전 화면':'back','자세 시점 수정':'timing','결과 펼쳐 보기':'resultPage','음성 촬영 꺼줘':'voiceOff','드라이버 아이언':'unknown','파일 전부 삭제':'unknown'};
 for(final e in cases.entries){final result=AssistantIntent.parse(e.key);if(result.action!=e.value)throw StateError('${e.key}: ${result.action} != ${e.value}');}
 if(AssistantIntent.parse('치킨윙은 왜 나왔어?').argument!='chicken_wing_check')throw StateError('Topic failed');
 print('PASS 17 assistant intent cases');
}
