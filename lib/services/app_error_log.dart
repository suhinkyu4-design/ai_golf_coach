import 'dart:io';
import 'package:flutter/foundation.dart';

/// Bounded local diagnostics; no video/image data and no network transmission.
class AppErrorLog {
  static Future<void> _pending = Future.value();
  static bool _installed = false;
  static void install() {
    if (_installed) return;
    _installed = true;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record('FLUTTER_ERROR', '${details.exceptionAsString()}\n${details.stack ?? ''}');
      if (previous != null) previous(details);
      else FlutterError.presentError(details);
    };
  }

  static void record(String event, String message) {
    debugPrint('[$event] $message');
    _pending = _pending.then((_) async {
      try {
        final file = File('${Directory.systemTemp.path}/golf_app_errors.log');
        if (await file.exists() && await file.length() > 65536) {
          final old = await file.readAsString();
          await file.writeAsString(old.substring(old.length > 32768 ? old.length - 32768 : 0));
        }
        final bounded = message.length > 12000 ? message.substring(0, 12000) : message;
        await file.writeAsString('${DateTime.now().toIso8601String()} [$event] $bounded\n',
          mode: FileMode.append, flush: true);
      } catch (_) { /* Logging must never interrupt recording or error reporting. */ }
    });
  }
}
