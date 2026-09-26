import '../widgets/coach_app_bar.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../providers/experience_settings.dart';
import '../providers/voice_settings.dart';
import '../theme/theme_controller.dart';
import '../models/swing_model.dart';
import '../services/assistant_rules.dart';
import '../services/assistant_operation_log.dart';
import '../services/assistant_model_service.dart';
import '../services/correction_guide.dart';
import '../services/shot_insight_service.dart';
import '../widgets/motion_visual_card.dart';
import '../widgets/assistant_welcome.dart';
import '../widgets/shot_visual_card.dart';
import 'video_input_screen.dart';
import 'appearance_settings_screen.dart';
import 'history_screen.dart';
import 'analysis_result_screen.dart';
import 'analysis_details_screen.dart';
import 'motion_detection_screen.dart';
import 'pose_trimming_screen.dart';
import 'ocr_input_screen.dart';
import 'slm_settings_screen.dart';

class _Message {
  final String text;
  final bool user;
  final List<String> actions;
  final String? resultId;
  const _Message(this.text,
      {this.user = false, this.actions = const [], this.resultId});
}

class AssistantScreen extends StatefulWidget {
  final bool popup, cameraContext;
  final AssistantScreenContext? situation;
  const AssistantScreen(
      {super.key,
      this.popup = false,
      this.cameraContext = false,
      this.situation});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with WidgetsBindingObserver {
  static const _voice =
      MethodChannel('com.metaoffice.aigolfcoatch/voice_capture');
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[
    const _Message(
        '안녕하세요. 스윙을 함께 살펴볼 골프 코치입니다.\n\n새로 찍으려면 ‘촬영’, 저장된 영상이라면 ‘갤러리’를 선택하세요. 분석이 끝나면 결과와 연습 방법을 여기에서 안내할게요.',
        actions: ['새 영상 촬영', '갤러리에서 가져오기'])
  ];
  bool _working = false, _listening = false, _away = false;
  String? _topic;
  Object? _seenResult;
  String? _pendingCommand;
  Timer? _voiceTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.popup && widget.situation != null) {
      _messages.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send(widget.situation!.question);
      });
    } else if (widget.popup) {
      _messages[0] = _Message(
          widget.cameraContext
              ? '촬영 화면을 유지하며 문자로 도와드릴게요. 촬영 중에는 시작·종료 음성 명령을 그대로 사용할 수 있어요.'
              : '무엇을 도와드릴까요? 기능 사용법이나 분석 결과를 물어보세요.',
          actions: widget.cameraContext ? const [] : const ['도움말', '설정']);
    }
  }

  void _bindVoice() {
    _voice.setMethodCallHandler((call) async {
      if (!mounted || _away || call.method != 'state' || !_listening) return;
      final state = Map<String, dynamic>.from(call.arguments as Map);
      if (state['status'] == 'transcript') {
        _voiceTimer?.cancel();
        setState(() => _listening = false);
        final text = (state['text'] as String? ?? '').trim();
        if (text.isNotEmpty)
          await _send(text);
        else
          _add('말씀을 듣지 못했어요. 마이크를 눌러 다시 말하거나 아래 버튼을 선택해 주세요.');
      } else if ((state['status'] as String? ?? '').startsWith('unavailable')) {
        _voiceTimer?.cancel();
        setState(() => _listening = false);
        _add('말씀을 인식하지 못했어요. 마이크를 눌러 다시 말하거나 글로 입력해 주세요.');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _listening)
      unawaited(_stopVoice());
  }

  Future<void> _stopVoice() async {
    if (!_listening) return;
    _voiceTimer?.cancel();
    if (mounted) setState(() => _listening = false);
    await _voice.invokeMethod('disable');
  }

  Future<void> _listen() async {
    if (_listening) {
      await _stopVoice();
      return;
    }
    try {
      final allowed = await _voice.invokeMethod<bool>('requestPermission');
      if (!mounted || allowed != true) return;
      _bindVoice();
      setState(() => _listening = true);
      await _voice.invokeMethod('enableConversation');
      _voiceTimer = Timer(const Duration(seconds: 25), () async {
        if (!_listening || !mounted) return;
        await _stopVoice();
        if (mounted) _add('음성 입력을 마쳤어요. 다시 말하려면 마이크를 눌러 주세요.');
      });
    } catch (e) {
      if (mounted) {
        setState(() => _listening = false);
        _add(e is PlatformException
            ? e.message ?? '음성 입력을 사용할 수 없어요.'
            : '음성 입력을 사용할 수 없어요. 글이나 버튼으로 계속할 수 있습니다.');
      }
    }
  }

  void _add(String text,
      {bool user = false, List<String> actions = const [], String? resultId}) {
    if (!mounted) return;
    setState(() => _messages
        .add(_Message(text, user: user, actions: actions, resultId: resultId)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients)
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _coachReply({
    required String request,
    required String verifiedDraft,
    required AssistantRules rules,
    required AssistantDecision decision,
    required SwingProvider provider,
    List<String> actions = const [],
    String? resultId,
  }) async {
    final history = _messages.reversed
        .take(8)
        .toList()
        .reversed
        .map((message) => {
              'role': message.user ? 'user' : 'assistant',
              'content': message.text,
            })
        .toList();
    final generated = await AssistantModelService.respond(
      request: request,
      rules: rules,
      decision: decision,
      draftReply: verifiedDraft,
      history: history,
      hasAnalysis: provider.currentSwing != null &&
          provider.currentAnalysisResult != null,
      busy: provider.isAnalyzing,
    );
    if (!mounted) return;
    _add(generated?.reply ?? verifiedDraft,
        actions: actions, resultId: resultId);
  }

  Future<void> _open(Widget page) async {
    if (widget.cameraContext) {
      _add('촬영을 마치고 대화창을 닫은 뒤 해당 기능을 열어 주세요.');
      return;
    }
    await _stopVoice();
    if (!mounted) return;
    _away = true;
    String? next;
    try {
      next = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => page));
    } finally {
      if (mounted) {
        _away = false;
        _bindVoice();
        setState(() {});
      }
    }
    if (mounted && next != null) {
      if (_working) {
        _pendingCommand = next;
      } else {
        await _send(next);
      }
    }
  }

  static const _names = {
    'head_trail_check': '스웨이',
    'early_extension_check': '배치기',
    'standing_up_check': '얼리 스탠드업',
    'chicken_wing_check': '치킨윙',
    'head_up_check': '헤드업',
    'casting_check': '캐스팅',
    'over_the_top_check': '오버더탑'
  };
  String _explain(SwingProvider p, String key) {
    _topic = key;
    final name = _names[key] ?? key;
    final rule = p.currentPoseReport?['fault_features']?[key] as Map?;
    final guide = CorrectionGuide.guides[key];
    if (rule == null || rule['status'] != 'rule_classified')
      return '$name${rule == null ? '의 분석 기록이 아직 없어요.' : '은 이 영상에서 측정 근거가 부족해 판정하지 못했어요.'} 정상이라는 뜻은 아닙니다.\n\n${guide?.focus ?? ''}에 관련된 동작입니다. 분석 가능한 영상을 준비하면 실제 결과에 맞춰 안내할게요.';
    var detail = '';
    final value = rule['value'];
    if (value is num && value.isFinite) {
      if (key == 'head_trail_check')
        detail =
            '머리 이동이 ${rule['normalization_label'] ?? '기준 너비'} 대비 ${(value * 100).toStringAsFixed(1)}%로 기록됐습니다.';
      if (key == 'early_extension_check')
        detail = '임팩트 골반 이동이 발 길이 대비 ${(value * 100).toStringAsFixed(1)}%입니다.';
      if (key == 'standing_up_check')
        detail = '상체 기울기 감소는 ${value.toStringAsFixed(1)}°입니다.';
      if (key == 'chicken_wing_check')
        detail = '임팩트 직후 팔꿈치 굽힘 증가가 ${value.toStringAsFixed(1)}°입니다.';
      if (key == 'head_up_check')
        detail =
            '임팩트 전 머리 상승이 몸통 길이 대비 ${(value * 100).toStringAsFixed(1)}%입니다.';
    }
    if (rule['grade'] == 'within_rule')
      return '$name은 앱 기준 이내입니다. $detail\n\n이 항목을 억지로 바꾸기보다 현재 움직임을 유지해 보세요. 영상 각도와 관절 인식에 따른 오차는 있을 수 있습니다.';
    return '${rule['label'] ?? name}\n$detail\n\n${guide?.focus ?? '해당 장면을 확인해 주세요.'}\n${guide?.steps.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n') ?? ''}';
  }

  void _result(SwingProvider p) {
    final motion = p.currentPoseReport?['fault_features'] as Map?;
    if (p.currentAnalysisResult == null) {
      _add('먼저 스윙 영상을 준비해 주세요. 촬영하거나 갤러리에서 가져올 수 있어요.',
          actions: ['새 영상 촬영', '갤러리에서 가져오기']);
      return;
    }
    final lines = <String>[];
    for (final e in _names.entries) {
      final rule = motion?[e.key] as Map?;
      final label = rule?['status'] == 'rule_classified'
          ? (rule!['label'] ?? rule['grade'])
          : '측정 불가';
      lines.add(rule?['status'] == 'rule_classified'
          ? '$label'
          : '${e.value} · 측정 불가');
    }
    _topic = null;
    for (final e in _names.entries) {
      if (CorrectionGuide.eligible(motion?[e.key] as Map?)) {
        _topic = e.key;
        break;
      }
    }
    _add(
        '스윙 분석 결과입니다.\n\n${motion == null ? p.currentAnalysisResult!.koreanSummary : lines.join('\n')}\n\n${_topic != null ? '먼저 ${_names[_topic]}부터 함께 살펴볼까요?' : '궁금한 동작을 말씀하시거나 결과를 펼쳐 보세요.'}',
        actions: ['결과 펼쳐 보기', '교정안내', '샷 기록 추가'],
        resultId: p.currentSwing?.swingId);
    final shot = ShotInsightService.describe(p.currentShotMeasurement,
        swingId: p.currentSwing?.swingId);
    if (shot.isNotEmpty)
      _add(
          '${p.currentShotMeasurement?.isTestData == true ? '테스트 예시 샷입니다.\n' : ''}${shot.join('\n\n')}');
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _working) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    await _stopVoice();
    if (!mounted) return;
    _add(text, user: true);
    setState(() => _working = true);
    try {
      final p = context.read<SwingProvider>();
      final prefs = context.read<ExperienceSettings>();
      final failure = await AssistantOperationLog.current.explainSaved(text);
      if (failure != null) {
        _add(failure,
            actions: widget.cameraContext
                ? const []
                : const ['다시 촬영하기', '갤러리에서 가져오기']);
        return;
      }
      if (text == '다시 촬영하기') text = '새 영상 촬영';
      final rules = AssistantRules.fromJson(
          await rootBundle.loadString('assets/assistant_rules.json'));
      if (!mounted) return;
      final decision = rules.resolve(text,
          hasAnalysis:
              p.currentSwing != null && p.currentAnalysisResult != null,
          busy: p.isAnalyzing);
      if (decision.message != null) {
        await _coachReply(
            request: text,
            verifiedDraft: decision.message!,
            rules: rules,
            decision: decision,
            provider: p,
            actions: decision.actions);
        return;
      }
      final intent = decision.intent;
      if (intent.action == 'unknown') {
        await _coachReply(
            request: text,
            verifiedDraft:
                '질문을 정확히 이해하지 못했어요. 골프 스윙 분석이나 이 앱의 기능에 관해 조금 더 구체적으로 말씀해 주세요.',
            rules: rules,
            decision: decision,
            provider: p,
            actions: const ['새 영상 촬영', '갤러리에서 가져오기']);
        return;
      }
      switch (intent.action) {
        case 'camera':
        case 'gallery':
          _add(intent.action == 'camera'
              ? '카메라를 열게요. 전신을 담아 촬영해 주세요. 저장 후 분석 결과를 이 대화에 가져올게요.'
              : '갤러리에서 스윙 영상을 하나 선택해 주세요. 분석이 끝나면 여기에서 설명할게요.');
          final before = p.currentAnalysisResult;
          await _open(VideoInputScreen(initialAction: intent.action));
          if (mounted && identical(before, p.currentAnalysisResult))
            _add('대화로 돌아왔어요. 준비되면 다시 촬영하거나 영상을 선택해 주세요.',
                actions: ['새 영상 촬영', '갤러리에서 가져오기']);
          break;
        case 'settings':
          await _open(const AppearanceSettingsScreen());
          break;
        case 'history':
          await _open(const HistoryScreen());
          break;
        case 'result':
          _result(p);
          break;
        case 'resultPage':
          if (p.currentAnalysisResult != null)
            await _open(const AnalysisResultScreen());
          else
            _result(p);
          break;
        case 'detail':
        case 'video':
        case 'timing':
        case 'shot':
          if (p.currentSwing == null || p.currentAnalysisResult == null) {
            _add('먼저 영상을 분석해 주세요.', actions: ['새 영상 촬영', '갤러리에서 가져오기']);
            break;
          }
          await _open(intent.action == 'detail'
              ? const AnalysisDetailsScreen()
              : intent.action == 'video'
                  ? const MotionDetectionScreen()
                  : intent.action == 'timing'
                      ? const PoseTrimmingScreen()
                      : const OcrInputScreen());
          break;
        case 'slm':
          await _open(const SlmSettingsScreen());
          break;
        case 'explain':
          await _coachReply(
              request: text,
              verifiedDraft: _explain(p, intent.argument!),
              rules: rules,
              decision: decision,
              provider: p,
              actions: const ['영상으로 확인하기', '교정안내']);
          break;
        case 'followup':
        case 'practice':
          final draft = _topic != null
              ? _explain(p, _topic!)
              : '어떤 동작이 궁금한지 말씀해 주세요. 스웨이, 배치기, 얼리 스탠드업, 치킨윙, 헤드업, 캐스팅과 오버더탑을 설명할 수 있어요.';
          await _coachReply(
              request: text,
              verifiedDraft: draft,
              rules: rules,
              decision: decision,
              provider: p,
              actions: _topic != null
                  ? const ['영상으로 확인하기', '새 영상 촬영']
                  : const [
                      '스웨이',
                      '배치기',
                      '얼리 스탠드업',
                      '치킨윙',
                      '헤드업',
                      '캐스팅',
                      '오버더탑'
                    ]);
          break;
        case 'dark':
        case 'light':
          await context.read<ThemeController>().select(
              intent.action == 'dark' ? ThemeMode.dark : ThemeMode.light);
          _add('화면을 ${intent.action == 'dark' ? '어둡게' : '밝게'} 변경했어요.');
          break;
        case 'left':
        case 'right':
          await prefs.select(
              hand:
                  intent.action == 'left' ? Handedness.left : Handedness.right);
          _add(
              '다음 스윙부터 ${intent.action == 'left' ? '왼손' : '오른손'}잡이 설정을 사용합니다. 이미 분석한 기록은 바꾸지 않았어요.');
          break;
        case 'driver':
        case 'iron':
          await prefs.select(club: intent.action == 'driver' ? 'Driver' : '7i');
          _add(
              '다음 스윙의 클럽을 ${intent.action == 'driver' ? '드라이버' : '7번 아이언'}로 저장했어요.');
          break;
        case 'rear':
        case 'face':
          await prefs.select(
              view:
                  intent.action == 'rear' ? SwingView.rear : SwingView.faceOn);
          _add(
              '다음 스윙의 촬영 방향을 ${intent.action == 'rear' ? '후방' : '정면'}으로 저장했어요.');
          break;
        case 'voiceOn':
        case 'voiceOff':
          await context
              .read<VoiceSettings>()
              .select(intent.action == 'voiceOn');
          _add(intent.action == 'voiceOn'
              ? '음성 촬영을 켰어요. 카메라에서 ‘시작’, ‘종료’라고 말해 주세요.'
              : '음성 촬영을 껐어요. 촬영 버튼으로 조작할 수 있어요.');
          break;
        case 'menu':
          _add('앱은 메뉴 방식으로 이용합니다. 이 대화창을 닫으면 원래 화면으로 돌아갑니다.');
          break;
        case 'back':
          _topic = null;
          _add('처음 안내로 돌아왔어요. 무엇을 할까요?',
              actions: ['새 영상 촬영', '갤러리에서 가져오기', '설정']);
          break;
        case 'clarify':
          _add('설정을 바꾸거나 작업을 실행하지 않았어요. 원하는 작업 하나를 말씀해 주세요.',
              actions: ['새 영상 촬영', '갤러리에서 가져오기', '설정']);
          break;
        default:
          await _coachReply(
              request: text,
              verifiedDraft:
                  '촬영과 영상 선택부터 결과 확인까지 함께 진행할 수 있어요. 설정에서는 손잡이, 클럽, 촬영 방향, 테마와 음성 촬영을 바꿀 수 있습니다. 궁금한 기능이나 스윙 동작을 편하게 말씀해 주세요.',
              rules: rules,
              decision: decision,
              provider: p,
              actions: const [
                '새 영상 촬영',
                '갤러리에서 가져오기',
                '설정',
                '최근 기록',
                '분석 결과',
                '측정 상세',
                '샷 기록 추가',
                '자세 시점 수정',
                '모델 설정'
              ]);
      }
    } catch (e) {
      _add(
          '작업을 완료하지 못했어요. ${e is PlatformException ? e.message ?? '' : '다시 시도하거나 설정 화면에서 확인해 주세요.'}',
          actions: ['설정', '도움말']);
    } finally {
      if (mounted) {
        setState(() => _working = false);
        final next = _pendingCommand;
        _pendingCommand = null;
        if (next != null) unawaited(_send(next));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceTimer?.cancel();
    if (_listening) unawaited(_voice.invokeMethod('disable'));
    if (!widget.cameraContext && _listening) _voice.setMethodCallHandler(null);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SwingProvider>();
    if (widget.situation == null &&
        !_away &&
        p.currentAnalysisResult != null &&
        !identical(_seenResult, p.currentAnalysisResult)) {
      _seenResult = p.currentAnalysisResult;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _result(p);
      });
    }
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.popup ? 'AI 골프 코치' : '골프 코치'),
          automaticallyImplyLeading: false,
          actions: [
            if (!widget.popup)
              IconButton(
                  tooltip: 'AI 코치와 대화',
                  icon: const CoachIcon(),
                  onPressed: () => showCoachPopup(context)),
            if (widget.popup)
              IconButton(
                  tooltip: '대화 닫기',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            IconButton(
                tooltip: '설정',
                onPressed: _working ? null : () => _send('설정'),
                icon: const Icon(Icons.settings_outlined))
          ]),
      body: SafeArea(
          child: Column(children: [
        Expanded(
            child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final m = _messages[index];
                  if (index == 0 && !widget.popup) {
                    return AssistantWelcome(busy: _working, onAction: _send);
                  }
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Align(
                          alignment: m.user
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                              constraints: const BoxConstraints(maxWidth: 620),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                  color: m.user
                                      ? colors.primaryContainer
                                      : colors.surfaceVariant.withOpacity(.45),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!m.user) ...[
                                      Text('골프 코치',
                                          style: TextStyle(
                                              color: colors.primary,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12)),
                                      const SizedBox(height: 10)
                                    ],
                                    SelectableText(m.text,
                                        style: TextStyle(
                                            height: 1.65,
                                            color: m.user
                                                ? colors.onPrimaryContainer
                                                : colors.onSurface)),
                                    if (m.resultId != null &&
                                        m.resultId == p.currentSwing?.swingId &&
                                        p.currentPoseReport != null)
                                      ExpansionTile(
                                          tilePadding: EdgeInsets.zero,
                                          title: const Text('내 동작을 이미지로 보기'),
                                          children: [
                                            MotionVisualCard(
                                                key: ValueKey(
                                                    '${m.resultId}-$index'),
                                                videoPath:
                                                    p.currentSwing!.videoPath,
                                                report: p.currentPoseReport!,
                                                leadSide: p.currentSwing!
                                                            .handedness ==
                                                        Handedness.right
                                                    ? 'left'
                                                    : 'right'),
                                            if (p.currentShotMeasurement !=
                                                null)
                                              ShotVisualCard(
                                                  shot: p
                                                      .currentShotMeasurement!),
                                          ]),
                                    if (m.actions.isNotEmpty) ...[
                                      const SizedBox(height: 14),
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: m.actions
                                              .map((label) => ActionChip(
                                                  label: Text(label),
                                                  onPressed: _working
                                                      ? null
                                                      : () {
                                                          if (label ==
                                                              '결과 펼쳐 보기') {
                                                            _open(
                                                                const AnalysisResultScreen());
                                                          } else {
                                                            _send(label);
                                                          }
                                                        }))
                                              .toList())
                                    ],
                                  ]))));
                })),
        if (_working)
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: LinearProgressIndicator()),
        if (_listening)
          const Padding(
              padding: EdgeInsets.all(8),
              child: Text('듣고 있어요. 원하는 기능이나 질문을 말씀하세요.')),
        if (widget.popup)
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                IconButton(
                    tooltip: _listening ? '음성 입력 중지' : '음성으로 말하기',
                    onPressed:
                        _working || widget.cameraContext ? null : _listen,
                    icon: Icon(_listening ? Icons.stop_circle : Icons.mic_none),
                    color: colors.primary),
                Expanded(
                    child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        decoration: const InputDecoration(
                            hintText: '무엇을 도와드릴까요?',
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(24)))))),
                IconButton(
                    tooltip: '보내기',
                    onPressed: _working ? null : () => _send(_input.text),
                    icon: const Icon(Icons.arrow_upward),
                    color: colors.primary),
              ])),
      ])),
    );
  }
}
