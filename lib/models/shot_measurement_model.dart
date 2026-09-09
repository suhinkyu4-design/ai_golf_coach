enum OcrStatus { pending, userConfirmed, rejected }

class ShotMeasurementModel {
  final String measurementId;
  final String swingId;
  final String? imagePath;
  final double? ballSpeedMs;
  final double? clubSpeedMs;
  final double? carryDistanceMeters;
  final double? totalDistanceMeters;
  final double? launchAngleDeg;
  final double? backSpinRpm;
  final double? sideSpinRpm;
  final double? smashFactor;
  final OcrStatus ocrStatus;

  ShotMeasurementModel({
    required this.measurementId,
    required this.swingId,
    this.imagePath,
    this.ballSpeedMs,
    this.clubSpeedMs,
    this.carryDistanceMeters,
    this.totalDistanceMeters,
    this.launchAngleDeg,
    this.backSpinRpm,
    this.sideSpinRpm,
    this.smashFactor,
    this.ocrStatus = OcrStatus.pending,
  });

  /// Calculate Smash Factor: Ball Speed / Club Speed
  double? get calculatedSmashFactor {
    if (ballSpeedMs != null && clubSpeedMs != null && clubSpeedMs! > 0) {
      return double.parse((ballSpeedMs! / clubSpeedMs!).toStringAsFixed(2));
    }
    return smashFactor;
  }

  // Unit conversion helpers
  double? get ballSpeedMph => ballSpeedMs != null ? ballSpeedMs! * 2.23694 : null;
  double? get clubSpeedMph => clubSpeedMs != null ? clubSpeedMs! * 2.23694 : null;
  double? get carryYards => carryDistanceMeters != null ? carryDistanceMeters! * 1.09361 : null;

  Map<String, dynamic> toMap() {
    return {
      'measurement_id': measurementId,
      'swing_id': swingId,
      'image_path': imagePath,
      'ball_speed_ms': ballSpeedMs,
      'club_speed_ms': clubSpeedMs,
      'carry_meters': carryDistanceMeters,
      'total_meters': totalDistanceMeters,
      'launch_angle': launchAngleDeg,
      'back_spin': backSpinRpm,
      'side_spin': sideSpinRpm,
      'smash_factor': calculatedSmashFactor,
      'ocr_status': ocrStatus.name,
    };
  }

  factory ShotMeasurementModel.fromMap(Map<String, dynamic> map) {
    return ShotMeasurementModel(
      measurementId: map['measurement_id'],
      swingId: map['swing_id'],
      imagePath: map['image_path'],
      ballSpeedMs: (map['ball_speed_ms'] as num?)?.toDouble(),
      clubSpeedMs: (map['club_speed_ms'] as num?)?.toDouble(),
      carryDistanceMeters: (map['carry_meters'] as num?)?.toDouble(),
      totalDistanceMeters: (map['total_meters'] as num?)?.toDouble(),
      launchAngleDeg: (map['launch_angle'] as num?)?.toDouble(),
      backSpinRpm: (map['back_spin'] as num?)?.toDouble(),
      sideSpinRpm: (map['side_spin'] as num?)?.toDouble(),
      smashFactor: (map['smash_factor'] as num?)?.toDouble(),
      ocrStatus: map['ocr_status'] == 'userConfirmed'
          ? OcrStatus.userConfirmed
          : OcrStatus.pending,
    );
  }
}
