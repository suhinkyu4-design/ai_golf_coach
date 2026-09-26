import 'dart:convert';
import 'assistant_intent.dart';

class AssistantDecision {
  final AssistantIntent intent;
  final String? message;
  final List<String> actions;
  const AssistantDecision(this.intent, [this.message, this.actions = const []]);
}

/// Bundled application-owned rules. Model output cannot register new handlers.
class AssistantRules {
  static const actions = {
    'camera',
    'gallery',
    'settings',
    'history',
    'result',
    'resultPage',
    'detail',
    'video',
    'timing',
    'shot',
    'slm',
    'back',
    'dark',
    'light',
    'left',
    'right',
    'driver',
    'iron',
    'rear',
    'face',
    'voiceOn',
    'voiceOff',
    'menu',
    'explain',
    'practice',
    'followup',
    'help'
  };
  static const needs = {
    'result',
    'resultPage',
    'detail',
    'video',
    'timing',
    'shot'
  };
  static const busyActions = {
    'camera',
    'gallery',
    'timing',
    'shot',
    'dark',
    'light',
    'left',
    'right',
    'driver',
    'iron',
    'rear',
    'face',
    'voiceOn',
    'voiceOff',
    'menu'
  };
  final List<Map<String, dynamic>> features;
  final int version;
  AssistantRules._(this.version, this.features);
  static String normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s.,!?]'), '');

  factory AssistantRules.fromJson(String source) {
    final doc = jsonDecode(source) as Map<String, dynamic>;
    if (doc['version'] is! int || doc['version'] < 1)
      throw const FormatException('rule version');
    final features = <Map<String, dynamic>>[];
    final seenActions = <String>{}, seenPhrases = <String>{};
    for (final value in doc['features'] as List) {
      final f = Map<String, dynamic>.from(value as Map);
      if (!actions.contains(f['action']) ||
          !seenActions.add(f['action']) ||
          f['description'] is! String ||
          f['requires_analysis'] is! bool ||
          f['blocked_while_busy'] is! bool)
        throw const FormatException('invalid feature');
      for (final key in ['utterances', 'questions']) {
        for (final p in f[key] as List) {
          if (p is! String ||
              normalize(p).isEmpty ||
              !seenPhrases.add(normalize(p))) {
            throw const FormatException('ambiguous phrase');
          }
        }
      }
      features.add(f);
      for (final group in (f['search_groups'] as List? ?? const [])) {
        if (group is! List ||
            group.isEmpty ||
            group.any((p) => p is! String || normalize(p).isEmpty)) {
          throw const FormatException('invalid search group');
        }
      }
    }
    return AssistantRules._(doc['version'], features);
  }

  AssistantDecision resolve(String request,
      {required bool hasAnalysis, required bool busy}) {
    final s = normalize(request);
    // Troubleshooting is a question, not a request to open the camera again.
    final failure = RegExp(r'실패|오류|에러|안돼|안되|안됐|못해|못했|멈|먹통|왜|이유').hasMatch(s);
    if (failure && RegExp(r'촬영|카메라|녹화').hasMatch(s)) {
      return const AssistantDecision(AssistantIntent('reply'),
          '촬영이 진행되지 않았군요. 대화로 돌아온 기록만으로는 촬영 실패인지, 저장 전에 종료된 것인지 알 수 없어요.\n\n'
          '어느 단계에서 멈췄나요?\n'
          '• 카메라 화면이 열리지 않음\n'
          '• 시작이라고 말해도 녹화가 안 됨\n'
          '• 녹화 종료 후 저장이나 분석이 안 됨\n\n'
          '화면에 나온 오류 문구가 있다면 함께 알려주세요.',
          ['카메라 화면이 열리지 않음', '시작이라고 말해도 녹화가 안 됨', '종료 후 저장이나 분석이 안 됨']);
    }
    if (RegExp(r'카메라.*열리지|카메라.*안열').hasMatch(s)) {
      return const AssistantDecision(AssistantIntent('reply'),
          '카메라 화면이 열리지 않는 문제군요. 휴대폰 설정 → 앱 → 골프 코치 → 권한에서 카메라 허용 여부를 확인해 주세요. '
          '다른 앱이 카메라를 사용 중이면 닫고 다시 시도해 주세요. 현재 대화에서는 권한 상태나 원인을 직접 확인한 것은 아닙니다.');
    }
    if (RegExp(r'시작.*녹화.*안|음성.*인식.*안|말해도.*안').hasMatch(s)) {
      return const AssistantDecision(AssistantIntent('reply'),
          '음성 시작이 반응하지 않는 문제군요. 음성 촬영 설정과 마이크 권한을 확인한 뒤, '
          '먼저 촬영 화면의 시작 버튼으로 녹화가 되는지 확인해 주세요. 버튼으로 된다면 음성 입력 쪽을 따로 확인할 수 있어요.');
    }
    if (RegExp(r'종료후.*저장|저장.*안|분석.*안|분석.*실패').hasMatch(s)) {
      return const AssistantDecision(AssistantIntent('reply'),
          '저장 단계와 분석 단계를 나눠 확인해 볼게요. 갤러리에 방금 촬영한 영상이 있나요? '
          '있다면 저장은 완료된 것이므로 그 영상을 선택해 분석을 다시 시도해 주세요. '
          '영상이 없다면 저장 단계 확인이 필요합니다. 표시된 오류 문구도 알려주세요.');
    }
    // Negated or compound requests need clarification before any action.
    if (RegExp(r'하지마|하지않|말고|대신|아니|안할|안해|취소해|그리고|동시에').hasMatch(s)) {
      return const AssistantDecision(AssistantIntent('clarify'));
    }
    for (final f in features) {
      if ((f['questions'] as List).any((p) => normalize(p) == s)) {
        return AssistantDecision(
            const AssistantIntent('reply'), f['description'] as String);
      }
    }
    AssistantIntent? intent;
    for (final f in features) {
      if ((f['utterances'] as List).any((p) => normalize(p) == s)) {
        intent = AssistantIntent(f['action'] as String);
        break;
      }
    }
    if (intent == null) {
      final candidates = search(request);
      final question =
          RegExp(r'어떻게|어디|무엇|뭐야|뭔가|방법|사용법|가능|할수있|하는거|하나요|인가요|알려|설명')
              .hasMatch(s);
      if (question && candidates.isNotEmpty) {
        final descriptions = candidates
            .map((f) => f['description'] as String)
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList();
        if (descriptions.isNotEmpty) {
          return AssistantDecision(const AssistantIntent('reply'),
              descriptions.take(3).join('\n\n'));
        }
      }
      final execute = RegExp(
              r'해줘|해주세요|열어|켜줘|켜주|꺼줘|꺼주|바꿔|변경해|설정해|선택할|가져와|보여줘|보여주|할래|하고싶|불러와')
          .hasMatch(s);
      if (!question && execute && candidates.length == 1) {
        intent = AssistantIntent(candidates.single['action'] as String);
      } else if (candidates.isNotEmpty && (execute || question)) {
        return const AssistantDecision(AssistantIntent('clarify'));
      }
    }
    intent ??= AssistantIntent.parse(request);
    return guard(intent, hasAnalysis: hasAnalysis, busy: busy);
  }

  /// Every group must match; alternatives within one group are synonyms.
  /// No fuzzy similarity threshold is used to authorize setting changes.
  List<Map<String, dynamic>> search(String request) {
    final s = normalize(request);
    return features.where((f) {
      final groups = f['search_groups'] as List? ?? const [];
      return groups.isNotEmpty &&
          groups.every((g) =>
              (g as List).any((term) => s.contains(normalize(term as String))));
    }).toList();
  }

  String relevantContextJson(String request) => jsonEncode({
        'rules_version': version,
        'features': search(request),
      });

  AssistantDecision guard(AssistantIntent intent,
      {required bool hasAnalysis, required bool busy}) {
    Map<String, dynamic>? feature;
    for (final f in features) {
      if (f['action'] == intent.action) feature = f;
    }
    if (busy &&
        (busyActions.contains(intent.action) ||
            feature?['blocked_while_busy'] == true)) {
      return const AssistantDecision(
          AssistantIntent('reply'), '분석이 진행 중이에요. 작업이 끝난 뒤 다시 요청해 주세요.');
    }
    if (!hasAnalysis &&
        (needs.contains(intent.action) ||
            feature?['requires_analysis'] == true)) {
      return const AssistantDecision(
          AssistantIntent('reply'), '먼저 스윙 영상을 촬영하거나 갤러리에서 선택해 분석해 주세요.');
    }
    return AssistantDecision(intent);
  }

  /// Future SLM bridge: only independently resolved commands may execute.
  /// Unrecognized requests remain clarification; generated reply is not trusted here.
  AssistantDecision validateProposal(String request, String raw,
      {required bool hasAnalysis, required bool busy}) {
    final local = resolve(request, hasAnalysis: hasAnalysis, busy: busy);
    if (local.message != null) return local;
    try {
      final p = jsonDecode(raw);
      if (p is! Map ||
          p.length != 4 ||
          !p.keys
              .toSet()
              .containsAll({'action', 'argument', 'reply', 'evidence_ids'}) ||
          p['reply'] is! String ||
          p['evidence_ids'] is! List ||
          (p['evidence_ids'] as List).isNotEmpty ||
          !actions.contains(p['action']) ||
          p['action'] != local.intent.action ||
          p['argument'] != local.intent.argument) {
        throw const FormatException('unverified command');
      }
      return local;
    } catch (_) {
      return const AssistantDecision(AssistantIntent('clarify'));
    }
  }

  String contextJson() =>
      jsonEncode({'rules_version': version, 'features': features});
}
