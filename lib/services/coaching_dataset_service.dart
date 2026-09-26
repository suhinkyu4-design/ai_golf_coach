import '../models/swing_model.dart';
import 'evidence_coaching_service.dart';

class CoachingDatasetService {
  static Map<String, dynamic> draft(
          SwingModel swing, Map<String, dynamic> report,
          {required bool eventsConfirmed}) =>
      {
        'schema_version': 'golf_coaching_evidence_2.0',
        'record_id': swing.swingId,
        'source': 'app_measurements_with_reference_context',
        'golfer_id': null,
        'session_id': null,
        'training_consent': false,
        'input': {
          'view': swing.view.name,
          'handedness': swing.handedness.name,
          'club': swing.club,
          'events_ms': swing.eventsMs,
          'events_user_confirmed': eventsConfirmed,
          'pose_measurements': report,
        },
        'coaching_context': EvidenceCoachingService.build(swing, report,
            eventsConfirmed: eventsConfirmed),
        'training_target': null,
      };
}
