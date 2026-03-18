// lib/services/bridge_service.dart
//
// Connects Flutter to the Node.js Baileys bridge via:
//  - WebSocket  : real-time presence events
//  - HTTP REST  : subscribe/unsubscribe/status calls

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;

// ── Bridge connection state ──────────────────────────────
enum BridgeState { disconnected, connecting, connected, error }

enum WhatsAppState {
  disconnected,
  qrPending, // waiting for QR scan
  connected, // fully authenticated
}

// ── Event types from bridge ──────────────────────────────
class PresenceEvent {
  final String jid;
  final String phone;
  final bool isOnline;
  final String status;
  final DateTime? lastSeen;
  final String? contactId;
  final DateTime timestamp;

  PresenceEvent({
    required this.jid,
    required this.phone,
    required this.isOnline,
    required this.status,
    this.lastSeen,
    this.contactId,
    required this.timestamp,
  });

  factory PresenceEvent.fromJson(Map<String, dynamic> json) {
    return PresenceEvent(
      jid: json['jid'] as String,
      phone: json['phone'] as String,
      isOnline: json['isOnline'] as bool,
      status: json['status'] as String,
      lastSeen: json['lastSeen'] != null ? DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int) : null,
      contactId: json['contactId'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
    );
  }
}

class BridgeService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  // Config keys
  static const _keyBridgeHost = 'bridge_host';
  static const _keyApiSecret = 'api_secret';

  // State
  BridgeState _bridgeState = BridgeState.disconnected;
  WhatsAppState _waState = WhatsAppState.disconnected;
  String? _qrCodeBase64;
  String? _connectedPhone;
  String? _lastError;
  String _bridgeHost = '';
  String _apiSecret = '';

  // WebSocket
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;

  // Streams for presence events
  final _presenceController = StreamController<PresenceEvent>.broadcast();
  Stream<PresenceEvent> get presenceStream => _presenceController.stream;

  // Getters
  BridgeState get bridgeState => _bridgeState;
  WhatsAppState get waState => _waState;
  String? get qrCodeBase64 => _qrCodeBase64;
  String? get connectedPhone => _connectedPhone;
  String? get lastError => _lastError;
  String get bridgeHost => _bridgeHost;
  bool get isConfigured => _bridgeHost.isNotEmpty && _apiSecret.isNotEmpty;
  bool get isFullyConnected => _bridgeState == BridgeState.connected && _waState == WhatsAppState.connected;

  // ── Init ──────────────────────────────────────────────
  Future<void> initialize() async {
    _bridgeHost = await _storage.read(key: _keyBridgeHost) ?? '';
    _apiSecret = await _storage.read(key: _keyApiSecret) ?? '';

    if (isConfigured) {
      await connectWebSocket();
    }
  }

  // ── Save config ────────────────────────────────────────
  Future<void> saveConfig({required String bridgeHost, required String apiSecret}) async {
    _bridgeHost = bridgeHost.trim().replaceAll(RegExp(r'/$'), '');
    _apiSecret = apiSecret.trim();

    await _storage.write(key: _keyBridgeHost, value: _bridgeHost);
    await _storage.write(key: _keyApiSecret, value: _apiSecret);

    notifyListeners();
    await connectWebSocket();
  }

  Future<void> clearConfig() async {
    await _storage.deleteAll();
    _bridgeHost = '';
    _apiSecret = '';
    disconnectWebSocket();
    notifyListeners();
  }

  // ── WebSocket connection ───────────────────────────────
  Future<void> connectWebSocket() async {
    if (_bridgeHost.isEmpty) return;

    disconnectWebSocket();
    _bridgeState = BridgeState.connecting;
    notifyListeners();

    try {
      // Convert http://host:3000 → ws://host:8080
      final wsUrl = _bridgeHost.replaceFirst(RegExp(r'^http'), 'ws').replaceFirst(RegExp(r':\d+$'), ':8080');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _wsSub = _channel!.stream.listen(_handleWsMessage, onError: _handleWsError, onDone: _handleWsDone);

      _bridgeState = BridgeState.connected;
      _reconnectAttempts = 0;
      _lastError = null;
      notifyListeners();

      _startPingTimer();

      // Request current status immediately
      _sendWsMessage({'type': 'get_status', 'secret': _apiSecret});
    } catch (e) {
      _handleWsError(e);
    }
  }

  void disconnectWebSocket() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _bridgeState = BridgeState.disconnected;
  }

  // ── WebSocket message handler ──────────────────────────
  void _handleWsMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;
    debugPrint('[Bridge] WS received: $type');

    switch (type) {
      case 'qr_code':
        _qrCodeBase64 = msg['qr'] as String?;
        _waState = WhatsAppState.qrPending;
        notifyListeners();
        break;

      case 'auth_success':
        _waState = WhatsAppState.connected;
        _connectedPhone = msg['phoneNumber'] as String?;
        _qrCodeBase64 = null;
        notifyListeners();
        break;

      case 'auth_logout':
        _waState = WhatsAppState.disconnected;
        _connectedPhone = null;
        notifyListeners();
        break;

      case 'presence':
        try {
          debugPrint('[Bridge] Presence payload: $msg');
          final event = PresenceEvent.fromJson(msg);
          debugPrint(
            '[Bridge] Presence parsed — isOnline: ${event.isOnline}, contactId: ${event.contactId}, phone: ${event.phone}',
          );
          _presenceController.add(event);
          debugPrint('[Bridge] Presence added to stream — listeners: ${_presenceController.hasListener}');
        } catch (e, stack) {
          debugPrint('[Bridge] ERROR parsing presence event: $e');
          debugPrint('[Bridge] Stack: $stack');
          debugPrint('[Bridge] Raw msg was: $msg');
        }
        break;

      case 'bridge_status':
        final connected = msg['connected'] as bool? ?? false;
        _waState = connected ? WhatsAppState.connected : WhatsAppState.disconnected;
        notifyListeners();
        break;

      case 'pong':
        // Heartbeat received — connection healthy
        break;

      case 'error':
        _lastError = msg['message'] as String?;
        notifyListeners();
        break;
    }
  }

  void _handleWsError(dynamic error) {
    debugPrint('[Bridge] WS error: $error');
    _bridgeState = BridgeState.error;
    _lastError = error.toString();
    notifyListeners();
    _scheduleReconnect();
  }

  void _handleWsDone() {
    debugPrint('[Bridge] WS connection closed');
    _bridgeState = BridgeState.disconnected;
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = Duration(
      seconds: (2 << _reconnectAttempts.clamp(0, 6)), // 2,4,8,16...128s
    );
    _reconnectAttempts++;
    debugPrint('[Bridge] Reconnecting in ${delay.inSeconds}s...');
    _reconnectTimer = Timer(delay, connectWebSocket);
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _sendWsMessage({'type': 'ping', 'secret': _apiSecret});
    });
  }

  void _sendWsMessage(Map<String, dynamic> msg) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(msg));
    } catch (e) {
      debugPrint('[Bridge] Failed to send WS message: $e');
    }
  }

  // ── WebSocket subscribe calls ──────────────────────────
  void subscribePresence(String phone, {String? contactId}) {
    _sendWsMessage({
      'type': 'subscribe',
      'secret': _apiSecret,
      'phone': phone,
      if (contactId != null) 'contactId': contactId,
    });
  }

  void unsubscribePresence(String phone) {
    _sendWsMessage({'type': 'unsubscribe', 'secret': _apiSecret, 'phone': phone});
  }

  // ── HTTP REST calls ────────────────────────────────────
  Future<Map<String, dynamic>?> getStatus() => _get('/status');

  Future<Map<String, dynamic>?> subscribeBulk(List<Map<String, String>> contacts) =>
      _post('/subscribe-bulk', {'contacts': contacts});

  Future<Map<String, dynamic>?> logout() => _post('/logout', {});

  Future<Map<String, dynamic>?> _get(String path) async {
    try {
      final uri = Uri.parse('$_bridgeHost$path');
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[Bridge] HTTP GET $path failed: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _post(String path, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$_bridgeHost$path');
      final res = await http.post(uri, headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[Bridge] HTTP POST $path failed: $e');
    }
    return null;
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json', 'x-api-secret': _apiSecret};

  // ── Test connection ────────────────────────────────────
  Future<bool> testConnection(String host, String secret) async {
    try {
      final uri = Uri.parse('$host/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    disconnectWebSocket();
    _presenceController.close();
    super.dispose();
  }
}
