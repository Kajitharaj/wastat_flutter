// lib/services/tracker_service.dart
//
// Core tracking service. Bridges real WhatsApp presence events
// from the Node.js bridge into local SQLite logs + UI state.

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

  // Per-contact online-since tracking (for session duration)
  final Map<String, DateTime> _onlineSince = {};

  // Bridge subscription
  BridgeService? _bridge;
  StreamSubscription<PresenceEvent>? _presenceSub;

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

    if (bridge != null) {
      attachBridge(bridge);
    }
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: iOS);
    await _notifications.initialize(settings: settings);
  }

  // ── Bridge attachment ────────────────────────────────────
  void attachBridge(BridgeService bridge) {
    _presenceSub?.cancel();
    _bridge?.removeListener(_onBridgeStateChanged);
    _bridge = bridge;

    // Listen to real-time presence events
    _presenceSub = bridge.presenceStream.listen(_handlePresenceFromBridge);

    // Listen for WhatsApp auth state changes (QR scan, logout)
    bridge.addListener(_onBridgeStateChanged);

    // If WhatsApp is already authenticated right now, start immediately
    if (bridge.waState == WhatsAppState.connected) {
      _isRunning = true;
      _subscribeAllToBridge();
      notifyListeners();
    }
  }

  // Called whenever BridgeService notifies (waState changed, etc.)
  void _onBridgeStateChanged() {
    if (_bridge == null) return;
    if (_bridge!.waState == WhatsAppState.connected && !_isRunning) {
      debugPrint('[Tracker] WhatsApp connected → auto-starting tracking');
      _isRunning = true;
      _subscribeAllToBridge();
      notifyListeners();
    } else if (_bridge!.waState == WhatsAppState.disconnected && _isRunning) {
      debugPrint('[Tracker] WhatsApp disconnected → pausing tracking');
      _isRunning = false;
      notifyListeners();
    }
  }

  void _subscribeAllToBridge() {
    if (_bridge == null) return;
    debugPrint('[Tracker] Subscribing ${_contacts.length} contacts to bridge');
    for (final c in _contacts) {
      if (c.isTracking) {
        debugPrint('[Tracker] → subscribing ' + c.name + ' (' + c.phoneNumber + ')');
        _bridge!.subscribePresence(c.phoneNumber, contactId: c.id);
      }
    }
  }

  // ── Handle real presence event from bridge ────────────────
  void _handlePresenceFromBridge(PresenceEvent event) {
    debugPrint(
      '[Tracker] Presence received — contactId: ${event.contactId}, isOnline: ${event.isOnline}, status: ${event.status}',
    );
    debugPrint('[Tracker] Known contacts: ${_contacts.map((c) => c.id + ':' + c.name).join(', ')}');

    TrackedContact? contact;

    // 1. Match by contactId (UUID set by the bridge from our subscription)
    if (event.contactId != null) {
      try {
        contact = _contacts.firstWhere((c) => c.id == event.contactId);
        debugPrint('[Tracker] Matched by contactId: ${contact.name}');
      } catch (_) {
        debugPrint('[Tracker] contactId ${event.contactId} not found in local contacts');
      }
    }

    // 2. Fallback: match by phone digits
    // Note: event.phone may be LID digits on new WhatsApp — contactId match above is preferred
    if (contact == null) {
      final phone = event.phone.replaceAll(RegExp(r'\D'), '');
      debugPrint('[Tracker] Trying phone fallback with digits: $phone');
      try {
        contact = _contacts.firstWhere((c) => c.phoneNumber.replaceAll(RegExp(r'\D'), '') == phone);
        debugPrint('[Tracker] Matched by phone: ${contact.name}');
      } catch (_) {
        debugPrint('[Tracker] No phone match for $phone');
      }
    }

    if (contact == null) {
      debugPrint('[Tracker] No contact found — dropping presence event');
      return;
    }

    debugPrint('[Tracker] Dispatching presence for ${contact.name} — isOnline: ${event.isOnline}');
    handlePresenceEvent(contact.id, isOnline: event.isOnline);
  }

  // ── Contacts ─────────────────────────────────────────────
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

    // Subscribe to bridge if WhatsApp is connected
    // (regardless of _isRunning — bridge connection is the source of truth)
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
  Future<void> handlePresenceEvent(String contactId, {required bool isOnline}) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;

    final contact = _contacts[idx];
    if (contact.isCurrentlyOnline == isOnline) return; // no change

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

    // Persist event
    final event = StatusEvent(
      id: _uuid.v4(),
      contactId: contactId,
      status: isOnline ? StatusType.online : StatusType.offline,
      timestamp: now,
      durationSeconds: durationSeconds,
    );
    await _db.insertStatusEvent(event);

    // Update stats
    final addMinutes = durationSeconds != null ? (durationSeconds / 60).round() : 0;
    await _db.updateContactStatus(
      contactId,
      isOnline: isOnline,
      lastSeen: isOnline ? null : now,
      addToSessions: isOnline ? 1 : 0,
      addToMinutes: addMinutes,
    );

    final updated = contact.copyWith(
      isCurrentlyOnline: isOnline,
      lastSeen: isOnline ? contact.lastSeen : now,
      totalSessions: isOnline ? contact.totalSessions + 1 : contact.totalSessions,
      totalOnlineMinutes: contact.totalOnlineMinutes + addMinutes,
    );
    _contacts[idx] = updated;
    notifyListeners();

    if (_notificationsEnabled && isOnline) {
      _sendOnlineNotification(updated);
    }
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
