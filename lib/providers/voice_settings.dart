import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

class VoiceSettings extends ChangeNotifier {
  static const channel = MethodChannel('com.metaoffice.aigolfcoatch/voice_capture');
  bool enabled = false, saving = false;
  late File _file;
  Future<void> load() async {
    _file = File('${await getDatabasesPath()}/voice_capture.txt');
    try { enabled = await _file.exists() && (await _file.readAsString()).trim() == 'enabled'; } catch (_) { enabled = false; }
  }
  Future<void> select(bool value) async {
    if (saving) return;
    saving = true; notifyListeners();
    try {
      if (value) {
        final allowed = await channel.invokeMethod<bool>('requestPermission');
        if (allowed != true) throw StateError('마이크 권한을 허용해 주세요.');
      } else { await channel.invokeMethod('disable'); }
      await _file.parent.create(recursive: true);
      await _file.writeAsString(value ? 'enabled' : 'disabled', flush: true);
      enabled = value;
    } finally { saving = false; notifyListeners(); }
  }
}
