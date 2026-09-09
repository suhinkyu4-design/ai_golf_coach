import 'dart:math';
import '../models/shot_measurement_model.dart';

class OcrService {
  /// Parses raw text blocks extracted by ML Kit OCR into structured shot measurements
  static ShotMeasurementModel parseOcrText(String rawText, String swingId) {
    double? ballSpeed;
    double? clubSpeed;
    double? carry;
    double? total;
    double? launchAngle;
    double? backSpin;

    final lines = rawText.split('\n');

    for (String line in lines) {
      final cleanLine = line.toLowerCase().trim();

      // Ball speed parsing
      if (cleanLine.contains('ball') || cleanLine.contains('볼스피드') || cleanLine.contains('b.s')) {
        final val = _extractFirstNumber(cleanLine);
        if (val != null) {
          ballSpeed = cleanLine.contains('mph') ? val * 0.44704 : val; // Convert mph to m/s if needed
        }
      }

      // Club speed parsing
      if (cleanLine.contains('club') || cleanLine.contains('head') || cleanLine.contains('헤드') || cleanLine.contains('c.s')) {
        final val = _extractFirstNumber(cleanLine);
        if (val != null) {
          clubSpeed = cleanLine.contains('mph') ? val * 0.44704 : val;
        }
      }

      // Carry distance parsing
      if (cleanLine.contains('carry') || cleanLine.contains('캐리')) {
        final val = _extractFirstNumber(cleanLine);
        if (val != null) {
          carry = cleanLine.contains('yd') || cleanLine.contains('yard') ? val * 0.9144 : val;
        }
      }

      // Spin parsing
      if (cleanLine.contains('spin') || cleanLine.contains('스핀')) {
        final val = _extractFirstNumber(cleanLine);
        if (val != null) backSpin = val;
      }
    }

    return ShotMeasurementModel(
      measurementId: 'ocr_${DateTime.now().millisecondsSinceEpoch}',
      swingId: swingId,
      ballSpeedMs: ballSpeed,
      clubSpeedMs: clubSpeed,
      carryDistanceMeters: carry,
      totalDistanceMeters: total,
      launchAngleDeg: launchAngle,
      backSpinRpm: backSpin,
      ocrStatus: OcrStatus.pending,
    );
  }

  static double? _extractFirstNumber(String text) {
    final RegExp regExp = RegExp(r'(\d+(\.\d+)?)');
    final match = regExp.firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(0)!);
    }
    return null;
  }
}
