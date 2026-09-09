import 'dart:convert';

enum SwingView { faceOn, rear, targetLine, unknown }
enum Handedness { right, left }

class SwingModel {
  final String swingId;
  final DateTime createdAt;
  final String videoPath;
  final SwingView view;
  final Handedness handedness;
  final String club;
  final int durationMs;
  final double fps;
  final Map<String, int> eventsMs; // top, impact, finish t_ms

  SwingModel({
    required this.swingId,
    required this.createdAt,
    required this.videoPath,
    required this.view,
    required this.handedness,
    required this.club,
    required this.durationMs,
    required this.fps,
    required this.eventsMs,
  });

  Map<String, dynamic> toMap() {
    return {
      'swing_id': swingId,
      'created_at': createdAt.toIso8601String(),
      'video_path': videoPath,
      'view': view.name,
      'handedness': handedness.name,
      'club': club,
      'duration_ms': durationMs,
      'fps': fps,
      'events_ms': jsonEncode(eventsMs),
    };
  }

  factory SwingModel.fromMap(Map<String, dynamic> map) {
    return SwingModel(
      swingId: map['swing_id'],
      createdAt: DateTime.parse(map['created_at']),
      videoPath: map['video_path'],
      view: SwingView.values.firstWhere(
        (e) => e.name == map['view'],
        orElse: () => SwingView.unknown,
      ),
      handedness: map['handedness'] == 'left' ? Handedness.left : Handedness.right,
      club: map['club'] ?? '7i',
      durationMs: map['duration_ms'] ?? 0,
      fps: (map['fps'] as num?)?.toDouble() ?? 60.0,
      eventsMs: map['events_ms'] != null
          ? Map<String, int>.from(jsonDecode(map['events_ms']))
          : {},
    );
  }
}
