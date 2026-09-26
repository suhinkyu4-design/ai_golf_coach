import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_golf_coach/services/gallery_pose_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const extractor =
      MethodChannel('com.metaoffice.aigolfcoatch/frame_extractor');
  const detector = MethodChannel('google_mlkit_pose_detector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late String video;
  var closed = false;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('golf_pose_test_');
    video = '${temp.path}/swing.mp4';
    closed = false;
    messenger.setMockMethodCallHandler(
        extractor,
        (_) async => List.generate(
            10,
            (i) => {
                  'path': '${temp.path}/missing_$i.jpg',
                  't_ms': i * 100,
                  'width': 640,
                  'height': 480,
                }));
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(extractor, null);
    messenger.setMockMethodCallHandler(detector, null);
    await temp.delete(recursive: true);
  });
  test('preserves detected joints when optional impact image reading fails',
      () async {
    var index = 0;
    const ys = [
      400.0,
      390.0,
      300.0,
      200.0,
      100.0,
      200.0,
      300.0,
      390.0,
      380.0,
      370.0
    ];
    messenger.setMockMethodCallHandler(detector, (call) async {
      if (call.method == 'vision#closePoseDetector') {
        closed = true;
        return null;
      }
      return [
        [
          {
            'type': 15,
            'x': 200.0,
            'y': ys[index++],
            'z': 0.0,
            'likelihood': 0.99
          }
        ]
      ];
    });
    final result = await GalleryPoseService.analyzeGalleryVideo(
        videoPath: video, onProgress: (_, __) {});
    expect(result, isTrue);
    final data = jsonDecode(await File('$video.pose.json').readAsString());
    expect(data['samples'], hasLength(10));
    expect(data['samples'].every((dynamic s) => s['detected'] == true), isTrue);
    expect(data['vision_impact'], isNull);
    expect(closed, isTrue);
  });
  test('reports detector failure and closes detector', () async {
    messenger.setMockMethodCallHandler(detector, (call) async {
      if (call.method == 'vision#closePoseDetector') {
        closed = true;
        return null;
      }
      throw PlatformException(code: 'DETECTOR_FAILED');
    });
    final statuses = <String>[];
    final result = await GalleryPoseService.analyzeGalleryVideo(
        videoPath: video, onProgress: (_, s) => statuses.add(s));
    expect(result, isFalse);
    expect(statuses.last, contains('DETECTOR_FAILED'));
    expect(closed, isTrue);
  });
}
