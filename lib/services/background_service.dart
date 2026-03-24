// lib/services/background_service.dart
//
// Runs a foreground service on Android that keeps the WebSocket
// connection to the bridge alive even when the app is killed.
//
// Architecture:
//   Main isolate  ──► FlutterForegroundTask starts service
//   Service isolate ──► WS connection ──► receives presence events
//                    ──► saves to SQLite directly
//                    ──► fires local notifications
//
// The service isolate runs completely independently of the UI.
// When the user opens the app, it reads from the same SQLite DB
// and shows all events that happened in the background.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import '../models/status_event.dart';
import 'database_service.dart';

// ── Task handler — runs in background isolate ────────────
// This class is instantiated in the background isolate.
// It has NO access to the main app's Provider/state — it talks
// directly to SQLite and sends local notifications.
@pragma('vm:entry-point')
class WaStatTaskHandler extends TaskHandler {
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  final _db = DatabaseService();
  final _uuid = const Uuid();
  final _notifications = FlutterLocalNotificationsPlugin();

  // Per-contact online-since map for session duration tracking
  final Map<String, DateTime> _onlineSince = {};

  String _bridgeHost = '';
  String _apiSecret = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BG] Background task started');
    await _initNotifications();
    await _loadConfig();
    _connect();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Called every repeatInterval — use as a watchdog
    if (_channel == null) {
      debugPrint('[BG] Watchdog: not connected, reconnecting...');
      _connect();
    }
  }

  @override
  @override
  Future<void> onDestroy(DateTime timestamp, bool isPermanent) async {
    debugPrint('[BG] Background task destroyed (permanent: $isPermanent)');
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
  }

  // ── Init ──────────────────────────────────────────────
  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(settings: settings);
  }

  Future<void> _loadConfig() async {
    // flutter_secure_storage works across isolates via platform channel
    const storage = FlutterSecureStorage();
    _bridgeHost = await storage.read(key: 'bridge_host') ?? '';
    _apiSecret = await storage.read(key: 'api_secret') ?? '';
    debugPrint('[BG] Config loaded — host: $_bridgeHost');
  }

  // ── WebSocket connection ───────────────────────────────
  void _connect() {
    if (_bridgeHost.isEmpty || _apiSecret.isEmpty) {
      debugPrint('[BG] No bridge config — cannot connect');
      return;
    }

    _disconnect();

    try {
      final wsUrl = _bridgeHost.replaceFirst(RegExp(r'^http'), 'ws').replaceFirst(RegExp(r':\d+$'), ':8080');

      debugPrint('[BG] Connecting to $wsUrl');
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _wsSub = _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('[BG] WS error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[BG] WS closed');
          _scheduleReconnect();
        },
      );

      // Send ping to authenticate + signal our presence
      _send({'type': 'ping', 'secret': _apiSecret});

      // Re-subscribe all tracked contacts
      _resubscribeAll();

      // Keep-alive ping every 25s
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        _send({'type': 'ping', 'secret': _apiSecret});
      });

      _reconnectAttempts = 0;
      debugPrint('[BG] Connected successfully');
    } catch (e) {
      debugPrint('[BG] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _disconnect() {
    _pingTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: (2 << _reconnectAttempts.clamp(0, 6)));
    _reconnectAttempts++;
    debugPrint('[BG] Reconnecting in ${delay.inSeconds}s...');
    _reconnectTimer = Timer(delay, _connect);
  }

  // ── Subscribe all tracked contacts ────────────────────
  Future<void> _resubscribeAll() async {
    final contacts = await _db.getAllContacts();
    for (final contact in contacts) {
      if (contact.isTracking) {
        _send({'type': 'subscribe', 'secret': _apiSecret, 'phone': contact.phoneNumber, 'contactId': contact.id});
      }
    }
    debugPrint('[BG] Resubscribed ${contacts.length} contacts');
  }

  // ── Handle incoming WS messages ────────────────────────
  void _onMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;

    if (type == 'presence') {
      _handlePresence(msg);
    }
    // Ignore pong, bridge_status etc. in background
  }

  // ── Handle presence event ─────────────────────────────
  Future<void> _handlePresence(Map<String, dynamic> msg) async {
    final contactId = msg['contactId'] as String?;
    final isOnline = msg['isOnline'] as bool? ?? false;
    final status = msg['status'] as String? ?? '';

    // Only care about available/unavailable
    if (status != 'available' && status != 'unavailable') return;
    if (contactId == null) return;

    final contact = await _db.getContact(contactId);
    if (contact == null) return;
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

    // Persist event to SQLite
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

    debugPrint('[BG] ${contact.name} is now ${isOnline ? "ONLINE" : "offline"}');

    // Fire notification when contact comes online
    if (isOnline) {
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
        ),
      );
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }
}

// ── Main isolate API ──────────────────────────────────────
// Called from the UI to start/stop the foreground service.
class BackgroundService {
  // Initialize ForegroundTask config — call once in main()
  static void initialize() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'wastat_tracking',
        channelName: 'WaStat Tracking',
        channelDescription: 'Keeps WhatsApp status tracking running in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          60000, // watchdog every 60s
        ),
        autoRunOnBoot: true, // restart after phone reboot
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // Start the foreground service
  static Future<bool> start() async {
    // Request permissions first
    final permResult = await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    debugPrint('[BGService] Battery opt ignored: $permResult');

    if (await FlutterForegroundTask.isRunningService) {
      debugPrint('[BGService] Already running');
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: 'WaStat is tracking',
      notificationText: 'Monitoring WhatsApp online status',
      callback: startCallback,
    );

    debugPrint('[BGService] Start result: $result');
    return ServiceRequestResult is ServiceRequestSuccess;
  }

  // Stop the foreground service
  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
    debugPrint('[BGService] Stopped');
  }

  // Update notification text (e.g. "3 contacts online")
  static Future<void> updateNotification(String text) async {
    await FlutterForegroundTask.updateService(notificationTitle: 'WaStat is tracking', notificationText: text);
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}

// ── Entry point for background isolate ────────────────────
// Must be a top-level function annotated with @pragma
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(WaStatTaskHandler());
}
