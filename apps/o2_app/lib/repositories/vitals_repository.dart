import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/vitals.dart';

/// Vitals Repository — uses plain sqflite (no Brick/Supabase)
class VitalsRepository {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'o2_local.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS vitals (
            id TEXT PRIMARY KEY,
            patient_id TEXT NOT NULL,
            systolic_bp REAL,
            diastolic_bp REAL,
            heart_rate REAL,
            temperature REAL,
            spo2 REAL,
            weight REAL,
            hemoglobin REAL,
            fetal_heart_rate REAL,
            vital_type TEXT,
            value TEXT,
            unit TEXT,
            notes TEXT,
            recorded_by TEXT,
            source TEXT,
            clinical_flag TEXT,
            recorded_at TEXT,
            created_at TEXT
          )
        ''');
      },
    );
  }

  Future<List<Vitals>> getVitalsForPatient(String patientId, {int limit = 10}) async {
    final db = await database;
    final maps = await db.query(
      'vitals',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return maps.map((m) => Vitals.fromJson(m)).toList();
  }

  Future<Vitals?> getLatestVitals(String patientId) async {
    final list = await getVitalsForPatient(patientId, limit: 1);
    return list.isEmpty ? null : list.first;
  }

  Future<void> saveVitals(Vitals vitals) async {
    final db = await database;
    await db.insert(
      'vitals',
      vitals.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Vitals>> getRecentVitalsForPhc(String phcId, {int days = 7}) async {
    final db = await database;
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final maps = await db.rawQuery('''
      SELECT v.* FROM vitals v
      INNER JOIN patients p ON p.id = v.patient_id
      WHERE p.phc_id = ? AND v.recorded_at > ?
      ORDER BY v.recorded_at DESC
      LIMIT 50
    ''', [phcId, since]);
    return maps.map((m) => Vitals.fromJson(m)).toList();
  }
}