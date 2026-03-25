import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/status_event.dart';
import 'database_service.dart';

// ── Task identifiers ───────────────────────────────────────
const _kPeriodicUniqueName = 'wastat_periodic_sync';
const _kOneshotUniqueName = 'wastat_oneshot_sync';
const _kTaskName = 'wastat.history_sync';

// SharedPreferences keys
const _kLastSyncMs = 'wastat_last_bg_sync_ms';
const _kLastNotifyMs = 'wastat_last_notify_ms';

// ── Top-level callback — MUST be a top-level function ─────
// Runs in a separate isolate. No access to main app state.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('[BG] WorkManager fired: $taskName');

    if (taskName == _kTaskName || taskName == Workmanager.iOSBackgroundTask) {
      try {
        await _BackgroundSync.run();
        return true;
      } catch (e) {
        debugPrint('[BG] Sync error: $e');
        return false; // triggers WorkManager exponential backoff retry
      }
    }

    return true; // unknown task — return success so it isn't retried
  });
}

// ── Background sync logic ─────────────────────────────────
class _BackgroundSync {
  static Future<void> run() async {
    const storage = FlutterSecureStorage();
    final host = await storage.read(key: 'bridge_host') ?? '';
    final secret = await storage.read(key: 'api_secret') ?? '';

    if (host.isEmpty || secret.isEmpty) {
      debugPrint('[BG] No bridge config — skipping sync');
      return;
    }

    final db = DatabaseService();
    final contacts = await db.getAllContacts();
    final tracked = contacts.where((c) => c.isTracking).toList();
    if (tracked.isEmpty) return;

    // ── Fetch 3-day history from bridge ────────────────────
    final ids = tracked.map((c) => c.id).toList();
    final res = await http
        .post(
          Uri.parse('$host/history/bulk'),
          headers: {'Content-Type': 'application/json', 'x-api-secret': secret},
          body: jsonEncode({'contactIds': ids, 'days': 3}),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      debugPrint('[BG] /history/bulk returned ${res.statusCode}');
      return;
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final rawResults = data['results'] as Map<String, dynamic>? ?? {};

    // ── Timestamps for notification dedup ──────────────────
    final prefs = await SharedPreferences.getInstance();
    final lastNotifyMs = prefs.getInt(_kLastNotifyMs) ?? 0;
    final lastSyncMs = prefs.getInt(_kLastSyncMs) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // ── Init notifications ──────────────────────────────────
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );

    int inserted = 0;
    int notified = 0;
    int latestEventMs = lastNotifyMs;
    const uuid = Uuid();

    // ── Process each contact ────────────────────────────────
    for (final contact in tracked) {
      final rawDays = rawResults[contact.id] as List<dynamic>? ?? [];

      // Flatten all events and sort chronologically
      final allEvents = <Map<String, dynamic>>[];
      for (final day in rawDays) {
        for (final e in (day['events'] as List<dynamic>? ?? [])) {
          allEvents.add(e as Map<String, dynamic>);
        }
      }
      allEvents.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));

      DateTime? sessionStart;

