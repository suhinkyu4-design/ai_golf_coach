import 'package:flutter/services.dart';
import '../models/swing_model.dart';
import 'slm_measurement_contract.dart';

class OnDeviceSlmService {
  // Populated only in debug builds for the fixed public-data smoke test.
  static String? debugLastResponse;
  static const channel = MethodChannel('com.metaoffice.aigolfcoatch/slm');
  static Future<bool> isReady() async {
    try {
      return await channel.invokeMethod<bool>('isReady') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> installModel(String path) =>
      channel.invokeMethod('installModel', {'path': path});
  static Future<Map<String, dynamic>?> describe(
      SwingModel swing, Map<String, dynamic> report) async {
    final payload =
        SlmMeasurementContract.select(report, swing.view.name, swing.club);
    if (payload == null || !await isReady()) return null;
    try {
      final raw = await channel.invokeMethod<String>(
          'describe', {'prompt': SlmMeasurementContract.prompt(payload)});
      if (raw == null) return null;
      assert(() { debugLastResponse = raw; return true; }());
      return {
        ...SlmMeasurementContract.validate(payload, raw),
        'model': 'golf_q8_v1',
        'input': payload
      };
    } catch (_) {
      return null;
    }
  }
}
