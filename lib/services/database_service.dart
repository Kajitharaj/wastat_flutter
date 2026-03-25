// lib/services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/contact.dart';
import '../models/status_event.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'wastat.db');

    return await openDatabase(path, version: 2, onCreate: _createTables, onUpgrade: _onUpgrade);
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE contacts (
        id                TEXT PRIMARY KEY,
        name              TEXT NOT NULL,
        phoneNumber       TEXT NOT NULL,
        avatarPath        TEXT,
        note              TEXT,
        isTracking        INTEGER NOT NULL DEFAULT 1,
        isCurrentlyOnline INTEGER NOT NULL DEFAULT 0,
        lastSeen          INTEGER,
        addedAt           INTEGER NOT NULL,
        totalSessions     INTEGER NOT NULL DEFAULT 0,
        totalOnlineMinutes INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE status_events (
        id              TEXT PRIMARY KEY,
        contactId       TEXT NOT NULL,
        status          TEXT NOT NULL,
        timestamp       INTEGER NOT NULL,
        durationSeconds INTEGER,
        FOREIGN KEY (contactId) REFERENCES contacts (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_events_contact ON status_events (contactId, timestamp DESC)');
  }

  /// Migrate v1 → v2: no schema change needed, but reserved for future use.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: nothing to migrate for existing data
  }

  // ── Contacts ─────────────────────────────────────────────
  Future<List<TrackedContact>> getAllContacts() async {
    final db = await database;
    final maps = await db.query('contacts', orderBy: 'addedAt DESC');
    return maps.map((m) => TrackedContact.fromMap(m)).toList();
  }

  Future<TrackedContact?> getContact(String id) async {
    final db = await database;
    final maps = await db.query('contacts', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return TrackedContact.fromMap(maps.first);
  }

  Future<void> insertContact(TrackedContact contact) async {
    final db = await database;
    await db.insert('contacts', contact.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateContact(TrackedContact contact) async {
    final db = await database;
    await db.update('contacts', contact.toMap(), where: 'id = ?', whereArgs: [contact.id]);
  }

  Future<void> deleteContact(String id) async {
    final db = await database;
    await db.delete('contacts', where: 'id = ?', whereArgs: [id]);
    await db.delete('status_events', where: 'contactId = ?', whereArgs: [id]);
  }

  Future<void> updateContactStatus(
    String contactId, {
    required bool isOnline,
    DateTime? lastSeen,
    int? addToSessions,
    int? addToMinutes,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{'isCurrentlyOnline': isOnline ? 1 : 0};
    if (lastSeen != null) updates['lastSeen'] = lastSeen.millisecondsSinceEpoch;

    if (addToSessions != null && addToSessions > 0) {
      await db.rawUpdate(
        'UPDATE contacts SET isCurrentlyOnline=?, lastSeen=?, '
        'totalSessions=totalSessions+?, totalOnlineMinutes=totalOnlineMinutes+? '
        'WHERE id=?',
        [isOnline ? 1 : 0, lastSeen?.millisecondsSinceEpoch, addToSessions, addToMinutes ?? 0, contactId],
      );
    } else {
      await db.update('contacts', updates, where: 'id = ?', whereArgs: [contactId]);
    }
  }

  // ── Status Events ────────────────────────────────────────
  Future<List<StatusEvent>> getEventsForContact(String contactId, {int? limit, DateTime? since}) async {
    final db = await database;
    String where = 'contactId = ?';
    List<dynamic> whereArgs = [contactId];

    if (since != null) {
      where += ' AND timestamp >= ?';
      whereArgs.add(since.millisecondsSinceEpoch);
    }

    final maps = await db.query(
      'status_events',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map((m) => StatusEvent.fromMap(m)).toList();
  }

  Future<void> insertStatusEvent(StatusEvent event) async {
    final db = await database;
    // REPLACE: re-syncing bridge data is safe because bridge events have
    // deterministic IDs (bridge_{contactId}_{ts}), so duplicate inserts just
    // overwrite with the same row. Local UUID events are never overwritten.
    await db.insert('status_events', event.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearEventsForContact(String contactId) async {
    final db = await database;
    await db.delete('status_events', where: 'contactId = ?', whereArgs: [contactId]);
  }

  Future<int> getEventCount(String contactId) async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM status_events WHERE contactId = ?', [contactId]);
    return (result.first['count'] as int?) ?? 0;
  }

  // ── Bridge history dedup helpers ─────────────────────────

  /// Returns true if a [status] event for [contactId] already exists in SQLite
  /// within ±[windowSeconds] of [timestamp].
  ///
  /// Used to prevent duplicate entries when syncing bridge history alongside
  /// events that were already recorded locally in real-time.
  Future<bool> hasEventNearTime(
    String contactId,
    DateTime timestamp,
    StatusType status, {
    int windowSeconds = 30,
  }) async {
    final db = await database;
    final statusStr = status == StatusType.online ? 'online' : 'offline';
    final low = timestamp.millisecondsSinceEpoch - windowSeconds * 1000;
    final high = timestamp.millisecondsSinceEpoch + windowSeconds * 1000;

    final rows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM status_events '
      'WHERE contactId = ? AND status = ? AND timestamp BETWEEN ? AND ?',
      [contactId, statusStr, low, high],
    );
    return (rows.first['c'] as int) > 0;
  }

  /// Returns the most recent [StatusEvent] for [contactId], or null.
  Future<StatusEvent?> getMostRecentEvent(String contactId) async {
    final db = await database;
    final maps = await db.query(
      'status_events',
      where: 'contactId = ?',
      whereArgs: [contactId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return StatusEvent.fromMap(maps.first);
  }

  // ── Analytics ────────────────────────────────────────────
  Future<Map<int, int>> getHourlyDistribution(String contactId) async {
    final db = await database;
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final result = await db.rawQuery(
      '''
      SELECT 
        CAST(strftime('%H', datetime(timestamp/1000, 'unixepoch')) AS INTEGER) as hour,
        COUNT(*) as count
      FROM status_events
      WHERE contactId = ? AND status = 'online' AND timestamp >= ?
      GROUP BY hour
      ORDER BY hour
    ''',
      [contactId, sevenDaysAgo.millisecondsSinceEpoch],
    );

    final map = <int, int>{};
    for (final row in result) {
      map[row['hour'] as int] = row['count'] as int;
    }
    return map;
  }

  Future<List<Map<String, dynamic>>> getDailyOnlineTime(String contactId, int days) async {
    final db = await database;
    final since = DateTime.now().subtract(Duration(days: days));
    return await db.rawQuery(
      '''
      SELECT 
        date(timestamp/1000, 'unixepoch') as day,
        COUNT(CASE WHEN status='online'  THEN 1 END) as sessions,
        SUM(CASE WHEN status='offline' THEN COALESCE(durationSeconds, 0) END) as totalSeconds
      FROM status_events
      WHERE contactId = ? AND timestamp >= ?
      GROUP BY day
      ORDER BY day
    ''',
      [contactId, since.millisecondsSinceEpoch],
    );
  }
}
