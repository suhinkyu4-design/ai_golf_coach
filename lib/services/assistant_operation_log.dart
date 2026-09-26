import 'capture_quality_guidance.dart';
import 'dart:io';
import 'dart:convert';
/// Bounded local operation journal; chat receives structured facts, not raw stacks.
class AssistantOperationLog {
  final File? storage;
  AssistantOperationLog({this.storage});
  static final current = AssistantOperationLog();
  final Map<String, ({DateTime at, String reason})> _failures = {};
  final List<Map<String,dynamic>> _events=[];
  Future<void> _pending=Future.value();
  bool _loaded=false;
  File get file => storage ?? File('${Directory.systemTemp.path}/golf_assistant_diagnostics.json');
  void begin() { _loaded=true; _failures.clear(); _events.clear(); note('작업', '시작', '새 영상 분석을 시작했습니다.'); }
  void note(String stage,String level,String message) {
    _loaded=true;
    _events.add({'at':DateTime.now().toIso8601String(),'stage':stage,'level':level,'message':message});
    if(_events.length>150) _events.removeRange(0,_events.length-150);
    final snapshot=jsonEncode(_events);
    _pending=_pending.then((_) async { try { await file.writeAsString(snapshot,flush:true); } catch (_) {} });
  }
  Future<String?> explainSaved(String request) async {
    await _pending;
    if(!_loaded) {
      _loaded=true;
      try { final saved=jsonDecode(await file.readAsString());
        if(saved is List) _events.addAll(saved.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)));
      } catch (_) {}
    }
    final s=request.replaceAll(RegExp(r'\s'),'');
    if(RegExp(r'초점|포커스|흐릿|흐려|흔들|촬영방법|잘찍').hasMatch(s)) {
      return '촬영 상태를 확인해 주세요.\n\n${CaptureQualityGuidance.advice}\n\n${CaptureQualityGuidance.retry}';
    }
    if(!RegExp(r'오류|경고|실패|안돼|안되|안됐|안됨|못|불가|왜|이유|fallback|로그|대체').hasMatch(s)) return null;
    final recent=_events.where((e) {
      final at=DateTime.tryParse(e['at']?.toString() ?? '');
      return at!=null && DateTime.now().difference(at)>=Duration.zero && DateTime.now().difference(at)<const Duration(hours:24);
    }).toList();
    final issues=recent.where((e)=>['오류','경고','대체 처리'].contains(e['level'])).toList();
    if(issues.isEmpty) return explain(request) ?? '최근 작업 로그에서 오류·경고 기록을 찾지 못했어요. 기록이 없다는 것만으로 분석 성공을 뜻하지는 않습니다. 문제가 발생한 영상을 다시 분석하면 단계별 기록을 확인할 수 있어요.';
    final selected=issues.reversed.take(6).toList().reversed.toList();
    final capture=issues.where((e)=>e['stage']=='촬영 상태 확인').toList();
    if(capture.isNotEmpty && !selected.contains(capture.last)) selected.insert(0,capture.last);
    final latest=recent.last;
    final lastStatus='마지막 기록: ${latest['stage']} · ${latest['level']} — ${latest['message']}';
    return '최근 영상 작업의 기록을 확인했어요.\n$lastStatus\n\n'+selected.map((e)=>'• [${e['stage']} · ${e['level']}] ${e['message']}').join('\n\n')+'\n\n대체 처리는 다른 방법으로 분석을 이어갔다는 뜻이며, 측정 불가는 정상 판정이 아닙니다. 원인이 기록되지 않은 부분은 추측하지 않을게요.' + (issues.any((e)=>['관절 인식','촬영 상태 확인','스윙 시점 탐색'].contains(e['stage'])) ? '\n\n${CaptureQualityGuidance.retry}' : '');
  }
  void reportFaults(Map features) {
    const names={'head_trail_check':'스웨이','sway_check':'스웨이','early_extension_check':'배치기','standing_up_check':'얼리 스탠드업','stand_up_check':'얼리 스탠드업','casting_check':'캐스팅','over_the_top_check':'오버더탑','chicken_wing_check':'치킨윙','head_up_check':'헤드업'};
    const reasons={'insufficient_joint_samples':'필요한 관절 표본이 부족합니다.','baseline_unavailable':'어드레스 기준 자세를 확보하지 못했습니다.','reviewed_events_required':'스윙 시점을 확정하지 못했습니다.','sampling_gaps_too_large':'분석 장면 사이의 시간 간격이 큽니다.','foot_length_unavailable':'발 길이 기준을 측정하지 못했습니다.','head_width_unavailable':'머리 너비 기준을 측정하지 못했습니다.','target_direction_unknown':'타격 방향을 확정하지 못했습니다.','ball_direction_unknown':'공 방향을 확정하지 못했습니다.','different_view_required':'이 판정에 필요한 촬영 방향과 다릅니다.'};
    for(final e in features.entries) {
      if(e.value is! Map || !e.key.toString().endsWith('_check')) continue;
      final row=e.value as Map;
      if(row['status']=='unavailable') {
        final code=row['reason']?.toString() ?? 'not_recorded';
        final safeCode=RegExp(r'^[a-z0-9_]{1,100}$').hasMatch(code)?code:'not_recorded';
        note(names[e.key] ?? '동작 ${e.key}', '경고', '측정 불가: ${reasons[code] ?? '유효한 측정 근거를 확보하지 못했습니다.'} (기록 코드: $safeCode)');
      }
    }
  }
  void success(String stage) { _failures.remove(stage); note(stage, '완료', '이 단계가 완료됐습니다. 앞선 경고는 작업 이력입니다.'); }
  void fail(String stage, Object error, {DateTime? at}) {
    final s=error.toString().toLowerCase();
    final reason=s.contains('cameraaccessdenied') ? 'camera_permission'
      : s.contains('enospc') || s.contains('no space left') ? 'storage_full'
      : s.contains('missingpluginexception') ? 'plugin_missing'
      : 'unknown';
    _failures[stage]=(at:at ?? DateTime.now(),reason:reason);
    note(stage, '오류', switch(reason) { 'camera_permission'=>'카메라 접근 권한이 거부됐습니다.', 'storage_full'=>'저장 공간 부족 오류입니다.', 'plugin_missing'=>'기기 기능 연결을 찾지 못했습니다.', _=>'처리에 실패했습니다. 구체적인 원인은 아직 확인되지 않았습니다.' });
  }
  String? explain(String request, {DateTime? now}) {
    final s=request.replaceAll(RegExp(r'\s'), '');
    if(!RegExp(r'실패|오류|에러|안돼|안되|안됐|안됨|못|멈|왜|이유').hasMatch(s)) return null;
    final stages=RegExp(r'분석|관절|스윙시점').hasMatch(s) ? {'scan','analysis'}
      : RegExp(r'갤러리|영상선택').hasMatch(s) ? {'selection','scan'}
      : RegExp(r'저장').hasMatch(s) ? {'save'}
      : RegExp(r'음성|말해도').hasMatch(s) ? {'voice'}
      : RegExp(r'촬영|카메라|녹화').hasMatch(s) ? {'camera','recording','save','voice'}
      : _failures.keys.toSet();
    final time=now ?? DateTime.now();
    final entries=_failures.entries.where((e)=>stages.contains(e.key) &&
      time.difference(e.value.at)>=Duration.zero && time.difference(e.value.at)<const Duration(minutes:30)).toList()
      ..sort((a,b)=>b.value.at.compareTo(a.value.at));
    if(entries.isEmpty) return null;
    final e=entries.first;
    const names={'selection':'갤러리 영상 선택','camera':'카메라 열기','recording':'녹화 처리','save':'갤러리 저장','voice':'음성 촬영 연결','scan':'영상의 관절·스윙 구간 찾기','analysis':'동작 분석'};
    final detail=switch(e.value.reason) {
      'camera_permission'=>'카메라 접근 권한이 거부됐다는 오류가 확인됐어요. 휴대폰 설정의 앱 권한에서 카메라를 허용해 주세요.',
      'storage_full'=>'저장 공간이 부족하다는 오류가 확인됐어요. 휴대폰의 여유 공간을 확보한 뒤 다시 시도해 주세요.',
      'plugin_missing'=>'앱의 기기 기능 연결을 찾지 못하는 오류가 확인됐어요. 앱을 완전히 종료하고 다시 열어 주세요. 반복되면 앱 수정이 필요합니다.',
      _=>'이 단계가 실패한 기록은 있지만 구체적인 원인은 확인되지 않았어요. 화면에 나온 오류 문구가 있으면 함께 알려주세요.',
    };
    return '이번 앱 실행의 최근 작업에서 ‘${names[e.key] ?? e.key}’ 오류가 기록됐어요.\n\n$detail';
  }
}