      for (final e in allEvents) {
        final statusStr = e['status'] as String;
        final ts = e['ts'] as int;
        final timestamp = DateTime.fromMillisecondsSinceEpoch(ts);

        if (statusStr == 'available') {
          sessionStart = timestamp;

          if (await db.hasEventNearTime(contact.id, timestamp, StatusType.online)) {
            continue; // already recorded by foreground WS handler
          }

          await db.insertStatusEvent(
            StatusEvent(
              id: 'bridge_${contact.id}_$ts',
              contactId: contact.id,
              status: StatusType.online,
              timestamp: timestamp,
            ),
          );
          inserted++;

          // Notify only for events that are genuinely new since last sync
          if (ts > lastNotifyMs && ts > lastSyncMs) {
            await notifications.show(
              id: contact.id.hashCode,
              body: '${contact.name} was online',
              payload: _notifyBody(timestamp),
              notificationDetails: const NotificationDetails(
                android: AndroidNotificationDetails(
                  'wastat_online',
                  'Online Alerts',
                  channelDescription: 'Notifies when tracked contacts come online',
                  importance: Importance.high,
                  priority: Priority.high,
                  icon: '@mipmap/ic_launcher',
                ),
              ),
            );
            notified++;
            if (ts > latestEventMs) latestEventMs = ts;
          }
        } else if (statusStr == 'unavailable') {
          final duration = sessionStart != null ? timestamp.difference(sessionStart).inSeconds : null;
          sessionStart = null;

          if (await db.hasEventNearTime(contact.id, timestamp, StatusType.offline)) {
            continue;
          }

          await db.insertStatusEvent(
            StatusEvent(
              id: 'bridge_${contact.id}_$ts',
              contactId: contact.id,
              status: StatusType.offline,
              timestamp: timestamp,
              durationSeconds: duration,
            ),
          );
          inserted++;

          // Reconcile DB if the contact is still marked online
          final dbContact = await db.getContact(contact.id);
          if (dbContact != null && dbContact.isCurrentlyOnline) {
            final addMins = duration != null ? (duration / 60).round() : 0;
            await db.updateContactStatus(contact.id, isOnline: false, lastSeen: timestamp, addToMinutes: addMins);
            debugPrint('[BG] Reconciled ${contact.name} → offline');
          }
        }
        // composing / recording — skip, not persisted
      }
    }

    // ── Persist timestamps ──────────────────────────────────
    await prefs.setInt(_kLastSyncMs, nowMs);
    if (latestEventMs > lastNotifyMs) {
      await prefs.setInt(_kLastNotifyMs, latestEventMs);
    }

    debugPrint('[BG] Sync done — inserted: $inserted, notified: $notified');
  }

  static String _notifyBody(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 2) return 'Just came online on WhatsApp';
    if (diff.inMinutes < 60) return 'Was online ${diff.inMinutes}m ago on WhatsApp';
    if (diff.inHours < 24) return 'Was online ${diff.inHours}h ago on WhatsApp';
    return 'Was online on WhatsApp';
  }
}

// ── Public API (main isolate) ─────────────────────────────
class BackgroundService {
  /// Call once in main(), before runApp().
  /// Registers the callbackDispatcher with WorkManager.
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      // isInDebugMode is deprecated in 0.9.0 — use WorkmanagerDebug instead.
      // Leave it out; debug hooks can be set up separately if needed.
    );
  }

  /// Register (or replace) the 15-minute periodic sync task.
  static Future<void> start() async {
    await Workmanager().registerPeriodicTask(
      _kPeriodicUniqueName,
      _kTaskName,
      frequency: const Duration(minutes: 15), // Android minimum
      constraints: Constraints(networkType: NetworkType.connected, requiresBatteryNotLow: true),
      // 0.9.0 uses ExistingPeriodicWorkPolicy (not ExistingWorkPolicy)
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
    debugPrint('[BGService] Periodic task registered (15 min)');
  }

  /// Cancel the periodic task (call when user stops tracking or logs out).
  static Future<void> stop() async {
    await Workmanager().cancelByUniqueName(_kPeriodicUniqueName);
    await Workmanager().cancelByUniqueName(_kOneshotUniqueName);
    debugPrint('[BGService] Tasks cancelled');
  }

  /// Trigger an immediate one-shot sync — e.g. on app resume.
  /// Does not affect the periodic schedule.
  static Future<void> syncNow() async {
    await Workmanager().registerOneOffTask(
      _kOneshotUniqueName,
      _kTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    debugPrint('[BGService] One-shot sync queued');
  }

  /// True if a sync has ever completed (used to show status in Settings UI).
  static Future<bool> get isRunning async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kLastSyncMs);
  }
}
