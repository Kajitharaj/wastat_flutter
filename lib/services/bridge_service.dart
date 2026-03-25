// lib/services/bridge_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;

enum BridgeState { disconnected, connecting, connected, error }

enum WhatsAppState { disconnected, qrPending, connected }

class PresenceEvent {
  final String jid;
  final String phone;
  final bool isOnline;
  final String status;
  final DateTime? lastSeen;
  final String? contactId;
  final DateTime timestamp;

  // FIX 8: these getters are required by tracker_service to distinguish
  // composing/recording from genuine offline events. Without them,
  // _handlePresenceFromBridge cannot guard against transient statuses.
  bool get isOffline => status == 'unavailable';
  bool get isComposing => status == 'composing';
  bool get isRecording => status == 'recording';

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

class BridgeHistoryDay {
  final String date;
  final List<BridgeHistoryEvent> events;
  BridgeHistoryDay({required this.date, required this.events});

  factory BridgeHistoryDay.fromJson(Map<String, dynamic> json) {
    final raw = (json['events'] as List<dynamic>? ?? []);
    return BridgeHistoryDay(
      date: json['date'] as String,
      events: raw.map((e) => BridgeHistoryEvent.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class BridgeHistoryEvent {
  final String jid;
  final String status;
  final int? lastSeen;
  final int ts;

  bool get isOnline => status == 'available';
  bool get isOffline => status == 'unavailable';
  bool get isComposing => status == 'composing';
  bool get isRecording => status == 'recording';

  BridgeHistoryEvent({required this.jid, required this.status, this.lastSeen, required this.ts});

  factory BridgeHistoryEvent.fromJson(Map<String, dynamic> json) {
    return BridgeHistoryEvent(
      jid: json['jid'] as String,
      status: json['status'] as String,
      lastSeen: json['lastSeen'] as int?,
      ts: json['ts'] as int,
    );
  }
}

class BridgeService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _keyBridgeHost = 'bridge_host';
  static const _keyApiSecret = 'api_secret';

  BridgeState _bridgeState = BridgeState.disconnected;
  WhatsAppState _waState = WhatsAppState.disconnected;
  String? _qrCodeBase64;
  String? _connectedPhone;
  String? _lastError;
  String _bridgeHost = '';
  String _apiSecret = '';
  bool _appInForeground = true;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;

  final _presenceController = StreamController<PresenceEvent>.broadcast();
  Stream<PresenceEvent> get presenceStream => _presenceController.stream;

  BridgeState get bridgeState => _bridgeState;
  WhatsAppState get waState => _waState;
  String? get qrCodeBase64 => _qrCodeBase64;
  String? get connectedPhone => _connectedPhone;
  String? get lastError => _lastError;
  String get bridgeHost => _bridgeHost;
  bool get isConfigured => _bridgeHost.isNotEmpty && _apiSecret.isNotEmpty;
  bool get isFullyConnected => _bridgeState == BridgeState.connected && _waState == WhatsAppState.connected;

  Future<void> initialize() async {
    _bridgeHost = await _storage.read(key: _keyBridgeHost) ?? '';
    _apiSecret = await _storage.read(key: _keyApiSecret) ?? '';
    if (isConfigured) await connectWebSocket();
  }

  void onAppForeground() {
    if (_appInForeground) return;
    _appInForeground = true;
    debugPrint('[Bridge] App foreground → reconnecting WS');
    if (isConfigured) connectWebSocket();
  }

  void onAppBackground() {
    if (!_appInForeground) return;
    _appInForeground = false;
    debugPrint('[Bridge] App background → disconnecting WS');
    _disconnectGracefully();
  }

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

  Future<void> connectWebSocket() async {
    if (_bridgeHost.isEmpty || !_appInForeground) return;

    disconnectWebSocket();
    _bridgeState = BridgeState.connecting;
    notifyListeners();

    try {
      final wsUrl = _bridgeHost.replaceFirst(RegExp(r'^http'), 'ws').replaceFirst(RegExp(r':\d+$'), ':8080');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSub = _channel!.stream.listen(_handleWsMessage, onError: _handleWsError, onDone: _handleWsDone);

      _bridgeState = BridgeState.connected;
      _reconnectAttempts = 0;
      _lastError = null;
      notifyListeners();

      _startPingTimer();
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

  void _disconnectGracefully() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _bridgeState = BridgeState.disconnected;
    _waState = WhatsAppState.disconnected;
    notifyListeners();
  }

  void _handleWsMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;

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
          final event = PresenceEvent.fromJson(msg);
          debugPrint('[Bridge] Presence — status: ${event.status}, contactId: ${event.contactId}');
          _presenceController.add(event);
        } catch (e) {
          debugPrint('[Bridge] Presence parse error: $e\nMsg: $msg');
        }
        break;
      case 'bridge_status':
        _waState = (msg['connected'] as bool? ?? false) ? WhatsAppState.connected : WhatsAppState.disconnected;
        notifyListeners();
        break;
      case 'pong':
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
    if (_appInForeground) _scheduleReconnect();
  }

  void _handleWsDone() {
    debugPrint('[Bridge] WS closed');
    _bridgeState = BridgeState.disconnected;
    notifyListeners();
    if (_appInForeground) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: (2 << _reconnectAttempts.clamp(0, 6)));
    _reconnectAttempts++;
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
      debugPrint('[Bridge] Send failed: $e');
    }
  }

  void subscribePresence(String phone, {String? contactId}) {
    // FIX 6: '?contactId' is invalid Dart. Use a collection-if instead.
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

  Future<Map<String, dynamic>?> getStatus() => _get('/status');

  Future<Map<String, dynamic>?> subscribeBulk(List<Map<String, String>> contacts) =>
      _post('/subscribe-bulk', {'contacts': contacts});

  Future<Map<String, dynamic>?> logout() => _post('/logout', {});

  Future<List<BridgeHistoryDay>?> getHistory(String contactId, {int days = 3}) async {
    final res = await _get('/history/$contactId?days=${days.clamp(1, 3)}');
    if (res == null) return null;
    return (res['history'] as List<dynamic>? ?? [])
        .map((d) => BridgeHistoryDay.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, List<BridgeHistoryDay>>?> getHistoryBulk(List<String> contactIds, {int days = 3}) async {
    if (contactIds.isEmpty) return {};
    final res = await _post('/history/bulk', {'contactIds': contactIds, 'days': days.clamp(1, 3)});
    if (res == null) return null;
    return (res['results'] as Map<String, dynamic>? ?? {}).map(
      (id, rawDays) => MapEntry(
        id,
        (rawDays as List<dynamic>).map((d) => BridgeHistoryDay.fromJson(d as Map<String, dynamic>)).toList(),
      ),
    );
  }

  Future<bool> testConnection(String host, String secret) async {
    try {
      final res = await http.get(Uri.parse('$host/health')).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _get(String path) async {
    try {
      final res = await http
          .get(Uri.parse('$_bridgeHost$path'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[Bridge] GET $path failed: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(Uri.parse('$_bridgeHost$path'), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[Bridge] POST $path failed: $e');
    }
    return null;
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json', 'x-api-secret': _apiSecret};

  @override
  void dispose() {
    disconnectWebSocket();
    _presenceController.close();
    super.dispose();
  }
}
