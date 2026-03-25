// lib/services/tracker_service.dart
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
    // FIX 8: initialize() takes a positional argument — not 'settings:' named.
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
      if (c.isTracking) _bridge!.subscribePresence(c.phoneNumber, contactId: c.id);
    }
  }

  // ── App lifecycle ────────────────────────────────────────
  Future<void> onAppForeground() async {
    debugPrint('[Tracker] App foreground → syncing missed history');
    await BackgroundService.syncNow();
    await syncHistoryFromBridge();
  }

  void onAppBackground() {
    debugPrint('[Tracker] App background → WorkManager takes over');
  }

  // ── Bridge history sync ──────────────────────────────────
  Future<void> syncHistoryFromBridge() async {
    if (_bridge == null || _contacts.isEmpty || _syncInProgress) return;
    _syncInProgress = true;

    try {
      final ids = _contacts.where((c) => c.isTracking).map((c) => c.id).toList();

      if (ids.isEmpty) return;

      final historyMap = await _bridge!.getHistoryBulk(ids);
      if (historyMap == null || historyMap.isEmpty) return;

      int inserted = 0;
      final Map<String, int> sessionIncrments = {}; // Track session increments per contact
      final Map<String, int> minuteIncrments = {}; // Track minute increments per contact

      for (final entry in historyMap.entries) {
        final contactId = entry.key;
        final allEvents = entry.value.expand((d) => d.events).toList()..sort((a, b) => a.ts.compareTo(b.ts));

        sessionIncrments[contactId] = 0;
        minuteIncrments[contactId] = 0;

        DateTime? sessionStart;

        for (final e in allEvents) {
          final tsTimestamp = DateTime.fromMillisecondsSinceEpoch(e.ts);

          if (e.isOnline) {
            sessionStart = tsTimestamp;
            if (await _db.hasEventNearTime(contactId, tsTimestamp, StatusType.online)) {
              continue;
            }
            await _db.insertStatusEvent(
              StatusEvent(
                id: 'bridge_${contactId}_${e.ts}',
                contactId: contactId,
                status: StatusType.online,
                timestamp: tsTimestamp,
              ),
            );
            sessionIncrments[contactId] = (sessionIncrments[contactId] ?? 0) + 1;
            inserted++;
          } else if (e.isOffline) {
            final lastSeenMs = e.lastSeen ?? e.ts;
            final exactLastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenMs);
            final duration = sessionStart != null ? exactLastSeen.difference(sessionStart).inSeconds : null;
            sessionStart = null;

            if (await _db.hasEventNearTime(contactId, exactLastSeen, StatusType.offline)) {
              continue;
            }
            await _db.insertStatusEvent(
              StatusEvent(
                id: 'bridge_${contactId}_${e.ts}',
                contactId: contactId,
                status: StatusType.offline,
                timestamp: tsTimestamp,
                exactLastSeen: exactLastSeen,
                durationSeconds: duration,
              ),
            );
            if (duration != null && duration > 0) {
              minuteIncrments[contactId] = (minuteIncrments[contactId] ?? 0) + (duration / 60).round();
            }
            inserted++;
          }
          // composing / recording — skip
        }
      }

      // Update contact statistics for all new events
      for (final entry in sessionIncrments.entries) {
        final contactId = entry.key;
        final sessionIncrement = entry.value;
        final minuteIncrement = minuteIncrments[contactId] ?? 0;

        if (sessionIncrement > 0 || minuteIncrement > 0) {
          final contact = _contacts.firstWhere((c) => c.id == contactId, orElse: () => TrackedContact.empty());
          if (contact.id.isNotEmpty) {
            await _db.updateContactStatus(
              contactId,
              isOnline: contact.isCurrentlyOnline,
              lastSeen: contact.isCurrentlyOnline ? null : contact.lastSeen,
              addToSessions: sessionIncrement,
              addToMinutes: minuteIncrement,
            );
          }
        }
      }

      debugPrint('[Tracker] Foreground sync — $inserted new events');

      if (inserted > 0) {
        for (final contact in [..._contacts]) {
          if (!contact.isCurrentlyOnline) continue;
          final latest = await _db.getMostRecentEvent(contact.id);
          if (latest != null && latest.status == StatusType.offline) {
            debugPrint('[Tracker] Reconciling ${contact.name} → offline');
            await handlePresenceEvent(contact.id, isOnline: false, lastSeen: latest.exactLastSeen);
          }
        }
        await loadContacts();
      }
    } catch (e, stack) {
      debugPrint('[Tracker] Sync error: $e\n$stack');
    } finally {
      // FIX 10: always released — even on early return or exception
      _syncInProgress = false;
    }
  }

  // ── Handle real-time WS presence event ───────────────────
  void _handlePresenceFromBridge(PresenceEvent event) {
    // FIX 9: guard against composing / recording before touching any state.
    // event.isOnline  = status == 'available'
    // event.isOffline = status == 'unavailable'
    // composing and recording have both false — without this guard they call
    // handlePresenceEvent(isOnline: false) and silently mark the contact offline.
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

    handlePresenceEvent(contact.id, isOnline: event.isOnline, lastSeen: event.lastSeen);
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
      for (final c in _contacts) {
        _bridge!.unsubscribePresence(c.phoneNumber);
      }
    }
    BackgroundService.stop();
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  // ── Core presence handler ─────────────────────────────────
  Future<void> handlePresenceEvent(String contactId, {required bool isOnline, DateTime? lastSeen}) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;

    final contact = _contacts[idx];
    if (contact.isCurrentlyOnline == isOnline) return;

    final offlineAt = isOnline ? null : (lastSeen ?? DateTime.now());
    int? durationSeconds;

    if (!isOnline) {
      final since = _onlineSince[contactId];
      if (since != null && offlineAt != null) {
        durationSeconds = offlineAt.difference(since).inSeconds;
        if (durationSeconds < 0) durationSeconds = 0;
        _onlineSince.remove(contactId);
      }
    } else {
      _onlineSince[contactId] = DateTime.now();
    }

    final event = StatusEvent(
      id: _uuid.v4(),
      contactId: contactId,
      status: isOnline ? StatusType.online : StatusType.offline,
      timestamp: DateTime.now(),
      exactLastSeen: offlineAt,
      durationSeconds: durationSeconds,
    );
    await _db.insertStatusEvent(event);

    final addMinutes = durationSeconds != null ? (durationSeconds / 60).round() : 0;
    await _db.updateContactStatus(
      contactId,
      isOnline: isOnline,
      lastSeen: isOnline ? null : offlineAt,
      addToSessions: isOnline ? 1 : 0,
      addToMinutes: addMinutes,
    );

    _contacts[idx] = contact.copyWith(
      isCurrentlyOnline: isOnline,
      lastSeen: isOnline ? contact.lastSeen : offlineAt,
      totalSessions: isOnline ? contact.totalSessions + 1 : contact.totalSessions,
      totalOnlineMinutes: contact.totalOnlineMinutes + addMinutes,
    );
    notifyListeners();

    if (_notificationsEnabled && isOnline) _sendOnlineNotification(_contacts[idx]);
  }

  Future<void> _sendOnlineNotification(TrackedContact contact) async {
    // FIX 8: show() takes positional args:
    //   (int id, String? title, String? body, NotificationDetails? details)
    // Using named params (id:, title:, body:) is a compile error.
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
