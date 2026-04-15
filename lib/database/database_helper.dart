import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/reminder.dart';

class DatabaseHelper {
  DatabaseHelper._init();

  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDb('ai_scheduler.db');
    return _database!;
  }

  Future<Database> _initDb(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return openDatabase(path, version: 2, onCreate: _createDb, onUpgrade: _upgradeDb);
  }

  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          text TEXT NOT NULL,
          is_user INTEGER NOT NULL,
          timestamp TEXT NOT NULL,
          metadata TEXT
        )
      ''');
    }
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        date_time TEXT NOT NULL,
        is_completed INTEGER DEFAULT 0,
        priority TEXT DEFAULT 'medium',
        repeat_rule TEXT,
        notification_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        is_user INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        metadata TEXT
      )
    ''');
  }

  // Reminder methods ... (existing)

  // Chat methods
  Future<int> insertChatMessage(Map<String, dynamic> message) async {
    final db = await database;
    return db.insert('chat_messages', message);
  }

  Future<List<Map<String, dynamic>>> getChatHistory() async {
    final db = await database;
    return db.query('chat_messages', orderBy: 'timestamp ASC');
  }

  Future<void> clearChatHistory() async {
    final db = await database;
    await db.delete('chat_messages');
  }

  Future<int> insertReminder(Reminder reminder) async {
    final db = await database;
    return db.insert('reminders', reminder.toMap());
  }

  Future<List<Reminder>> getAllReminders() async {
    final db = await database;
    final maps = await db.query('reminders', orderBy: 'date_time ASC');
    return maps.map(Reminder.fromMap).toList();
  }

  Future<List<Reminder>> getRemindersByDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final db = await database;
    final maps = await db.query(
      'reminders',
      where: 'date_time >= ? AND date_time < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date_time ASC',
    );
    return maps.map(Reminder.fromMap).toList();
  }

  Future<Reminder?> getNextUpcomingReminder() async {
    final db = await database;
    final maps = await db.query(
      'reminders',
      where: 'date_time >= ? AND is_completed = 0',
      whereArgs: [DateTime.now().toIso8601String()],
      orderBy: 'date_time ASC',
      limit: 1,
    );
    if (maps.isEmpty) {
      return null;
    }
    return Reminder.fromMap(maps.first);
  }

  Future<int> updateReminder(Reminder reminder) async {
    final db = await database;
    return db.update(
      'reminders',
      reminder.toMap(),
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
  }

  Future<int> deleteReminder(int id) async {
    final db = await database;
    return db.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> cleanupJunkReminders() async {
    final db = await database;
    final junkTitles = [
      'hi',
      'hi there',
      'are you there',
      'hello',
      'hey',
      'do i have any schedule',
      'check if i have any schedule',
      'check if i have schedule',
    ];
    for (final title in junkTitles) {
      await db.delete(
        'reminders',
        where: 'LOWER(title) = ?',
        whereArgs: [title.toLowerCase()],
      );
    }
  }

  Future<int> toggleComplete(int id, bool isCompleted) async {
    final db = await database;
    return db.update(
      'reminders',
      {
        'is_completed': isCompleted ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Reminder>> searchReminders(String query) async {
    final db = await database;
    final maps = await db.query(
      'reminders',
      where: 'LOWER(title) LIKE ?',
      whereArgs: ['%${query.toLowerCase()}%'],
      orderBy: 'date_time ASC',
    );
    return maps.map(Reminder.fromMap).toList();
  }
}
