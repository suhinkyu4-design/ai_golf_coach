import 'dart:convert';
import 'dart:io';
import '../lib/services/assistant_rules.dart';

void main(List<String> args) {
  final source = File('assets/assistant_rules.json').readAsStringSync();
  final rules = AssistantRules.fromJson(source);
  void check(bool ok, String label) {
    if (!ok) throw StateError(label);
  }

  String action(String text, {bool busy = false, bool result = true}) =>
      rules.resolve(text, hasAnalysis: result, busy: busy).intent.action;
  check(action('촬영') == 'camera', 'camera');
  check(action('음성 촬영은 어떻게 사용해') == 'reply', 'question must not execute');
  check(action('화면 어둡게 해줘', busy: true) == 'reply', 'busy mutation');
  check(action('영상 보여줘', result: false) == 'reply', 'missing result');
  check(action('촬영하지 마') == 'clarify', 'negation');
  check(action('후방 대신 정면 촬영으로 저장하자') != 'rear', 'direction reversal');
  final updated = jsonDecode(source);
  final f =
      (updated['features'] as List).firstWhere((f) => f['action'] == 'gallery');
  f['utterances'].add('보관한 스윙 불러오기');
  f['questions'].add('보관 영상은 어디서 찾아');
  f['description'] = '보관한 스윙은 갤러리에서 선택합니다.';
  final next = AssistantRules.fromJson(jsonEncode(updated));
  check(
      next
              .resolve('보관한 스윙 불러오기', hasAnalysis: false, busy: false)
              .intent
              .action ==
          'gallery',
      'new rule without training');
  check(
      next.resolve('보관 영상은 어디서 찾아', hasAnalysis: false, busy: false).message ==
          f['description'],
      'updated knowledge');
  String proposal(String a) => jsonEncode(
      {'action': a, 'argument': null, 'reply': 'done', 'evidence_ids': []});
  check(
      rules
              .validateProposal('갤러리', proposal('camera'),
                  hasAnalysis: true, busy: false)
              .intent
              .action ==
          'clarify',
      'wrong model action');
  check(
      rules
              .validateProposal('갤러리', proposal('gallery'),
                  hasAnalysis: true, busy: false)
              .intent
              .action ==
          'gallery',
      'matching action');
  check(
      rules
              .validateProposal('새로운 알 수 없는 요청', proposal('dark'),
                  hasAnalysis: true, busy: false)
              .intent
              .action ==
          'clarify',
      'unknown model action');
  f['action'] = 'deleteEverything';
  bool rejected = false;
  try {
    AssistantRules.fromJson(jsonEncode(updated));
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'unknown handler');
  print('PASS: 12 rules, state gates, updates, and model disagreement checks');
  if (args.length == 2) {
    final predictions = jsonDecode(File(args[0]).readAsStringSync()) as List;
    final rows = {
      for (final line in File(args[1]).readAsLinesSync())
        jsonDecode(line)['id']: jsonDecode(line)
    };
    int wrong = 0, blocked = 0, allowed = 0, correctAllowed = 0;
    for (final pred in predictions) {
      final input = jsonDecode(rows[pred['id']]['messages'][1]['content']);
      final decision = rules.validateProposal(input['request'], pred['raw'],
          hasAnalysis: input['state']['has_analysis'],
          busy: input['state']['busy']);
      final executes = AssistantRules.actions.contains(decision.intent.action);
      if (executes) {
        allowed++;
        if (pred['audit']['action_argument_exact'] == true) correctAllowed++;
      }
      if (pred['audit']['unsafe_execution'] == true) {
        wrong++;
        if (!executes) blocked++;
      }
    }
    print(jsonEncode({
      'previous_wrong_proposals': wrong,
      'blocked': blocked,
      'execution_allowed': allowed,
      'correct_allowed': correctAllowed,
      'total': predictions.length,
      'note':
          'Replay diagnostic only. Conservative exact-rule coverage, not improved model accuracy.'
    }));
  }
}
