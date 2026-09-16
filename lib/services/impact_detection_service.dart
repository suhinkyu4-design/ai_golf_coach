import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

class ImpactDetectionResult {
  final int tMs;
  final double confidence;
  final double ballX;
  final double ballY;
  final String method;
  final List<int> candidateTimesMs;

  const ImpactDetectionResult({
    required this.tMs,
    required this.confidence,
    required this.ballX,
    required this.ballY,
    required this.method,
    required this.candidateTimesMs,
  });

  Map<String, dynamic> toJson() => {
        't_ms': tMs,
        'confidence': confidence,
        'ball_x': ballX,
        'ball_y': ballY,
        'method': method,
        'candidate_times_ms': candidateTimesMs,
      };
}

class ImpactDetectionService {
  static Future<ImpactDetectionResult?> detectImpact({
    required List<Map<String, dynamic>> frames,
    required List<Map<String, dynamic>> samples,
  }) async {
    if (frames.length < 5 || samples.length < 5) return null;
    final sortedFrames = List<Map<String, dynamic>>.from(frames)
      ..sort((a, b) => (a['t_ms'] as int).compareTo(b['t_ms'] as int));
    final sortedSamples = List<Map<String, dynamic>>.from(samples)
      ..sort((a, b) => (a['t_ms'] as int).compareTo(b['t_ms'] as int));
    final usableCount = math.min(sortedFrames.length, sortedSamples.length);
    if (usableCount < 5) return null;

    final wristXs = <double>[];
    final wristYs = <double>[];
    for (int i = 0; i < usableCount; i++) {
      final landmarks = sortedSamples[i]['landmarks'] as List<dynamic>? ?? const [];
      final wristX = _averageLandmarkAxis(landmarks, const {'leftWrist', 'rightWrist'}, 'x');
      final wristY = _averageLandmarkAxis(landmarks, const {'leftWrist', 'rightWrist'}, 'y');
      if (wristX == null || wristY == null) return null;
      wristXs.add(wristX);
      wristYs.add(wristY);
    }

    final smoothXs = _smoothSeries(wristXs);
    final smoothYs = _smoothSeries(wristYs);
    final addressIndex = _findAddressIndex(smoothYs);
    final topIndex = _findTopIndex(smoothYs, addressIndex);
    if (topIndex <= addressIndex || topIndex >= usableCount - 2) return null;

    final addressLandmarks = sortedSamples[addressIndex]['landmarks'] as List<dynamic>? ?? const [];
    final addressFrame = sortedFrames[addressIndex];
    final ball = await _detectBallPosition(
      imagePath: addressFrame['path'] as String,
      width: (addressFrame['width'] as num).toInt(),
      height: (addressFrame['height'] as num).toInt(),
      landmarks: addressLandmarks,
    );
    if (ball == null) return null;

    final frameImages = <img.Image?>[];
    for (int i = 0; i < usableCount; i++) {
      final path = sortedFrames[i]['path'] as String;
      final bytes = await File(path).readAsBytes();
      frameImages.add(img.decodeImage(bytes));
    }

    final addressX = smoothXs[addressIndex];
    final addressY = smoothYs[addressIndex];
    final topY = smoothYs[topIndex];
    final amplitude = (addressY - topY).abs();
    if (amplitude < 1) return null;

    final impactSearchStart = (topIndex + 1).clamp(1, usableCount - 2);
    final impactSearchEnd = (usableCount * 0.82).round().clamp(impactSearchStart + 1, usableCount - 2);
    final recoveryThreshold = topY + amplitude * 0.74;

    final scored = <({int index, double score})>[];
    for (int i = impactSearchStart; i <= impactSearchEnd; i++) {
      final prev = frameImages[i - 1];
      final curr = frameImages[i];
      final next = frameImages[i + 1];
      if (prev == null || curr == null || next == null) continue;

      final wristRecoveryY = smoothYs[i];
      if (wristRecoveryY < recoveryThreshold) continue;

      final wristDistanceScore = _wristBallClosenessScore(
        wristX: smoothXs[i],
        wristY: wristRecoveryY,
        addressX: addressX,
        addressY: addressY,
        ballX: ball.x.toDouble(),
        ballY: ball.y.toDouble(),
        frameWidth: curr.width.toDouble(),
        frameHeight: curr.height.toDouble(),
      );
      final ballMotionScore = _ballMotionScore(prev, curr, next, ball.x, ball.y);
      final clubPresenceScore = _clubPresenceScore(curr, ball.x, ball.y);
      final progressPenalty = ((i - impactSearchStart) / (impactSearchEnd - impactSearchStart + 1)).clamp(0.0, 1.0);

      final score = (ballMotionScore * 0.58) +
          (clubPresenceScore * 0.22) +
          (wristDistanceScore * 0.24) -
          (progressPenalty * 0.08);
      scored.add((index: i, score: score));
    }

    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.score.compareTo(a.score));
    final best = scored.first;
    final secondScore = scored.length > 1 ? scored[1].score : best.score * 0.72;
    final confidence = ((best.score - secondScore) / (best.score.abs() + 1e-6)).clamp(0.15, 0.98);
    final candidateTimes = scored.take(3).map((entry) => sortedFrames[entry.index]['t_ms'] as int).toList();

