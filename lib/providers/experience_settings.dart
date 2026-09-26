import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/swing_model.dart';

class ExperienceSettings extends ChangeNotifier {
  bool saving = false;
  Handedness hand = Handedness.right;
  SwingView view = SwingView.rear;
  String club = 'unknown';
  late File _file;
  Future<void> load() async {
    _file = File('${await getDatabasesPath()}/experience.json');
    try {
      final m = jsonDecode(await _file.readAsString()) as Map;
      hand = m['hand'] == 'left' ? Handedness.left : Handedness.right;
      view = m['view'] == 'faceOn' ? SwingView.faceOn : SwingView.rear;
      club = ['Driver', '7i'].contains(m['club'])
          ? m['club'] as String
          : 'unknown';
    } catch (_) {}
  }

  Future<void> select(
      {Handedness? hand,
      SwingView? view,
      String? club}) async {
    if (saving) throw StateError('설정을 저장 중입니다.');
    final next = {
      'hand': (hand ?? this.hand).name,
      'view': (view ?? this.view).name,
      'club': club ?? this.club
    };
    saving = true;
    notifyListeners();
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode(next), flush: true);
      this.hand = hand ?? this.hand;
      this.view = view ?? this.view;
      this.club = club ?? this.club;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
