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
    return await openDatabase(path, version: 3, onCreate: _createTables, onUpgrade: _onUpgrade);
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE contacts (
        id                 TEXT    PRIMARY KEY,
        name               TEXT    NOT NULL,
        phoneNumber        TEXT    NOT NULL,
        avatarPath         TEXT,
        note               TEXT,
        isTracking         INTEGER NOT NULL DEFAULT 1,
        isCurrentlyOnline  INTEGER NOT NULL DEFAULT 0,
        lastSeen           INTEGER,
        addedAt            INTEGER NOT NULL,
        totalSessions      INTEGER NOT NULL DEFAULT 0,
        totalOnlineMinutes INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE status_events (
        id              TEXT    PRIMARY KEY,
        contactId       TEXT    NOT NULL,
        status          TEXT    NOT NULL,
        timestamp       INTEGER NOT NULL,
        exactLastSeen   INTEGER,
        durationSeconds INTEGER,
        FOREIGN KEY (contactId) REFERENCES contacts (id) ON DELETE CASCADE
      )
    ''');

    // Index for fast per-contact event queries (activity feed, detail screen)
    await db.execute(
      'CREATE INDEX idx_events_contact '
      'ON status_events (contactId, timestamp DESC)',
    );

    // FIX 3: index for hasEventNearTime offline dedup — queries exactLastSeen
    // directly. Without this every sync iteration does a full table scan.
    await db.execute(
      'CREATE INDEX idx_events_last_seen '
      'ON status_events (contactId, status, exactLastSeen)',
    );
  }

  // ── Migrations ────────────────────────────────────────────
  //
  // FIX 1: v1 → v2 and v2 → v3 migrations are both handled here.
  //
  // v1 schema had no exactLastSeen column. Any user upgrading from v1 would
  // crash immediately on any query touching that column without this migration.
  //
  // v2 had exactLastSeen but was missing the idx_events_last_seen index,
  // causing full table scans on every offline dedup check.
  //
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2 / v3: add the exactLastSeen column that was missing in v1
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE status_events ADD COLUMN exactLastSeen INTEGER');
    }

    // v2 → v3: add the dedup index (safe to run even if column already existed)
    if (oldVersion < 3) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_events_last_seen '
        'ON status_events (contactId, status, exactLastSeen)',
      );
    }
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
        'UPDATE contacts '
        'SET isCurrentlyOnline=?, lastSeen=?, '
        '    totalSessions=totalSessions+?, '
        '    totalOnlineMinutes=totalOnlineMinutes+? '
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
    // REPLACE: bridge events use deterministic IDs (bridge_{contactId}_{ts})
    // so re-syncing is always safe — duplicate inserts overwrite with the same
    // row. Local UUID events are never overwritten because their IDs are unique.
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

  // ── Bridge history dedup ─────────────────────────────────

  /// Returns true if an equivalent [status] event already exists in SQLite,
  /// using the right identity strategy per status:
  ///
  ///   offline  →  exact match on exactLastSeen
  ///     WhatsApp sets this once when the contact goes offline — it is
  ///     identical across every delivery of the same event (WS, history-sync,
  ///     reconnect). Two deliveries can have different bridge `ts` values, so
  ///     a ±window on `timestamp` would miss the duplicate.
  ///
  ///   online   →  ±[windowSeconds] window on `timestamp`
  ///     Online events carry no lastSeen (null), so `timestamp` (bridge
  ///     recording time) is the only available anchor.
  ///
  Future<bool> hasEventNearTime(
    String contactId,
    DateTime timestamp, // exactLastSeen for offline, ts for online
    StatusType status, {
    int windowSeconds = 30, // only used for online events
  }) async {
    final db = await database;
    final statusStr = status == StatusType.online ? 'online' : 'offline';

    // FIX 2: offline events use exactLastSeen exact-match, not ts window
    if (status == StatusType.offline) {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM status_events '
        'WHERE contactId = ? AND status = ? AND exactLastSeen = ?',
        [contactId, statusStr, timestamp.millisecondsSinceEpoch],
      );
      return (rows.first['c'] as int) > 0;
    }

    // Online: window-based dedup on bridge recording timestamp
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

    // Online events have no lastSeen — timestamp is the correct column here.
    final result = await db.rawQuery(
      '''
      SELECT
        CAST(strftime('%H', datetime(timestamp / 1000, 'unixepoch')) AS INTEGER) AS hour,
        COUNT(*) AS count
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

    // FIX 4: offline rows grouped by exactLastSeen (when the contact actually
    // went offline) rather than by timestamp (when the bridge recorded it).
    // A contact who went offline at 23:58 but whose event was processed at
    // 00:02 would otherwise be bucketed into the wrong day.
    //
    // Online rows have no exactLastSeen so they still group by timestamp —
    // the COALESCE per-row picks the right column for each status.
    return await db.rawQuery(
      '''
      SELECT
        date(
          COALESCE(
            CASE WHEN status = 'offline' THEN exactLastSeen ELSE NULL END,
            timestamp
          ) / 1000,
          'unixepoch'
        ) AS day,
        COUNT(CASE WHEN status = 'online'  THEN 1 END) AS sessions,
        SUM  (CASE WHEN status = 'offline' THEN COALESCE(durationSeconds, 0) END) AS totalSeconds
      FROM status_events
      WHERE contactId = ? AND timestamp >= ?
      GROUP BY day
      ORDER BY day
    ''',
      [contactId, since.millisecondsSinceEpoch],
    );
  }
}
