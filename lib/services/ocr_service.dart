import '../models/shot_measurement_model.dart';

class OcrService {
  static ShotMeasurementModel parseOcrText(String rawText, String swingId) {
    final labels = <String, RegExp>{
      'ball': RegExp(r'볼\s*(?:스피드|속도)|ball\s*speed|b\.s\b', caseSensitive: false),
      'club': RegExp(r'(?:클럽|헤드)\s*(?:스피드|속도)|(?:club|head)\s*speed|[ch]\.s\b', caseSensitive: false),
      'carry': RegExp(r'캐리|carry', caseSensitive: false),
      'total': RegExp(r'total(?:\s*distance)?|총\s*(?:비)?거리|전체\s*비거리|^비거리', caseSensitive: false),
      'launch': RegExp(r'launch\s*angle|발사\s*각(?:도)?', caseSensitive: false),
      'back': RegExp(r'back\s*spin|백\s*스핀', caseSensitive: false),
      'side': RegExp(r'side\s*spin|사이드\s*스핀', caseSensitive: false),
    };
    final lines = rawText.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final number = RegExp(r'[+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?');
    final values = <String, double?>{};
    for (final label in labels.entries) {
      final candidates = <double>[];
      for (var i = 0; i < lines.length; i++) {
        if (!label.value.hasMatch(lines[i])) continue;
        // A row containing multiple labels is ambiguous; do not borrow a neighbour's value.
        if (labels.values.where((p) => p.hasMatch(lines[i])).length != 1) continue;
        var text = lines[i];
        if (!number.hasMatch(text) && i+1 < lines.length && !labels.values.any((p) => p.hasMatch(lines[i+1]))) text += ' ${lines[i+1]}';
        final matches = number.allMatches(text).toList();
        if (matches.length != 1) continue;
        var value = double.tryParse(matches.single.group(0)!.replaceAll(',', ''));
        if (value == null || !value.isFinite) continue;
        final units = text.toLowerCase();
        if (label.key == 'ball' || label.key == 'club') {
          if (RegExp(r'\bmph\b').hasMatch(units)) value *= .44704;
          else if (RegExp(r'km\s*/\s*h|kmh|kph').hasMatch(units)) value /= 3.6;
          else if (!RegExp(r'\bm\s*/\s*s\b').hasMatch(units)) continue;
          if (value <= 0 || value > 150) continue;
        } else if (label.key == 'carry' || label.key == 'total') {
          if (RegExp(r'\byd\b|\byards?\b|야드').hasMatch(units)) value *= .9144;
          else if (!RegExp(r'\bm\b|미터').hasMatch(units)) continue;
          if (value < 0 || value > 600) continue;
        } else if (label.key == 'launch') {
          if (value < -90 || value > 90) continue;
        } else if (label.key == 'back') {
          if (value < 0 || value > 20000) continue;
        } else if (value.abs() > 20000) continue;
        candidates.add(value);
      }
      if (candidates.isNotEmpty && candidates.every((n) => (n-candidates.first).abs() < .001)) values[label.key] = candidates.first;
    }
    return ShotMeasurementModel(measurementId: 'ocr_${DateTime.now().microsecondsSinceEpoch}', swingId: swingId,
      ballSpeedMs: values['ball'], clubSpeedMs: values['club'], carryDistanceMeters: values['carry'],
      totalDistanceMeters: values['total'], launchAngleDeg: values['launch'], backSpinRpm: values['back'],
      sideSpinRpm: values['side'], ocrStatus: OcrStatus.pending);
  }
}
