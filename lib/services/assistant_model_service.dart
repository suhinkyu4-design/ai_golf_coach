import 'dart:convert';
import 'package:flutter/services.dart';
import 'assistant_rules.dart';
import 'assistant_intent.dart';

class AssistantModelReply {
  final String action;
  final String? argument;
  final String reply;
  const AssistantModelReply(this.action, this.argument, this.reply);
}

/// The candidate model can suggest a button, never execute an unknown request.
class AssistantModelService {
  static const channel =
      MethodChannel('com.metaoffice.aigolfcoatch/assistant_slm');
  static Future<bool> isReady() async {
    try {
      return await channel.invokeMethod<bool>('isReady') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> install(String path) =>
      channel.invokeMethod('installModel', {'path': path});

  static String _clean(String value) =>
      value.replaceAll('<|', '＜｜').replaceAll('|>', '｜＞');

  static Map<String, dynamic>? _jsonObject(String raw) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final value = jsonDecode(raw.substring(start, end + 1));
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  /// Rules choose the safe action and provide verified facts. The model owns
  /// the user-facing wording for every conversational response.
  static Future<AssistantModelReply?> respond({
    required String request,
    required AssistantRules rules,
    required AssistantDecision decision,
    required String draftReply,
    required List<Map<String, String>> history,
    required bool hasAnalysis,
    required bool busy,
    bool allowSuggestedAction = false,
  }) async {
    if (busy || request.length > 1000 || !await isReady()) return null;
    final requiredAction =
        decision.intent.action == 'unknown' ? 'reply' : decision.intent.action;
    final argument = decision.intent.argument;
    final compactFeatures = rules.features
        .map((feature) => {
              'action': feature['action'],
              'description': feature['description'],
            })
        .toList();
    final actionInstruction = allowSuggestedAction
        ? '사용자는 자연어 질문을 했습니다. action에는 reply, clarify 또는 관련된 앱 기능을 제안할 수 있습니다. 제안한 기능은 앱에서 자동 실행되지 않습니다. '
        : '앱이 검증한 action은 "$requiredAction"이고 argument는 ${jsonEncode(argument)}다. action과 argument를 바꾸지 말고, ';
    final system =
        '${await rootBundle.loadString('assets/assistant_model_system.txt')}\n'
        '$actionInstruction draft_reply와 facts만 이용해 자연스럽고 간결한 한국어 reply를 작성한다. '
        '사용자의 말투와 직전 대화 맥락을 반영하되 확인되지 않은 측정값이나 기능을 만들지 않는다. '
        '고정 안내문처럼 기능 목록을 반복하지 말고 사용자가 방금 물은 내용에 직접 답한다.';
    final input = jsonEncode({
      'request': request,
      'state': {
        'screen': 'chat',
        'has_analysis': hasAnalysis,
        'busy': busy,
        'last_topic': argument,
      },
      'facts': [
        {'id': 'verified_draft', 'text': draftReply},
        {'id': 'app_features', 'value': compactFeatures},
      ],
      'history': history.take(8).toList(),
      'tool_result': null,
      'required_action': requiredAction,
      'required_argument': argument,
      'allow_suggested_action': allowSuggestedAction,
      'draft_reply': draftReply,
    });
    final prompt = '<|im_start|>system\n${_clean(system)}<|im_end|>\n'
        '<|im_start|>user\n${_clean(input)}<|im_end|>\n'
        '<|im_start|>assistant\n<think>\n\n</think>\n\n';
    try {
      final raw =
          await channel.invokeMethod<String>('describe', {'prompt': prompt});
      final value = raw == null ? null : _jsonObject(raw);
      final reply = value?['reply'];
      final evidence = value?['evidence_ids'];
      final responseAction = value?['action'];
      final responseArgument = value?['argument'];
      final allowedActions = <String>{...AssistantRules.actions, 'reply', 'clarify'};
      final validAction = allowSuggestedAction
          ? responseAction is String && allowedActions.contains(responseAction)
          : responseAction == requiredAction;
      final validArgument = allowSuggestedAction
          ? responseArgument == null || responseArgument is String
          : responseArgument == argument;
      if (!validAction ||
          !validArgument ||
          reply is! String ||
          reply.trim().length < 2 ||
          reply.length > 1200 ||
          evidence is! List) return null;
      return AssistantModelReply(
          responseAction as String, responseArgument as String?, reply.trim());
    } catch (_) {
      return null;
    }
  }

  static Future<String?> suggest(String request, AssistantRules rules,
      {required bool hasAnalysis, required bool busy}) async {
    if (busy || request.length > 1000 || !await isReady()) return null;
    final system =
        '${await rootBundle.loadString('assets/assistant_model_system.txt')}\n'
        '현재 앱 기능 참고: ${rules.relevantContextJson(request)}';
    final input = jsonEncode({
      'request': request,
      'state': {
        'screen': 'chat',
        'has_analysis': hasAnalysis,
        'busy': busy,
        'last_topic': null
      },
      'facts': [],
      'history': [],
      'tool_result': null
    });
    final prompt = '<|im_start|>system\n${_clean(system)}<|im_end|>\n'
        '<|im_start|>user\n${_clean(input)}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n';
    try {
      final raw =
          await channel.invokeMethod<String>('describe', {'prompt': prompt});
      if (raw == null) return null;
      final p = _jsonObject(raw);
      if (p == null ||
          p['argument'] != null ||
          p['evidence_ids'] is! List ||
          (p['evidence_ids'] as List).isNotEmpty) return null;
      for (final f in rules.features) {
        if (f['action'] != p['action']) continue;
        final guarded = rules.guard(AssistantIntent(f['action'] as String),
            hasAnalysis: hasAnalysis, busy: busy);
        if (guarded.message != null) return null;
        final aliases = f['utterances'] as List;
        return aliases.isEmpty ? null : aliases.first as String;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
