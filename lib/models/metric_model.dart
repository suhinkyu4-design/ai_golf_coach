enum MetricStatus { usable, estimated, unavailable }

class MetricModel {
  final String id; // e.g. lead_elbow_projected_at_top, upper_body_tilt, tempo_ratio
  final String name;
  final double value;
  final String unit; // deg, ms, ratio, ratio_of_body_length
  final MetricStatus status;
  final List<int> evidenceTimeMs; // Timestamps of frames used as evidence

  MetricModel({
    required this.id,
    required this.name,
    required this.value,
    required this.unit,
    required this.status,
    required this.evidenceTimeMs,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'value': value,
      'unit': unit,
      'status': status.name,
      'evidence_t_ms': evidenceTimeMs,
    };
  }

  factory MetricModel.fromMap(Map<String, dynamic> map) {
    return MetricModel(
      id: map['id'],
      name: map['name'] ?? '',
      value: (map['value'] as num).toDouble(),
      unit: map['unit'] ?? '',
      status: MetricStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MetricStatus.usable,
      ),
      evidenceTimeMs: List<int>.from(map['evidence_t_ms'] ?? []),
    );
  }
}
