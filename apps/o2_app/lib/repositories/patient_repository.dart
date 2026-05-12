import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/patient.dart';

/// Patient Repository — uses plain sqflite (no Brick/Supabase)
class PatientRepository {
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
          CREATE TABLE IF NOT EXISTS patients (
            id TEXT PRIMARY KEY,
            abha_number TEXT,
            name TEXT,
            age INTEGER,
            gender TEXT,
            phone TEXT,
            assigned_chw_id TEXT,
            phc_id TEXT,
            address TEXT,
            village TEXT,
            district TEXT,
            state TEXT,
            emergency_contact TEXT,
            medical_history TEXT,
            allergies TEXT,
            blood_group TEXT,
            high_risk_pregnancy INTEGER DEFAULT 0,
            risk_level TEXT DEFAULT 'LOW',
            last_visit TEXT,
            next_visit TEXT,
            notes TEXT,
            is_active INTEGER DEFAULT 1,
            created_at TEXT,
            updated_at TEXT
          )
        ''');
      },
    );
  }

  Future<List<Patient>> getAllPatients() async {
    final db = await database;
    final maps = await db.query('patients', where: 'is_active = 1');
    return maps.map((m) => Patient.fromJson(m)).toList();
  }

  Future<List<Patient>> getPatientsForChw(String chwId) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'assigned_chw_id = ? AND is_active = 1',
      whereArgs: [chwId],
    );
    return maps.map((m) => Patient.fromJson(m)).toList();
  }

  Future<Patient?> getPatientById(String id) async {
    final db = await database;
    final maps = await db.query('patients', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Patient.fromJson(maps.first);
  }

  Future<List<Patient>> getHighRiskPatients() async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: "risk_level IN ('HIGH', 'EMERGENCY') AND is_active = 1",
    );
    return maps.map((m) => Patient.fromJson(m)).toList();
  }

  Future<void> upsertPatient(Patient patient) async {
    final db = await database;
    await db.insert(
      'patients',
      patient.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateRiskLevel(String patientId, String riskLevel) async {
    final db = await database;
    await db.update(
      'patients',
      {'risk_level': riskLevel, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [patientId],
    );
  }
}
