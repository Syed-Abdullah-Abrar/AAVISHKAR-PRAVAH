import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

/// EncryptionService — manages encrypted local database (demo: plain sqflite)
class EncryptionService {
  static const _secureStorage = FlutterSecureStorage();
  Database? _database;

  /// Open or create the local database
  Future<Database> openEncryptedDatabase() async {
    if (_database != null && _database!.isOpen) return _database!;

    final dbPath = join(await getDatabasesPath(), 'o2_local.db');
    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onDatabaseCreate,
    );
    debugPrint('[EncryptionService] Database opened at $dbPath');
    return _database!;
  }

  /// Close the database
  Future<void> closeDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  /// Delete and recreate database (for testing)
  Future<void> resetDatabase() async {
    await closeDatabase();
    final dbPath = join(await getDatabasesPath(), 'o2_local.db');
    await deleteDatabase(dbPath);
    debugPrint('[EncryptionService] Database reset');
  }

  /// Store a secure key-value pair
  Future<void> storeSecureValue(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  /// Read a secure key-value pair
  Future<String?> readSecureValue(String key) async {
    return await _secureStorage.read(key: key);
  }

  /// Delete a secure key-value pair
  Future<void> deleteSecureValue(String key) async {
    await _secureStorage.delete(key: key);
  }

  /// Database creation callback
  Future<void> _onDatabaseCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS patients (
        id TEXT PRIMARY KEY,
        abha_number TEXT,
        name TEXT NOT NULL,
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
        emergency_phone TEXT,
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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS clinical_contacts (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        contact_type TEXT,
        notes TEXT,
        conducted_by TEXT,
        contact_date TEXT,
        created_at TEXT
      )
    ''');

    debugPrint('[EncryptionService] Database tables created');
  }
}