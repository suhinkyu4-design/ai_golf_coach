import 'dart:convert';
import 'package:flutter/services.dart';
import 'assistant_rules.dart';
import 'assistant_intent.dart';

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
    String clean(String s) => s.replaceAll('<|', '＜｜').replaceAll('|>', '｜＞');
    final prompt = '<|im_start|>system\n${clean(system)}<|im_end|>\n'
        '<|im_start|>user\n${clean(input)}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n';
    try {
      final raw =
          await channel.invokeMethod<String>('describe', {'prompt': prompt});
      if (raw == null) return null;
      final p = jsonDecode(raw);
      if (p is! Map ||
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
