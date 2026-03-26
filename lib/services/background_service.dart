// lib/services/background_service.dart
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

const _kPeriodicUniqueName = 'wastat_periodic_sync';
const _kOneshotUniqueName = 'wastat_oneshot_sync';
const _kTaskName = 'wastat.history_sync';
const _kLastSyncMs = 'wastat_last_bg_sync_ms';
const _kLastNotifyMs = 'wastat_last_notify_ms';

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
        return false;
      }
    }
    return true;
  });
}

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

    final prefs = await SharedPreferences.getInstance();
    final lastNotifyMs = prefs.getInt(_kLastNotifyMs) ?? 0;
    final lastSyncMs = prefs.getInt(_kLastSyncMs) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // FIX 1: initialize() takes a positional argument, not a named 'settings:' param.
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );

    int inserted = 0;
    int notified = 0;
    int latestEventMs = lastNotifyMs;

    for (final contact in tracked) {
      final rawDays = rawResults[contact.id] as List<dynamic>? ?? [];

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
            continue;
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

          // FIX 13: Also update contact status for online events (not just offline).
          // This ensures the contact's isCurrentlyOnline flag stays in sync during bg sync.
          final dbContact = await db.getContact(contact.id);
          if (dbContact != null && !dbContact.isCurrentlyOnline) {
            await db.updateContactStatus(contact.id, isOnline: true, addToSessions: 1);
            debugPrint('[BG] Updated ${contact.name} → online');
          }

          if (ts > lastNotifyMs && ts > lastSyncMs) {
            // FIX 2: show() takes positional args (int id, String? title,
            // String? body, NotificationDetails?). Named params cause a
            // compile error. title and body were also previously swapped.
            await notifications.show(
              id: contact.id.hashCode,
              title: '${contact.name} was online',
              body: _notifyBody(timestamp),
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
          // FIX 3: use lastSeen as the canonical identity for offline dedup.
          // Two deliveries of the same offline event (WS + history-sync)
          // share identical lastSeen but different bridge ts values — a
          // ts-based dedup window misses the duplicate when the gap is large.
          final lastSeenMs = e['lastSeen'] as int? ?? ts;
          final exactLastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenMs);

          // FIX 5: session duration = exactLastSeen − sessionStart.
          // Using timestamp (bridge recording time) inflates duration when the
          // bridge processes the event late.
          final duration = sessionStart != null ? exactLastSeen.difference(sessionStart).inSeconds : null;
          sessionStart = null;

          // Pass exactLastSeen as the dedup anchor (not timestamp)
          if (await db.hasEventNearTime(contact.id, exactLastSeen, StatusType.offline)) {
            continue;
          }

          // FIX 4: set exactLastSeen on the StatusEvent so UI and analytics
          // use WhatsApp's authoritative offline time, not the bridge ts.
          await db.insertStatusEvent(
            StatusEvent(
              id: 'bridge_${contact.id}_$ts',
              contactId: contact.id,
              status: StatusType.offline,
              timestamp: timestamp,
              exactLastSeen: exactLastSeen,
              durationSeconds: duration,
            ),
          );
          inserted++;

          final dbContact = await db.getContact(contact.id);
          if (dbContact != null && dbContact.isCurrentlyOnline) {
            final addMins = duration != null ? (duration / 60).round() : 0;
            await db.updateContactStatus(
              contact.id,
              isOnline: false,
              lastSeen: exactLastSeen, // authoritative offline time
              addToMinutes: addMins,
            );
            debugPrint('[BG] Reconciled ${contact.name} → offline');
          }
        }
        // composing / recording — skip
      }
    }

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

class BackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> start() async {
    await Workmanager().registerPeriodicTask(
      _kPeriodicUniqueName,
      _kTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected, requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
    debugPrint('[BGService] Periodic task registered (15 min)');
  }

  static Future<void> stop() async {
    await Workmanager().cancelByUniqueName(_kPeriodicUniqueName);
    await Workmanager().cancelByUniqueName(_kOneshotUniqueName);
    debugPrint('[BGService] Tasks cancelled');
  }

  static Future<void> syncNow() async {
    await Workmanager().registerOneOffTask(
      _kOneshotUniqueName,
      _kTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    debugPrint('[BGService] One-shot sync queued');
  }

  static Future<bool> get isRunning async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kLastSyncMs);
  }
}
