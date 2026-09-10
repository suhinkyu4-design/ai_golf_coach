import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/golf_widgets.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/shot_measurement_model.dart';
import '../providers/swing_provider.dart';
import '../services/ocr_service.dart';
import 'analysis_result_screen.dart';

class OcrInputScreen extends StatefulWidget {
  const OcrInputScreen({super.key});
  @override
  State<OcrInputScreen> createState() => _OcrInputScreenState();
}
class _OcrInputScreenState extends State<OcrInputScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = List.generate(7, (_) => TextEditingController());
  bool _busy = false;
  String? _image, _error;
  String _raw = '';
  TextRecognitionScript _script = TextRecognitionScript.latin;
  static const _labels = ['볼스피드 (m/s)', '클럽스피드 (m/s)', '캐리 (m)',
    '총거리 (m)', '발사각 (°)', '백스핀 (rpm)', '사이드스핀 (rpm)'];

  @override
  void initState() {
    super.initState();
    final shot = context.read<SwingProvider>().currentShotMeasurement;
    if (shot != null) { _fill(shot); _image = shot.imagePath; }
  }
  void _fill(ShotMeasurementModel shot) {
    final values = [shot.ballSpeedMs, shot.clubSpeedMs, shot.carryDistanceMeters,
      shot.totalDistanceMeters, shot.launchAngleDeg, shot.backSpinRpm, shot.sideSpinRpm];
    for (int i = 0; i < _fields.length; i++) {
      _fields[i].text = values[i]?.toStringAsFixed(3) ?? '';
    }
  }
  double? _value(int i) => double.tryParse(_fields[i].text.trim().replaceAll(',', ''));

  Future<void> _scan() async {
    setState(() { _busy = true; _error = null; });
    TextRecognizer? recognizer;
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      final provider = context.read<SwingProvider>();
      final swing = provider.currentSwing;
      if (swing == null) throw StateError('선택된 스윙이 없습니다.');
      provider.clearShotMeasurement();
      setState(() {
        _image = image.path; _raw = '';
        for (final c in _fields) { c.clear(); }
      });
      recognizer = TextRecognizer(script: _script);
      final recognized = await recognizer.processImage(InputImage.fromFilePath(image.path));
      if (!mounted) return;
      final candidate = OcrService.parseOcrText(recognized.text, swing.swingId);
      setState(() {
        _raw = recognized.text; _fill(candidate);
        if (_raw.trim().isEmpty) _error = '글자를 찾지 못했습니다. 사진을 다시 선택하거나 직접 입력하세요.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'OCR 인식 실패. 직접 입력할 수 있습니다.\n$e');
    } finally {
      try { await recognizer?.close(); } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _next(bool skip) async {
    if (_busy) return;
    final provider = context.read<SwingProvider>();
    final swing = provider.currentSwing;
    if (swing == null) { setState(() => _error = '먼저 스윙 영상을 선택하세요.'); return; }
    if (!skip) {
      if (!_form.currentState!.validate()) return;
      if (_fields.every((c) => c.text.trim().isEmpty)) {
        setState(() => _error = '한 항목 이상 입력하거나 샷 기록 없이 진행하세요.'); return;
      }
      if (_value(2) != null && _value(3) != null && _value(2)! > _value(3)!) {
        setState(() => _error = '캐리가 총거리보다 큽니다. 항목과 단위를 다시 확인하세요.'); return;
      }
    }
    setState(() { _busy = true; _error = null; });
    try {
      if (skip) { provider.clearShotMeasurement(); } else {
        provider.attachShotMeasurement(ShotMeasurementModel(
          measurementId: 'shot_${DateTime.now().microsecondsSinceEpoch}',
          swingId: swing.swingId, imagePath: _image,
          ballSpeedMs: _value(0), clubSpeedMs: _value(1), carryDistanceMeters: _value(2),
          totalDistanceMeters: _value(3), launchAngleDeg: _value(4),
          backSpinRpm: _value(5), sideSpinRpm: _value(6), ocrStatus: OcrStatus.userConfirmed,
        ));
      }
      await provider.runAnalysis();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalysisResultScreen()));
    } catch (e) {
      if (mounted) setState(() => _error = '결과 생성 실패: $e');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  void dispose() { for (final c in _fields) { c.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('스크린 샷 기록 확인')),
    body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(20), children: [
      const GolfStepHeader(step: 3, title: '샷의 숫자를 더하세요', description: '같은 스윙의 결과 캡처를 선택하고, 인식값을 원본과 대조하세요.'),
      DropdownButton<TextRecognitionScript>(value: _script,
        items: const [
          DropdownMenuItem(value: TextRecognitionScript.latin, child: Text('영문·숫자 인식')),
          DropdownMenuItem(value: TextRecognitionScript.korean, child: Text('한글 인식 (추가 설정 필요)')),
        ], onChanged: _busy ? null : (v) => setState(() => _script = v!)),
      OutlinedButton.icon(onPressed: _busy ? null : _scan,
        icon: const Icon(Icons.document_scanner), label: const Text('캡처 이미지 선택 · OCR')),
      if (_image != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
        child: Image.file(File(_image!), height: 220, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Text('원본 이미지를 열 수 없습니다.'))),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(8),
        child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent))),
      const Text('입력 단위: 속도 m/s · 거리 m. mph는 ×0.44704, km/h는 ÷3.6, yd는 ×0.9144로 변환하세요. 단위가 불명확한 OCR 값은 비워 둡니다.'),
      for (int i = 0; i < _fields.length; i++) Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(controller: _fields[i], enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(labelText: _labels[i], hintText: '미입력 가능'),
          validator: (text) {
            if (text == null || text.trim().isEmpty) return null;
            final n = _value(i);
            if (n == null || !n.isFinite) return '올바른 숫자를 입력하세요.';
            if (i < 2 && n <= 0) return '속도는 0보다 커야 합니다.';
            if ((i == 2 || i == 3 || i == 5) && n < 0) return '0 이상 입력하세요.';
            if (i == 4 && (n < -90 || n > 90)) return '발사각과 단위를 확인하세요.';
            return null;
          },
        )),
      if (_raw.isNotEmpty) ExpansionTile(title: const Text('인식된 원문'), children: [SelectableText(_raw)]),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _busy ? null : () => _next(false), child: const Text('수치·단위·같은 샷 여부 확인 후 결과 보기')),
      TextButton(onPressed: _busy ? null : () => _next(true), child: const Text('샷 기록 없이 결과 보기')),
    ])),
  );
}