    return ImpactDetectionResult(
      tMs: sortedFrames[best.index]['t_ms'] as int,
      confidence: confidence,
      ballX: ball.x.toDouble(),
      ballY: ball.y.toDouble(),
      method: 'ball_motion_and_club_presence',
      candidateTimesMs: candidateTimes,
    );
  }

  static int _findAddressIndex(List<double> wristYs) {
    final maxSearchIndex = (wristYs.length * 0.45).round().clamp(1, wristYs.length - 1);
    var bestIndex = 0;
    var bestY = -double.infinity;
    for (int i = 0; i < maxSearchIndex; i++) {
      if (wristYs[i] > bestY) {
        bestY = wristYs[i];
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  static int _findTopIndex(List<double> wristYs, int addressIndex) {
    final searchEnd = (wristYs.length * 0.8).round().clamp(addressIndex + 1, wristYs.length);
    var bestIndex = addressIndex;
    var bestY = double.infinity;
    for (int i = addressIndex; i < searchEnd; i++) {
      if (wristYs[i] < bestY) {
        bestY = wristYs[i];
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  static double? _averageLandmarkAxis(
    List<dynamic> landmarks,
    Set<String> names,
    String axis,
  ) {
    double sum = 0;
    int count = 0;
    for (final item in landmarks) {
      if (item is Map && names.contains(item['name'])) {
        final value = item[axis];
        if (value is num && value.isFinite) {
          sum += value.toDouble();
          count++;
        }
      }
    }
    return count == 0 ? null : sum / count;
  }

  static List<double> _smoothSeries(List<double> values) {
    if (values.length < 3) return List<double>.from(values);
    return List<double>.generate(values.length, (index) {
      final from = index == 0 ? 0 : index - 1;
      final to = index == values.length - 1 ? values.length - 1 : index + 1;
      double sum = 0;
      int count = 0;
      for (int i = from; i <= to; i++) {
        sum += values[i];
        count++;
      }
      return sum / count;
    });
  }

  static Future<({int x, int y})?> _detectBallPosition({
    required String imagePath,
    required int width,
    required int height,
    required List<dynamic> landmarks,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    final ankleX = _averageLandmarkAxis(landmarks, const {'leftAnkle', 'rightAnkle'}, 'x');
    final ankleY = _averageLandmarkAxis(landmarks, const {'leftAnkle', 'rightAnkle'}, 'y');
    final wristX = _averageLandmarkAxis(landmarks, const {'leftWrist', 'rightWrist'}, 'x');
    if (ankleX == null || ankleY == null || wristX == null) return null;

    final xMin = math.max(0, math.min(width - 1, (math.min(ankleX, wristX) - width * 0.10).round()));
    final xMax = math.max(xMin + 1, math.min(width - 1, (math.max(ankleX, wristX) + width * 0.14).round()));
    final yMin = math.max(0, math.min(height - 1, (ankleY - height * 0.20).round()));
    final yMax = math.max(yMin + 1, math.min(height - 1, (ankleY - height * 0.01).round()));

    var bestScore = -double.infinity;
    int bestX = ((xMin + xMax) / 2).round();
    int bestY = ((yMin + yMax) / 2).round();

    for (int y = yMin; y <= yMax; y += 3) {
      for (int x = xMin; x <= xMax; x += 3) {
        final stats = _windowStats(image, x, y, radius: 3);
        final verticalBias = 1.0 - ((y - yMin) / ((yMax - yMin) + 1));
        final score = (stats.brightness * 0.60) + ((1 - stats.saturation) * 0.25) + (stats.contrast * 0.15) + (verticalBias * 0.05);
        if (score > bestScore) {
          bestScore = score;
          bestX = x;
          bestY = y;
        }
      }
    }

    return (x: bestX, y: bestY);
  }

  static ({double brightness, double saturation, double contrast}) _windowStats(
    img.Image image,
    int cx,
    int cy, {
    int radius = 3,
  }) {
    double brightnessSum = 0;
    double saturationSum = 0;
    double minBrightness = double.infinity;
    double maxBrightness = -double.infinity;
    int count = 0;

    for (int y = math.max(0, cy - radius); y <= math.min(image.height - 1, cy + radius); y++) {
      for (int x = math.max(0, cx - radius); x <= math.min(image.width - 1, cx + radius); x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final maxChannel = math.max(r, math.max(g, b));
        final minChannel = math.min(r, math.min(g, b));
        final brightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
        final saturation = maxChannel == 0 ? 0.0 : (maxChannel - minChannel) / maxChannel;
        brightnessSum += brightness;
        saturationSum += saturation;
        minBrightness = math.min(minBrightness, brightness);
        maxBrightness = math.max(maxBrightness, brightness);
        count++;
      }
    }

    return (
      brightness: count == 0 ? 0 : brightnessSum / count,
      saturation: count == 0 ? 1 : saturationSum / count,
      contrast: count == 0 ? 0 : (maxBrightness - minBrightness),
    );
  }

  static double _ballMotionScore(
    img.Image prev,
    img.Image curr,
    img.Image next,
    int ballX,
    int ballY,
  ) {
    final radiusX = math.max(10, (curr.width * 0.055).round());
    final radiusY = math.max(10, (curr.height * 0.045).round());
    double diffSum = 0;
    double weightSum = 0;

    for (int y = math.max(0, ballY - radiusY); y <= math.min(curr.height - 1, ballY + radiusY); y++) {
      for (int x = math.max(0, ballX - radiusX); x <= math.min(curr.width - 1, ballX + radiusX); x++) {
        final dx = (x - ballX).abs() / math.max(1, radiusX);
        final dy = (y - ballY).abs() / math.max(1, radiusY);
        final weight = math.max(0.1, 1.2 - (dx * 0.8) - (dy * 0.9));
        final prevGray = _grayscale(prev.getPixel(x, y));
        final currGray = _grayscale(curr.getPixel(x, y));
        final nextGray = _grayscale(next.getPixel(x, y));
        diffSum += ((currGray - prevGray).abs() + (nextGray - currGray).abs()) * weight;
        weightSum += weight;
      }
    }

    return weightSum == 0 ? 0 : diffSum / weightSum / 255.0;
  }

  static double _clubPresenceScore(
    img.Image image,
    int ballX,
    int ballY,
  ) {
    final radiusX = math.max(12, (image.width * 0.06).round());
    final radiusY = math.max(12, (image.height * 0.05).round());
    double edgeSum = 0;
    int count = 0;

    for (int y = math.max(1, ballY - radiusY); y < math.min(image.height - 1, ballY + radiusY); y++) {
      for (int x = math.max(1, ballX - radiusX); x < math.min(image.width - 1, ballX + radiusX); x++) {
        final center = _grayscale(image.getPixel(x, y));
        final right = _grayscale(image.getPixel(x + 1, y));
        final down = _grayscale(image.getPixel(x, y + 1));
        edgeSum += (center - right).abs() + (center - down).abs();
        count++;
      }
    }

    return count == 0 ? 0 : edgeSum / count / 255.0;
  }

  static double _wristBallClosenessScore({
    required double wristX,
    required double wristY,
    required double addressX,
    required double addressY,
    required double ballX,
    required double ballY,
    required double frameWidth,
    required double frameHeight,
  }) {
    final currentDx = wristX - ballX;
    final currentDy = wristY - ballY;
    final addressDx = addressX - ballX;
    final addressDy = addressY - ballY;
    final currentDistance = math.sqrt((currentDx * currentDx) + (currentDy * currentDy));
    final addressDistance = math.sqrt((addressDx * addressDx) + (addressDy * addressDy));
    final maxDistance = math.max(frameWidth, frameHeight);
    final normalizedCurrent = (currentDistance / maxDistance).clamp(0.0, 1.0);
    final normalizedAddress = (addressDistance / maxDistance).clamp(0.0, 1.0);
    return (1.0 - (normalizedCurrent / math.max(0.15, normalizedAddress))).clamp(0.0, 1.0);
  }

  static double _grayscale(img.Pixel pixel) =>
      (0.299 * pixel.r.toDouble()) + (0.587 * pixel.g.toDouble()) + (0.114 * pixel.b.toDouble());
}
