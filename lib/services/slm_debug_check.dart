import 'dart:convert';
import '../providers/swing_provider.dart';
import 'dart:io';
import 'gallery_pose_service.dart';
import 'swing_trajectory_service.dart';
import 'swing_fault_features.dart';
import 'impact_detection_service.dart';
import 'dart:developer';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import '../models/swing_model.dart';
import 'on_device_slm_service.dart';
import 'assistant_model_service.dart';
import 'assistant_rules.dart';
import 'package:flutter/services.dart';

/// Fixed public-data smoke cases, registered only inside a debug assertion.
bool registerSlmDebugCheck() {
  registerExtension('ext.golf.poseCacheQuickCheck', (_, __) async {
    final directory = Directory('/data/user/0/com.metaoffice.aigolfcoatch/files/recordings');
    final videos = directory.listSync().whereType<File>()
        .where((f) => f.path.endsWith('.mp4') && File('${f.path}.review.json').existsSync())
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (videos.isEmpty) return ServiceExtensionResponse.result(jsonEncode({'error':'no_reviewed_video'}));
    final path = videos.first.path;
    final review = jsonDecode(File('$path.review.json').readAsStringSync()) as Map;
    final watch = Stopwatch()..start();
    final rows = await GalleryPoseService.measureReviewedFrames(
      path, Map<String,int>.from(review['events_ms'] as Map));
    return ServiceExtensionResponse.result(jsonEncode({
      'elapsed_ms':watch.elapsedMilliseconds,
      'cache_hits':GalleryPoseService.debugLastReviewedCacheHits,
      'requested':(review['events_ms'] as Map).length,
      'returned':rows.length,
    }));
  });
  registerExtension('ext.golf.poseCacheCheck', (_, __) async {
    try {
      final directory = Directory('/data/user/0/com.metaoffice.aigolfcoatch/files/recordings');
      final videos = directory.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.mp4') && File('${f.path}.review.json').existsSync())
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (videos.isEmpty) return ServiceExtensionResponse.result(jsonEncode({'error':'no_reviewed_video'}));
      final path = videos.first.path;
      final review = jsonDecode(File('$path.review.json').readAsStringSync()) as Map;
      final provider = SwingProvider();
      final watch = Stopwatch()..start();
      try {
        provider.createNewSwing(videoPath:path, view:SwingView.rear,
          handedness:Handedness.right, club:'unknown');
        provider.updateVideoReview(durationMs:review['duration_ms'] as int,
          eventsMs:Map<String,int>.from(review['events_ms'] as Map));
        await provider.runAnalysis();
        return ServiceExtensionResponse.result(jsonEncode({
          'elapsed_ms':watch.elapsedMilliseconds,
          'reviewed_cache_hits':GalleryPoseService.debugLastReviewedCacheHits,
          'trajectory_cache_hits':GalleryPoseService.debugLastTrajectoryCacheHits,
          'sample_count':(provider.currentPoseReport?['motion_evidence']?['samples'] as List?)?.length,
          'result_created':provider.currentAnalysisResult != null,
        }));
      } finally { provider.dispose(); }
    } catch(error, stack) {
      return ServiceExtensionResponse.result(jsonEncode({'error':'$error','stack':'$stack'}));
    }
  });
  registerExtension('ext.golf.recentFailedGalleryCheck', (_, __) async {
    try {
      final cache = Directory('/data/user/0/com.metaoffice.aigolfcoatch/cache');
      final videos = cache.listSync(recursive: true).whereType<File>()
          .where((file) => file.path.endsWith('.mp4') &&
              File('${file.path}.pose.json').existsSync())
          .where((file) {
            try {
              final saved = jsonDecode(
                  File('${file.path}.pose.json').readAsStringSync()) as Map;
              return saved['impact_debug']?['reason'] ==
                  'no_unique_hit_among_swings';
            } catch (_) {
              return false;
            }
          }).toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (videos.isEmpty) {
        return ServiceExtensionResponse.result(
            jsonEncode({'error': 'no_recent_ambiguous_gallery_video'}));
      }
      final path = videos.first.path;
      final watch = Stopwatch()..start();
      final ok = await GalleryPoseService.analyzeGalleryVideo(
          videoPath: path, onProgress: (_, __) {});
      final saved = jsonDecode(
          File('$path.pose.json').readAsStringSync()) as Map<String, dynamic>;
      final samples = saved['samples'] as List? ?? const [];
      return ServiceExtensionResponse.result(jsonEncode({
        'ok': ok,
        'elapsed_ms': watch.elapsedMilliseconds,
        'video_path': path,
        'sample_count': samples.length,
        'detected_count': samples.where((row) => row['detected'] == true).length,
        'impact_debug': saved['impact_debug'],
      }));
    } catch (error, stack) {
      return ServiceExtensionResponse.result(
          jsonEncode({'error': '$error', 'stack': '$stack'}));
    }
  });
  registerExtension('ext.golf.assistantModelCheck', (_, __) async {
    final rules = AssistantRules.fromJson(
        await rootBundle.loadString('assets/assistant_rules.json'));
    final ready = await AssistantModelService.isReady();
    const request = '촬영이 실패한 이유가 뭐야?';
    final decision = rules.resolve(request, hasAnalysis: false, busy: false);
    final timer = Stopwatch()..start();
    final response = await AssistantModelService.respond(
        request: request,
        rules: rules,
        decision: decision,
        draftReply: decision.message ?? '촬영 실패 상황을 조금 더 알려주세요.',
        history: const [
          {'role': 'assistant', 'content': '무엇을 도와드릴까요?'}
        ],
        hasAnalysis: false,
        busy: false);
    return ServiceExtensionResponse.result(jsonEncode({
      'ready': ready,
      'resolved_action': decision.intent.action,
      'model_action': response?.action,
      'reply': response?.reply,
      'elapsed_ms': timer.elapsedMilliseconds,
    }));
  });
  registerExtension('ext.golf.portraitCheck', (_, params) async {
    const path = '/data/user/0/com.metaoffice.aigolfcoatch/cache/baa1317c-9ddf-448e-aa5c-937e8a22a598/1000005801.mp4';
    final ok = await GalleryPoseService.analyzeGalleryVideo(videoPath:path,onProgress:(_,__){});
    final data=jsonDecode(await File('$path.pose.json').readAsString()) as Map;
    final rows=(data['samples'] as List).map((p)=>Map<String,dynamic>.from(p)).toList();
    return ServiceExtensionResponse.result(jsonEncode({'ok':ok,'sample_count':rows.length,
      'phase':ImpactDetectionService.scanWindow(rows),'impact':data['vision_impact'],
      'debug':data['impact_debug']}));
  });

  registerExtension('ext.golf.providerCheck', (_, params) async {
    try {
    File('${Directory.systemTemp.path}/golf_provider_check_stage.json').writeAsStringSync(jsonEncode({'step':'entered'}));
    const providerClips = [
      '/data/user/0/com.metaoffice.aigolfcoatch/cache/a2441b16-7d66-42e1-95ae-e5af734137f7/1000005800.mp4',
      '/data/user/0/com.metaoffice.aigolfcoatch/cache/ea2e1dc0-2b7e-4f3b-9dfd-a003fea9a5cf/1000005695.mp4',
      '/data/user/0/com.metaoffice.aigolfcoatch/cache/db7bfd33-5e44-45d8-8914-e0f42fcd2fd9/1000005689.mp4',
      '/data/user/0/com.metaoffice.aigolfcoatch/cache/casting_validation/side_view.mp4',
    ];
    final caseIndex = int.tryParse(params['case'] ?? '1') ?? 1;
    if (caseIndex < 0 || caseIndex >= providerClips.length) {
      return ServiceExtensionResponse.result(jsonEncode({'error': 'unknown_case'}));
    }
    final path = providerClips[caseIndex];
    final review = jsonDecode(File('$path.review.json').readAsStringSync()) as Map;
    final provider = SwingProvider();
    final watch = Stopwatch()..start();
    try {
      provider.createNewSwing(videoPath: path, view: SwingView.rear,
        handedness: Handedness.right, club: 'unknown');
      provider.updateVideoReview(durationMs: review['duration_ms'] as int,
        eventsMs: Map<String,int>.from(review['events_ms'] as Map));
      log('provider started',name:'GOLF_CHECK');
      await provider.runAnalysis(onProgress:(step,message){
        log('${watch.elapsedMilliseconds}ms step=$step $message',name:'GOLF_CHECK');
        File('${Directory.systemTemp.path}/golf_provider_check_stage.json').writeAsStringSync(jsonEncode({'elapsed_ms':watch.elapsedMilliseconds,'step':step,'message':message}));
      });
      final report = provider.currentPoseReport!;
      return ServiceExtensionResponse.result(jsonEncode({
        'scope': 'actual_provider_path_unknown_club_saved_review',
        'elapsed_ms': watch.elapsedMilliseconds,
        'sample_count': (report['motion_evidence']['samples'] as List).length,
        'motion_samples': report['motion_evidence']['samples'],
        'arm_refinements': [for(final row in report['motion_evidence']['samples'] as List)
          if(row['arm_refinement'] is Map){'t_ms':row['t_ms'],'original':row['landmarks'],...row['arm_refinement']}],
        'casting': report['fault_features']['casting_check'],
        'over_the_top': report['fault_features']['over_the_top_check'],
        'shaft_candidates': [for (final row in report['motion_evidence']['samples'] as List)
          if (row['shaft_candidate'] != null) row['shaft_candidate']],
        'standing_up': report['fault_features']['standing_up_check'],
        'chicken_wing': report['fault_features']['chicken_wing_check'],
        'head_up': report['fault_features']['head_up_check'],
        'trail_knee': report['fault_features']['trail_knee_check'],
        'early_extension': report['fault_features']['early_extension_check'],
        'result_created': provider.currentAnalysisResult != null,
      }));
    } finally { provider.dispose(); }
    } catch(error,stack) {
      return ServiceExtensionResponse.result(jsonEncode({'error':'$error','stack':'$stack'}));
    }
  });
  registerExtension('ext.golf.trajectoryCheck', (_, params) async {
    const clips = [
      '/data/user/0/com.metaoffice.aigolfcoatch/cache/9ed4fad2-de79-4637-aebb-286f71ea398e/1000005695.mp4',
      '/data/user/0/com.metaoffice.aigolfcoatch/cache/dedaa230-774d-4ca2-9058-206e37e713dc/1000005689.mp4',
    ];
    final index = int.tryParse(params['case'] ?? '0') ?? 0;
    if (index < 0 || index >= clips.length) {
      return ServiceExtensionResponse.result(jsonEncode({'error': 'unknown_case'}));
    }
    final path = clips[index];
    final data = jsonDecode(await File('$path.pose.json').readAsString()) as Map;
    final sparse = (data['samples'] as List).map((x) => Map<String, dynamic>.from(x)).toList();
    final window = ImpactDetectionService.scanWindow(sparse);
    if (window == null) return ServiceExtensionResponse.result(jsonEncode({'error': 'no_test_window'}));
    final start = int.tryParse(params['address_ms'] ?? '') ?? window['address_ms']!;
    final top = int.tryParse(params['top_ms'] ?? '') ?? window['top_ms']!;
    // Automatic candidate only; this test does not verify swing phase ground truth.
    final end = int.tryParse(params['impact_ms'] ?? '') ?? window['return_ms']!;
    final watch = Stopwatch()..start();
    final finish = int.tryParse(params['finish_ms'] ?? '') ?? sparse.last['t_ms'] as int;
    final view = params['view'] == 'rear' ? SwingView.rear : SwingView.faceOn;
    final ballSign = int.tryParse(params['ball_sign'] ?? '');
    final targetSign = int.tryParse(params['target_sign'] ?? '');
    final events = {'address': start, 'top': top, 'impact': end, 'finish': finish};
    final reviewed = await GalleryPoseService.measureReviewedFrames(path, events);
    final samples = await GalleryPoseService.measureTrajectoryFrames(path, start, end, topMs: top, finishMs: finish);
    final swing = SwingModel(swingId: 'device_trajectory_probe', createdAt: DateTime(2026),
      videoPath: path, view: view, handedness: Handedness.right,
      club: params['club'] ?? (index == 0 ? '7i' : 'Driver'), durationMs: (sparse.last['t_ms'] as int) + 1,
      fps: 0, eventsMs: events);
    final report = SwingTrajectoryService.measure(swing: swing,
      address: reviewed['address'], samples: samples, confirmed: true);
    return ServiceExtensionResponse.result(jsonEncode({
      'case': index, 'scope': 'automatic_window_pipeline_test_not_club_or_phase_validation',
      'configuration': {'view': view.name, 'club': swing.club, 'events_ms': events,
        'ball_sign': ballSign, 'target_sign': targetSign,
        'phase_basis': params.containsKey('impact_ms') ? 'visual_approximation_not_ground_truth' : 'automatic_window'},
      'evidence': {'reviewed': reviewed, 'samples': samples},
      'elapsed_ms': watch.elapsedMilliseconds, 'extracted_count': samples.length,
      'pose_detected_count': samples.where((s) => (s['landmarks'] as List).isNotEmpty).length,
      'eye_detected_count': samples.where((s) => (s['landmarks'] as List).where((p) => p['name'] == 'leftEye').isNotEmpty).length,
      'report': report,
      'fault_features': SwingFaultFeatures.analyze(swing: swing, reviewed: reviewed, samples: samples, confirmed: true, ballImageSign: ballSign, targetImageSign: targetSign),
    }));
  });
  registerExtension('ext.golf.mediaCheck', (_, __) async {
    final results = <String, dynamic>{};
    try {
      final lost = await ImagePicker().retrieveLostData();
      results['gallery_channel'] = 'ok';
      results['lost_data_empty'] = lost.isEmpty;
    } catch (error) {
      results['gallery_error'] = error.toString();
    }
    try {
      results['camera_count'] = (await availableCameras()).length;
      results['camera_channel'] = 'ok';
    } catch (error) {
      results['camera_error'] = error.toString();
    }
    return ServiceExtensionResponse.result(jsonEncode(results));
  });
  registerExtension('ext.golf.slmCheck', (_, __) async {
    final ready = await OnDeviceSlmService.isReady();
    final results = <Map<String, dynamic>>[];
    if (ready) {
      for (final rear in [false, true]) {
        final swing = SwingModel(
            swingId: 'public_debug_probe',
            createdAt: DateTime(2026),
            videoPath: '',
            view: rear ? SwingView.rear : SwingView.faceOn,
            handedness: Handedness.right,
            club: rear ? 'driver' : '7i',
            durationMs: 0,
            fps: 0,
            eventsMs: {});
        final report = <String, dynamic>{
          'metrics': [
            {
              'id': rear
                  ? 'trail_knee_projected_at_top'
                  : 'lead_elbow_projected_at_impact',
              'phase': rear ? 'top' : 'impact',
              'kind': rear ? 'trail_knee' : 'lead_elbow',
              'value': rear ? 180.0 : 148.21,
              'unit': 'deg',
              'status': 'estimated',
              'reason': null,
              'min_joint_likelihood': .9,
              'joint_names': rear
                  ? ['rightHip', 'rightKnee', 'rightAnkle']
                  : ['leftShoulder', 'leftElbow', 'leftWrist']
            }
          ]
        };
        final watch = Stopwatch()..start();
        final output = await OnDeviceSlmService.describe(swing, report);
        results.add({
          'case': rear ? 'previous_error' : 'faceon',
          'elapsed_ms': watch.elapsedMilliseconds,
          'output': output,
          'raw': OnDeviceSlmService.debugLastResponse
        });
      }
    }
    return ServiceExtensionResponse.result(
        jsonEncode({'ready': ready, 'cases': results}));
  });
  return true;
}
