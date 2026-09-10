import '../models/shot_measurement_model.dart';

/// Conservative parser. Missing units / ambiguous or duplicate labels stay blank.
/// OCR candidates are always pending until the user confirms the form.
class OcrService {
  static final _labels = <String, RegExp>{
    'ball': RegExp(r'ball\s*speed|볼\s*(?:스피드|속도)|b\.s\b', caseSensitive: false),
    'club': RegExp(r'(?:club|head)\s*speed|(?:클럽|헤드)\s*(?:스피드|속도)|c\.s\b', caseSensitive: false),
    'carry': RegExp(r'carry|캐리', caseSensitive: false),
    'total': RegExp(r'total(?:\s*distance)?|총\s*거리|총\s*비거리', caseSensitive: false),
    'launch': RegExp(r'launch\s*angle|발사각|발사\s*각도', caseSensitive: false),
    'back': RegExp(r'back\s*spin|백\s*스핀', caseSensitive: false),
    'side': RegExp(r'side\s*spin|사이드\s*스핀', caseSensitive: false),
  };
  static ShotMeasurementModel parseOcrText(String rawText, String swingId) {
    final lines = rawText.split('\n');
    final values = <String, double>{};
    final seen = <String>{};
    final duplicate = <String>{};
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final hits = _labels.entries.where((e) => e.value.hasMatch(line)).toList();
      if (hits.length != 1) continue;
      final hit = hits.single;
      if (!seen.add(hit.key)) duplicate.add(hit.key);
      final match = hit.value.firstMatch(line)!;
      var tail = line.substring(match.end).trim();
      if (tail.replaceAll(RegExp(r'[:：\s]'), '').isEmpty && i + 1 < lines.length &&
          !_labels.values.any((r) => r.hasMatch(lines[i + 1]))) tail = lines[i + 1].trim();
      final parsed = RegExp(r'^[:：\s]*([+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?)\s*(.*?)\s*$').firstMatch(tail);
      if (parsed == null) continue;
      final n = double.tryParse(parsed.group(1)!.replaceAll(',', ''));
      if (n == null || !n.isFinite) continue;
      final unit = parsed.group(2)!.toLowerCase().replaceAll(' ', '');
      double? value;
      if (hit.key == 'ball' || hit.key == 'club') {
        if (n <= 0) continue;
        if (unit == 'm/s' || unit == 'mps') value = n;
        if (unit == 'mph') value = n * .44704;
        if (unit == 'km/h' || unit == 'kph') value = n / 3.6;
      } else if (hit.key == 'carry' || hit.key == 'total') {
        if (n < 0) continue;
        if (unit == 'm' || unit == 'meter' || unit == 'meters') value = n;
        if (unit == 'yd' || unit == 'yards' || unit == 'yard') value = n * .9144;
      } else if (hit.key == 'launch') {
        if (unit == '°' || unit == 'deg' || unit == '도') value = n;
      } else if (unit == 'rpm' && (hit.key == 'side' || n >= 0)) {
        value = n;
      }
      if (value != null) values[hit.key] = value;
    }
    for (final key in duplicate) { values.remove(key); }
    return ShotMeasurementModel(measurementId: 'ocr_${DateTime.now().microsecondsSinceEpoch}',
      swingId: swingId, ballSpeedMs: values['ball'], clubSpeedMs: values['club'],
      carryDistanceMeters: values['carry'], totalDistanceMeters: values['total'],
      launchAngleDeg: values['launch'], backSpinRpm: values['back'], sideSpinRpm: values['side'],
      ocrStatus: OcrStatus.pending);
  }
}
