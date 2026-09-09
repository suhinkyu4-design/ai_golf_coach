import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'ai_golf_coach.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE swings (
            swing_id TEXT PRIMARY KEY,
            created_at TEXT,
            video_path TEXT,
            view TEXT,
            handedness TEXT,
            club TEXT,
            duration_ms INTEGER,
            fps REAL,
            events_ms TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE shot_measurements (
            measurement_id TEXT PRIMARY KEY,
            swing_id TEXT,
            image_path TEXT,
            ball_speed_ms REAL,
            club_speed_ms REAL,
            carry_meters REAL,
            total_meters REAL,
            launch_angle REAL,
            back_spin REAL,
            side_spin REAL,
            smash_factor REAL,
            ocr_status TEXT
          )
        ''');
      },
    );
  }
}
