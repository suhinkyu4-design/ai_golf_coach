import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.light;
  late File _file;
  bool saving = false;
  Future<void> load() async {
    _file = File('${await getDatabasesPath()}/appearance.txt');
    try { if (await _file.exists() && (await _file.readAsString()).trim() == 'dark') mode = ThemeMode.dark; } catch (_) { /* Default to light when no readable preference exists. */ }
  }
  Future<void> select(ThemeMode value) async {
    if (saving || value == mode) return;
    saving = true; notifyListeners();
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(value == ThemeMode.dark ? 'dark' : 'light', flush: true);
      mode = value;
    } finally { saving = false; notifyListeners(); }
  }
}
