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

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      for (final entry in _labels.entries) {
        final key = entry.key;
        if (values.containsKey(key)) continue;

        if (entry.value.hasMatch(line)) {
          String searchArea = line;
          var match = numberRegExp.firstMatch(searchArea);

          int targetLineIndex = i;
          if (match == null) {
            for (int offset = 1; offset <= 2 && (i + offset) < lines.length; offset++) {
              final nextLine = lines[i + offset];
              if (_labels.values.any((r) => r.hasMatch(nextLine))) break;
              match = numberRegExp.firstMatch(nextLine);
              if (match != null) {
                searchArea = nextLine;
                targetLineIndex = i + offset;
                break;
              }
            }
          }

          if (match != null) {
            final numStr = match.group(0)!.replaceAll(',', '');
            final n = double.tryParse(numStr);
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

              if (value != null) {
                values[key] = value;
              }
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
