// lib/services/tracker_service.dart
//
// Core tracking service.
//
// Foreground: WebSocket delivers ONLINE events → logged immediately.
// Background: WorkManager polls bridge history → writes to SQLite.
// On app resume: one-shot history sync catches anything missed while backgrounded.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';
import '../models/contact.dart';
import '../models/status_event.dart';
import 'database_service.dart';
import 'bridge_service.dart';
import 'background_service.dart';

class TrackerService extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final _uuid = const Uuid();

  List<TrackedContact> _contacts = [];
  bool _isRunning = false;
  bool _notificationsEnabled = true;

  final Map<String, DateTime> _onlineSince = {};

  BridgeService? _bridge;
  StreamSubscription<PresenceEvent>? _presenceSub;

  // Prevents two concurrent syncs
  bool _syncInProgress = false;

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  List<TrackedContact> get contacts => List.unmodifiable(_contacts);
  bool get isRunning => _isRunning;
  bool get notificationsEnabled => _notificationsEnabled;
  int get onlineCount => _contacts.where((c) => c.isCurrentlyOnline).length;
  int get trackedCount => _contacts.where((c) => c.isTracking).length;

  // ── Init ─────────────────────────────────────────────────
  Future<void> initialize({BridgeService? bridge}) async {
    await _initNotifications();
    await loadContacts();
    if (bridge != null) attachBridge(bridge);
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: iOS);
    await _notifications.initialize(settings: settings);
  }

  // ── Bridge attachment ─────────────────────────────────────
  void attachBridge(BridgeService bridge) {
    _presenceSub?.cancel();
    _bridge?.removeListener(_onBridgeStateChanged);
    _bridge = bridge;
    _presenceSub = bridge.presenceStream.listen(_handlePresenceFromBridge);
    bridge.addListener(_onBridgeStateChanged);

    if (bridge.waState == WhatsAppState.connected) {
      _isRunning = true;
      _subscribeAllToBridge();
      notifyListeners();
    }
  }

  void _onBridgeStateChanged() {
    if (_bridge == null) return;

    if (_bridge!.waState == WhatsAppState.connected && !_isRunning) {
      debugPrint('[Tracker] WhatsApp connected → starting tracking');
      _isRunning = true;
      _subscribeAllToBridge();
      notifyListeners();
    } else if (_bridge!.waState == WhatsAppState.disconnected && _isRunning) {
      debugPrint('[Tracker] WhatsApp disconnected → pausing');
      _isRunning = false;
      notifyListeners();
    }
  }

  void _subscribeAllToBridge() {
    if (_bridge == null) return;
    for (final c in _contacts) {
      if (c.isTracking) {
        _bridge!.subscribePresence(c.phoneNumber, contactId: c.id);
      }
    }
  }

  // ── App lifecycle callbacks ──────────────────────────────
  // Called by AppLifecycleObserver in main.dart.

  /// App moved to foreground: reconnect WS + sync any history missed.
  Future<void> onAppForeground() async {
    debugPrint('[Tracker] App foreground → syncing missed history');
    // Trigger immediate WorkManager one-shot (catches background events)
    await BackgroundService.syncNow();
    // Also do an in-process sync for immediate UI update
    await syncHistoryFromBridge();
  }

  /// App moved to background: WS will be disconnected by BridgeService.
  void onAppBackground() {
    debugPrint('[Tracker] App background → WorkManager takes over');
    // Nothing to do here — BridgeService handles WS teardown.
    // WorkManager is already scheduled.
  }

  // ── Bridge history sync (foreground, in-process) ──────────
  //
  // Fetches the 3-day history from the bridge via HTTP and merges
  // any missing events into local SQLite. Called on app resume so
  // the UI reflects everything that happened in the background.
  Future<void> syncHistoryFromBridge() async {
    if (_bridge == null || _contacts.isEmpty || _syncInProgress) return;
    _syncInProgress = true;

    try {
      final ids = _contacts.where((c) => c.isTracking).map((c) => c.id).toList();
      if (ids.isEmpty) return;

      final historyMap = await _bridge!.getHistoryBulk(ids);
      if (historyMap == null || historyMap.isEmpty) return;

      int inserted = 0;

      for (final entry in historyMap.entries) {
        final contactId = entry.key;
        final allEvents = entry.value.expand((d) => d.events).toList()..sort((a, b) => a.ts.compareTo(b.ts));

        DateTime? sessionStart;

        for (final e in allEvents) {
          final timestamp = DateTime.fromMillisecondsSinceEpoch(e.ts);

          if (e.isOnline) {
            sessionStart = timestamp;
            if (await _db.hasEventNearTime(contactId, timestamp, StatusType.online)) {
              continue;
            }
            await _db.insertStatusEvent(
              StatusEvent(
                id: 'bridge_${contactId}_${e.ts}',
                contactId: contactId,
                status: StatusType.online,
                timestamp: timestamp,
              ),
            );
            inserted++;
          } else if (e.isOffline) {
            final duration = sessionStart != null ? timestamp.difference(sessionStart).inSeconds : null;
            sessionStart = null;

            if (await _db.hasEventNearTime(contactId, timestamp, StatusType.offline)) {
              continue;
            }
            await _db.insertStatusEvent(
              StatusEvent(
                id: 'bridge_${contactId}_${e.ts}',
                contactId: contactId,
                status: StatusType.offline,
                timestamp: timestamp,
                durationSeconds: duration,
              ),
            );
            inserted++;
          }
        }
      }

      debugPrint('[Tracker] Foreground sync — $inserted new events');

      if (inserted > 0) {
        // Reconcile contacts still marked online whose latest event is offline
        for (final contact in [..._contacts]) {
          if (!contact.isCurrentlyOnline) continue;
          final latest = await _db.getMostRecentEvent(contact.id);
          if (latest != null && latest.status == StatusType.offline) {
            debugPrint('[Tracker] Reconciling ${contact.name} → offline');
            await handlePresenceEvent(contact.id, isOnline: false);
          }
        }
        await loadContacts();
      }
    } catch (e, stack) {
      debugPrint('[Tracker] Sync error: $e\n$stack');
    } finally {
      _syncInProgress = false;
    }
  }

  // ── Handle real-time presence event from WS ───────────────
  //
  // The bridge now broadcasts ALL statuses while the app is foreground:
  //   available   → mark online, log session start, notify
  //   unavailable → mark offline, compute session duration
  //   composing / recording → no DB write (could drive a typing indicator later)
  void _handlePresenceFromBridge(PresenceEvent event) {
    TrackedContact? contact;

    if (event.contactId != null) {
      try {
        contact = _contacts.firstWhere((c) => c.id == event.contactId);
      } catch (_) {}
    }

    if (contact == null) {
      final phone = event.phone.replaceAll(RegExp(r'\D'), '');
      try {
        contact = _contacts.firstWhere((c) => c.phoneNumber.replaceAll(RegExp(r'\D'), '') == phone);
      } catch (_) {}
    }

    if (contact == null) {
      debugPrint('[Tracker] No match for presence event — dropping');
      return;
    }

    handlePresenceEvent(contact.id, isOnline: event.isOnline);
    // composing / recording: skip DB write for now
  }

  // ── Contacts CRUD ─────────────────────────────────────────
  Future<void> loadContacts() async {
    _contacts = await _db.getAllContacts();
    notifyListeners();
  }

  Future<TrackedContact> addContact({required String name, required String phoneNumber, String? note}) async {
    final contact = TrackedContact(
      id: _uuid.v4(),
      name: name,
      phoneNumber: _normalizePhone(phoneNumber),
      note: note,
      addedAt: DateTime.now(),
    );
    await _db.insertContact(contact);
    _contacts.insert(0, contact);
    notifyListeners();

    if (_bridge != null && _bridge!.waState == WhatsAppState.connected) {
      _bridge!.subscribePresence(contact.phoneNumber, contactId: contact.id);
    }
    return contact;
  }

  Future<void> updateContact(TrackedContact contact) async {
    await _db.updateContact(contact);
    final idx = _contacts.indexWhere((c) => c.id == contact.id);
    if (idx != -1) {
      _contacts[idx] = contact;
      notifyListeners();
    }
  }

  Future<void> deleteContact(String id) async {
    final contact = _contacts.firstWhere((c) => c.id == id, orElse: () => throw Exception('not found'));
    _bridge?.unsubscribePresence(contact.phoneNumber);
    await _db.deleteContact(id);
    _contacts.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  Future<void> toggleTracking(String contactId) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    final contact = _contacts[idx];
    final updated = contact.copyWith(isTracking: !contact.isTracking);
    await _db.updateContact(updated);
    _contacts[idx] = updated;
    notifyListeners();

    if (updated.isTracking && _isRunning && _bridge != null) {
      _bridge!.subscribePresence(updated.phoneNumber, contactId: updated.id);
    } else if (!updated.isTracking) {
      _bridge?.unsubscribePresence(updated.phoneNumber);
    }
  }

  // ── Global start / stop ──────────────────────────────────
  void startTracking() {
    _isRunning = true;
    _subscribeAllToBridge();
    BackgroundService.start();
    notifyListeners();
  }

  void stopTracking() {
    _isRunning = false;
    if (_bridge != null) {
      for (final c in _contacts) _bridge!.unsubscribePresence(c.phoneNumber);
    }
    BackgroundService.stop();
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  // ── Core presence handler ─────────────────────────────────
  Future<void> handlePresenceEvent(String contactId, {required bool isOnline}) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;

    final contact = _contacts[idx];
    if (contact.isCurrentlyOnline == isOnline) return;

    final now = DateTime.now();
    int? durationSeconds;

    if (!isOnline) {
      final since = _onlineSince[contactId];
      if (since != null) {
        durationSeconds = now.difference(since).inSeconds;
        _onlineSince.remove(contactId);
      }
    } else {
      _onlineSince[contactId] = now;
    }

    final event = StatusEvent(
      id: _uuid.v4(),
      contactId: contactId,
      status: isOnline ? StatusType.online : StatusType.offline,
      timestamp: now,
      durationSeconds: durationSeconds,
    );
    await _db.insertStatusEvent(event);

    final addMinutes = durationSeconds != null ? (durationSeconds / 60).round() : 0;
    await _db.updateContactStatus(
      contactId,
      isOnline: isOnline,
      lastSeen: isOnline ? null : now,
      addToSessions: isOnline ? 1 : 0,
      addToMinutes: addMinutes,
    );

    _contacts[idx] = contact.copyWith(
      isCurrentlyOnline: isOnline,
      lastSeen: isOnline ? contact.lastSeen : now,
      totalSessions: isOnline ? contact.totalSessions + 1 : contact.totalSessions,
      totalOnlineMinutes: contact.totalOnlineMinutes + addMinutes,
    );
    notifyListeners();

    if (_notificationsEnabled && isOnline) _sendOnlineNotification(_contacts[idx]);
  }

  Future<void> _sendOnlineNotification(TrackedContact contact) async {
    await _notifications.show(
      id: contact.hashCode,
      title: '${contact.name} is online',
      body: 'Just came online on WhatsApp',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'wastat_online',
          'Online Alerts',
          channelDescription: 'Notifies when tracked contacts come online',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────
  String _normalizePhone(String phone) => phone.replaceAll(RegExp(r'[^\d+]'), '');

  Future<List<StatusEvent>> getEventsForContact(String contactId, {int? limit, DateTime? since}) =>
      _db.getEventsForContact(contactId, limit: limit, since: since);

  Future<Map<int, int>> getHourlyDistribution(String contactId) => _db.getHourlyDistribution(contactId);

  Future<List<Map<String, dynamic>>> getDailyOnlineTime(String contactId, int days) =>
      _db.getDailyOnlineTime(contactId, days);

  TrackedContact? getContact(String id) {
    try {
      return _contacts.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    _bridge?.removeListener(_onBridgeStateChanged);
    super.dispose();
  }
}
