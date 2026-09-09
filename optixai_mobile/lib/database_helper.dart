import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Singleton helper for the local offline SQLite database.
///
/// Stores patient screening records captured on-device so they can be
/// queued for sync when connectivity is restored.
class DatabaseHelper {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  /// Returns the lazily-initialised database handle.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------
  Future<Database> _initDatabase() async {
    // Use the app-private documents directory (works on Android & iOS).
    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDir.path, 'optixai_offline.db');

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );
  }

  /// Creates the `patient_queue` table on first launch.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE patient_queue (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_name TEXT,
        image_path  TEXT,
        dr_grade    INTEGER,
        is_synced   INTEGER DEFAULT 0,
        timestamp   DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  // ---------------------------------------------------------------------------
  // CRUD operations
  // ---------------------------------------------------------------------------

  /// Inserts a new screening record into the offline queue.
  ///
  /// Expected keys in [row]:
  ///   - `patient_name` (String)
  ///   - `image_path`   (String)
  ///   - `dr_grade`     (int, 0-4)
  ///
  /// Returns the auto-generated row `id`.
  Future<int> insertRecord(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert(
      'patient_queue',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves all records that have **not** been synced to the server yet
  /// (`is_synced = 0`), ordered oldest-first.
  Future<List<Map<String, dynamic>>> getUnsyncedRecords() async {
    final db = await database;
    return await db.query(
      'patient_queue',
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );
  }

  /// Marks a record as synced after successful upload.
  Future<int> markSynced(int id) async {
    final db = await database;
    return await db.update(
      'patient_queue',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns every record in the queue (useful for the history screen).
  Future<List<Map<String, dynamic>>> getAllRecords() async {
    final db = await database;
    return await db.query(
      'patient_queue',
      orderBy: 'timestamp DESC',
    );
  }

  /// Deletes a single record by its [id].
  Future<int> deleteRecord(int id) async {
    final db = await database;
    return await db.delete(
      'patient_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns the count of un-synced records still in the queue.
  Future<int> getUnsyncedCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM patient_queue WHERE is_synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
