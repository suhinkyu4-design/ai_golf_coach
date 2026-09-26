import '../widgets/coach_app_bar.dart';
import '../services/assistant_operation_log.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/swing_model.dart';
import '../providers/experience_settings.dart';
import '../providers/swing_provider.dart';
import '../services/gallery_pose_service.dart';
import 'pose_trimming_screen.dart';
import 'appearance_settings_screen.dart';
import 'live_camera_recording_screen.dart';

class VideoInputScreen extends StatefulWidget {
  final String? initialAction;
  const VideoInputScreen({super.key, this.initialAction});
  @override
  State<VideoInputScreen> createState() => _VideoInputScreenState();
}
class _VideoInputScreenState extends State<VideoInputScreen> {
  @override
  void initState() {
    super.initState();
    final prefs=context.read<ExperienceSettings>();
    _view=prefs.view; _hand=prefs.hand; _club=prefs.club;
    if(widget.initialAction!=null) WidgetsBinding.instance.addPostFrameCallback((_) async {
      if(!mounted)return;
      if(widget.initialAction=='camera') { await _open(true); } else { await _pick(); }
      if(mounted && ModalRoute.of(context)?.isCurrent==true) Navigator.pop(context);
    });
  }
  SwingView _view = SwingView.rear;
  Handedness _hand = Handedness.right;
  String _club = 'unknown';
  String? _video;
  bool _busy = false;
  bool _settingsOpen = false;

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).colorScheme.surface,
      checkmarkColor: Theme.of(context).colorScheme.onPrimary,
      side: BorderSide(
        color: selected ? Theme.of(context).colorScheme.primary : Color(0xFF40534A),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Future<void> _pick() async {
    AssistantOperationLog.current.begin();
    var picked = false;
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      if (!await File(file.path).exists()) throw StateError('영상 파일을 찾지 못했습니다.');
      if (mounted) { setState(() => _video = file.path); picked = true; }
    } catch (e) {
      AssistantOperationLog.current.fail('selection', e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('영상 선택 실패: $e')));
    } finally { if (mounted) setState(() => _busy = false); }
    if (picked && mounted) await _open(false);
  }

  Future<bool> _showSettings() async {
    if (_settingsOpen) return false;
    _settingsOpen = true;
    var draftView = _view;
    var draftHand = _hand;
    var draftClub = _club;
    try {
      final confirmed = await showModalBottomSheet<bool>(
        context: context, isScrollControlled: true, useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface, showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetContext) => StatefulBuilder(builder: (context, update) =>
          SingleChildScrollView(padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: SafeArea(top: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
                Row(children: [Expanded(child: Text('스윙 설정',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
                  IconButton(tooltip: '닫기', icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetContext, false))]),
                Text('필요한 항목만 변경하세요. 기본은 후방·오른손입니다.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                SizedBox(height: 24),
                ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.palette_outlined), title: Text('화면 테마 · 음성 촬영'), trailing: Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()))),
                Text('촬영 방향'), SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  _buildChip(label: '정면', selected: draftView == SwingView.faceOn,
                    onSelected: () => update(() => draftView = SwingView.faceOn)),
                  _buildChip(label: '골퍼 뒤에서 촬영', selected: draftView == SwingView.rear,
                    onSelected: () => update(() => draftView = SwingView.rear)),
                ]),
                SizedBox(height: 20), Text('주사용 손'), SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  _buildChip(label: '오른손', selected: draftHand == Handedness.right,
                    onSelected: () => update(() => draftHand = Handedness.right)),
                  _buildChip(label: '왼손', selected: draftHand == Handedness.left,
                    onSelected: () => update(() => draftHand = Handedness.left)),
                ]),
                SizedBox(height: 20),
                DropdownButtonFormField<String>(value: draftClub, isExpanded: true,
                  decoration: InputDecoration(labelText: '클럽'),
                  items: ['unknown', 'Driver', '7i']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c == 'unknown' ? '미지정 · 공통 동작 분석' : c == 'Driver' ? '드라이버' : '7번 아이언'))).toList(),
                  onChanged: (v) { if (v != null) update(() => draftClub = v); }),
                SizedBox(height: 28),
                ElevatedButton(onPressed: () => Navigator.pop(sheetContext, true),
                  child: Text('설정 저장')),
              ])),
          )),
      );
      if (confirmed != true || !mounted) return false;
      await context.read<ExperienceSettings>().select(view:draftView,hand:draftHand,club:draftClub);
      if(!mounted)return false;
      setState(() { _view = draftView; _hand = draftHand; _club = draftClub; });
      return true;
    } finally { _settingsOpen = false; }
  }

  Future<void> _open(bool camera) async {
    if (_busy || _settingsOpen || (!camera && _video == null)) return;
    setState(() => _busy = true);
    try {
      if (!mounted) return;
      await _openConfigured(camera);
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _openConfigured(bool camera) async {

    if (camera) {
      final recorded = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => LiveCameraRecordingScreen()));
      if (!mounted || recorded == null) return;
      setState(() => _video = recorded);
    }
    if (_video == null) return;

    {
      int currentStage = 0;
      final elapsed = Stopwatch()..start();
      Timer? ticker;
      bool dialogActive = true;
      const stages = ['분석할 영상 장면 준비', '사람과 관절 인식', '백스윙·타격 구간 탐색',
        '타격 주변 장면 정밀 확인', '공 이동·클럽 궤적 확인', '영상 분석 기록 정리'];
      String currentStatus = '갤러리 영상 관절 스캔 준비 중…';
      void Function(void Function())? refreshDialog;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            refreshDialog = setDialogState;
            return PopScope(canPop: false, child: AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Row(
                children: [
                  Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
                  SizedBox(width: 8),
                  Text('스윙 영상 분석 중', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(currentStatus, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
                  SizedBox(height: 12),
                  LinearProgressIndicator(color: Theme.of(context).colorScheme.primary, backgroundColor: Theme.of(context).dividerColor),
                  SizedBox(height: 8),
                  Text('경과 시간 ${elapsed.elapsed.inMinutes}분 ${elapsed.elapsed.inSeconds % 60}초',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                  SizedBox(height: 20),
                  for (var index=0;index<stages.length;index++)
                    Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Row(children: [
                      Icon(index<currentStage ? Icons.check_circle_outline :
                        index==currentStage ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: index<=currentStage ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                      SizedBox(width: 10),
                      Expanded(child: Text(stages[index], style: TextStyle(fontSize: 13,
                        color: index<=currentStage ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: index==currentStage ? FontWeight.bold : FontWeight.normal))),
                    ])),
                  SizedBox(height: 16),
                  Text('휴대폰에서 직접 분석 중입니다.\n영상이 길면 장면 준비와 관절 인식에 시간이 걸릴 수 있어요.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant,fontSize: 12)),
                ],
              )),
            ));
          },
        ),
      ).whenComplete(() { dialogActive=false; ticker?.cancel(); });
      ticker=Timer.periodic(Duration(seconds: 1), (_) {
        if(mounted && dialogActive)refreshDialog?.call(() {});
      });
      bool analyzed = false;
      try {

      analyzed = await GalleryPoseService.analyzeGalleryVideo(
        videoPath: _video!,
        onStage: (stage) {
          currentStage=stage;
          if(mounted && dialogActive)refreshDialog?.call(() {});
        },
        onProgress: (p, s) {
          currentStatus = s;
          if(mounted && dialogActive)refreshDialog?.call(() {});
        },
      );

      } catch (e) {
        AssistantOperationLog.current.fail('scan', e);
        rethrow;
      } finally {
        ticker?.cancel();
        elapsed.stop();
        if (mounted && dialogActive) Navigator.of(context, rootNavigator: true).pop();
        dialogActive=false;
      }
      if (analyzed) { AssistantOperationLog.current.success('scan'); }
      else { AssistantOperationLog.current.fail('scan', StateError('scan_failed')); }
      if (mounted && !analyzed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('관절 스캔에 실패했습니다. 영상은 열리지만 자동 후보 시각 정확도는 낮을 수 있습니다.')),
        );
      }
    }

    if (!mounted) return;
    context.read<SwingProvider>().createNewSwing(
      videoPath: _video!,
      view: _view,
      handedness: _hand,
      club: _club,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PoseTrimmingScreen(autoAnalyze: true),
      ),
    );
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: CoachAppBar(title: Text('스윙 영상 준비'), actions: [
      IconButton(tooltip: '설정', onPressed: _busy ? null : () => _showSettings(),
        icon: Icon(Icons.settings_outlined)),
    ]),
    bottomNavigationBar: _video == null ? null : SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: ElevatedButton(onPressed: _busy ? null : () => _open(false),
        child: Text(_busy ? '준비 중…' : '이 영상으로 계속')))),
    body: ListView(padding: EdgeInsets.fromLTRB(24, 32, 24, 24), children: [
      Text('스윙을 남겨보세요', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
      SizedBox(height: 12),
      Text('직접 촬영하거나 저장된 영상을 가져오세요.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      SizedBox(height: 32),
      SizedBox(height: 48),
      Icon(Icons.sports_golf_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
      SizedBox(height: 32),
      ElevatedButton.icon(onPressed: _busy ? null : () => _open(true),
        icon: Icon(Icons.videocam_outlined), label: Text('새 영상 촬영')),
      SizedBox(height: 16),
      OutlinedButton.icon(onPressed: _busy ? null : _pick,
        icon: Icon(Icons.video_library_outlined),
        label: Text(_busy ? '준비 중…' : _video == null ? '갤러리에서 가져오기' : '다른 영상 선택')),
      SizedBox(height: 24),
      if (_video != null) ListTile(contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
        title: Text('영상이 준비됐어요'),
        subtitle: Text(_video!.split(RegExp(r'[/\\]')).last, maxLines: 1, overflow: TextOverflow.ellipsis)),
      SizedBox(height: 16),
      Text('스크린을 바라보는 골퍼 뒤에서, 머리부터 발끝까지 담아 주세요.',
        textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
    ]),
  );
}
