import '../widgets/coach_app_bar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../services/on_device_slm_service.dart';
import '../services/assistant_model_service.dart';

class SlmSettingsScreen extends StatefulWidget {
  const SlmSettingsScreen({super.key});
  @override
  State<SlmSettingsScreen> createState() => _SlmSettingsScreenState();
}

class _SlmSettingsScreenState extends State<SlmSettingsScreen> {
  bool _ready = false, _busy = false;
  bool _assistantReady = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ready = await OnDeviceSlmService.isReady();
    final assistantReady = await AssistantModelService.isReady();
    if (mounted)
      setState(() {
        _ready = ready;
        _assistantReady = assistantReady;
      });
  }

  Future<void> _importAssistant() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final chosen = await FilePicker.platform
          .pickFiles(type: FileType.any, allowMultiple: false, withData: false);
      final path = chosen?.files.single.path;
      if (path != null) {
        await AssistantModelService.install(path);
        await _refresh();
      }
    } catch (_) {
      if (mounted)
        setState(() => _error =
            '대화 모델 등록에 실패했습니다. golf_assistant_v1_q8_0.gguf 파일을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final chosen = await FilePicker.platform
          .pickFiles(type: FileType.any, allowMultiple: false, withData: false);
      final path = chosen?.files.single.path;
      if (path != null) {
        await OnDeviceSlmService.installModel(path);
        await _refresh();
      }
    } catch (_) {
      if (mounted)
        setState(
            () => _error = '모델 등록에 실패했습니다. golf_slm_q8_0.gguf 원본 파일을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _describe() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SwingProvider>().runAnalysis();
    } catch (_) {
      if (mounted) setState(() => _error = '분석을 완료하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: CoachAppBar(title: const Text('기기 내 설명 모델')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(28), children: [
          Text(_assistantReady ? '대화 모델 준비 완료' : '대화 모델',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Text('이해하지 못한 요청에 관련 기능을 제안합니다. 제안된 버튼을 선택하면 실행됩니다.'),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: _busy ? null : _importAssistant,
              child: Text(_assistantReady ? '대화 모델 다시 등록' : '대화 모델 파일 선택')),
          const Divider(height: 40),
          Text(_ready ? '설명 모델 준비 완료' : '설명 모델을 등록해 주세요',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          const Text(
              '인터넷 연결 없이 자세 수치 한 가지를 짧게 설명합니다. 현재는 실험 기능이며 개인별 자세교정 처방은 제공하지 않습니다.'),
          const SizedBox(height: 24),
          const Text(
              'golf_slm_q8_0.gguf · 약 639MB\nGoogle Drive에서 받은 파일을 한 번 등록하면 됩니다.'),
          const SizedBox(height: 24),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_error!)),
          if (!_busy)
            OutlinedButton(
                onPressed: _import,
                child: Text(_ready ? '모델 파일 다시 등록' : '모델 파일 선택')),
          if (_ready &&
              !_busy &&
              context.watch<SwingProvider>().currentSwing != null)
            FilledButton(
                onPressed: _describe, child: const Text('현재 스윙 다시 설명')),
        ])),
      );
}
