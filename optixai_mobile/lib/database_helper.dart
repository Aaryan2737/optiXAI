import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Singleton helper for the local offline SQLite database.
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    // Use a v2 database name to force a clean schema creation
    final dbPath = join(documentsDir.path, 'optixai_offline_v2.db');

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE patient_queue (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id        TEXT,
        patient_name      TEXT,
        age               INTEGER,
        gender            TEXT,
        diabetes_details  TEXT,
        phone             TEXT,
        left_eye_path     TEXT,
        right_eye_path    TEXT,
        left_dr_grade     INTEGER,
        right_dr_grade    INTEGER,
        requires_referral INTEGER,
        is_synced         INTEGER DEFAULT 0,
        timestamp         DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  Future<int> insertRecord(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert(
      'patient_queue',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedRecords() async {
    final db = await database;
    return await db.query(
      'patient_queue',
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );
  }

  Future<int> markSynced(int id) async {
    final db = await database;
    return await db.update(
      'patient_queue',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getAllRecords() async {
    final db = await database;
    return await db.query(
      'patient_queue',
      orderBy: 'timestamp DESC',
    );
  }

  Future<int> deleteRecord(int id) async {
    final db = await database;
    return await db.delete(
      'patient_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getUnsyncedCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM patient_queue WHERE is_synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
