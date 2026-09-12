import '../models/shot_measurement_model.dart';

class OcrService {
  static final _labels = <String, RegExp>{
    'ball': RegExp(r'ball\s*speed|볼\s*(?:스피드|속도)|b\.s\b', caseSensitive: false),
    'club': RegExp(r'(?:club|head)\s*speed|(?:클럽|헤드)\s*(?:스피드|속도)|c\.s\b|h\.s\b', caseSensitive: false),
    'carry': RegExp(r'carry|캐리', caseSensitive: false),
    'total': RegExp(r'total(?:\s*distance)?|총\s*(?:비)?거리|전체\s*비거리|\b비거리\b', caseSensitive: false),
    'launch': RegExp(r'launch\s*angle|발사\s*각(?:도)?', caseSensitive: false),
    'back': RegExp(r'back\s*spin|백\s*스핀', caseSensitive: false),
    'side': RegExp(r'side\s*spin|사이드\s*스핀', caseSensitive: false),
  };

  static ShotMeasurementModel parseOcrText(String rawText, String swingId) {
    final lines = rawText.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final values = <String, double>{};
    final numberRegExp = RegExp(r'[+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?');

    // 1단계: 라인별 Key-Value 단일 패턴 추출
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      for (final entry in _labels.entries) {
        final key = entry.key;
        if (values.containsKey(key)) continue;

        if (entry.value.hasMatch(line)) {
          final match = entry.value.firstMatch(line)!;
          final tail = line.substring(match.end).trim();
          var numMatch = numberRegExp.firstMatch(tail);

          String searchArea = line;
          if (numMatch == null && (i + 1) < lines.length) {
            final nextLine = lines[i + 1];
            if (!_labels.values.any((r) => r.hasMatch(nextLine))) {
              numMatch = numberRegExp.firstMatch(nextLine);
              searchArea = nextLine;
            }
          }

          if (numMatch != null) {
            final n = double.tryParse(numMatch.group(0)!.replaceAll(',', ''));
            if (n != null && n.isFinite) {
              final unitArea = searchArea.toLowerCase().replaceAll(' ', '');
              double? value;

              if (key == 'ball' || key == 'club') {
                if (n > 0) {
                  if (unitArea.contains('mph')) {
                    value = n * 0.44704;
                  } else if (unitArea.contains('km/h') || unitArea.contains('kph')) {
                    value = n / 3.6;
                  } else {
                    value = n;
                  }
                }
              } else if (key == 'carry' || key == 'total') {
                if (n >= 0) {
                  if (unitArea.contains('yd') || unitArea.contains('yard')) {
                    value = n * 0.9144;
                  } else {
                    value = n;
                  }
                }
              } else if (key == 'launch') {
                if (n >= -90 && n <= 90) value = n;
              } else if (key == 'back' || key == 'side') {
                value = n;
              }

              if (value != null) values[key] = value;
            }
          }
        }
      }
    }

    // 2단계: 골프존/스마트골프 등 다중 컬럼/그리드 패턴 매칭 (라인 L: 라벨들, 라인 L+1: 숫자들)
    for (int i = 0; i < lines.length - 1; i++) {
      final labelLine = lines[i];
      final valueLine = lines[i + 1];

      final foundLabels = <_LabelPosition>[];
      for (final entry in _labels.entries) {
        final key = entry.key;
        if (values.containsKey(key)) continue;

        final matches = entry.value.allMatches(labelLine);
        for (final m in matches) {
          foundLabels.add(_LabelPosition(key: key, start: m.start));
        }
      }

      if (foundLabels.isEmpty) continue;
      foundLabels.sort((a, b) => a.start.compareTo(b.start));

      final numMatches = numberRegExp.allMatches(valueLine).toList();
      if (numMatches.isNotEmpty) {
        for (int k = 0; k < foundLabels.length; k++) {
          final labelInfo = foundLabels[k];
          if (values.containsKey(labelInfo.key)) continue;

          if (k < numMatches.length) {
            final n = double.tryParse(numMatches[k].group(0)!.replaceAll(',', ''));
            if (n != null && n.isFinite) {
              double? value;
              final key = labelInfo.key;

              if (key == 'ball' || key == 'club') {
                if (n > 0) value = n;
              } else if (key == 'carry' || key == 'total') {
                if (n >= 0) value = n;
              } else if (key == 'launch') {
                if (n >= -90 && n <= 90) value = n;
              } else if (key == 'back' || key == 'side') {
                value = n;
              }

              if (value != null) values[key] = value;
            }
          }
        }
      }
    }

    return ShotMeasurementModel(
      measurementId: 'ocr_${DateTime.now().microsecondsSinceEpoch}',
      swingId: swingId,
      ballSpeedMs: values['ball'],
      clubSpeedMs: values['club'],
      carryDistanceMeters: values['carry'],
      totalDistanceMeters: values['total'],
      launchAngleDeg: values['launch'],
      backSpinRpm: values['back'],
      sideSpinRpm: values['side'],
      ocrStatus: OcrStatus.pending,
    );
  }
}

class _LabelPosition {
  final String key;
  final int start;
  _LabelPosition({required this.key, required this.start});
}
