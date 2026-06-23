import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class CallDatabase {
  static final CallDatabase instance = CallDatabase._init();
  static Database? _database;

  CallDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('calls.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    Directory dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, fileName);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE calls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT UNIQUE,
        phone_number TEXT,
        call_type TEXT,
        duration INTEGER,
        audio_path TEXT,
        status TEXT,
        created_at TEXT
      )
    ''');
  }

  // 📥 INSERT CALL
  Future<int> insertCall(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert(
      'calls',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  //  GET ALL CALLS
  Future<List<Map<String, dynamic>>> getAllCalls() async {
    final db = await database;
    return await db.query(
      'calls',
      orderBy: 'id DESC',
    );
  }

  //  GET PENDING CALLS
  Future<List<Map<String, dynamic>>> getPendingCalls() async {
    final db = await database;
    return await db.query(
      'calls',
      where: 'status = ?',
      whereArgs: ['pending'],
    );
  }

  //  UPDATE STATUS
  Future<int> updateCallStatus(String sessionId, String status) async {
    final db = await database;
    return await db.update(
      'calls',
      {'status': status},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }
}