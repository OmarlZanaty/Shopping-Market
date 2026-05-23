import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/api_constants.dart';
import '../storage/secure_storage_keys.dart';

/// Connects to the backend's Django Channels endpoints used by the agent.
/// Each agent role subscribes to its own room:
///   /ws/agent/<agent_id>/    — direct messages for this agent
///   /ws/orders/<order_id>/   — joined ad-hoc when viewing an order
///
/// Auto-reconnects with exponential backoff. Pushes parsed events into the
/// `events` broadcast stream — UIs subscribe via Riverpod providers.
class AgentWebSocketService {
  AgentWebSocketService._();
  static final AgentWebSocketService I = AgentWebSocketService._();

  WebSocketChannel? _channel;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  Timer? _reconnect;
  int _backoffSec = 1;
  bool _shouldReconnect = true;

  /// Connect to /ws/agent/<agentId>/.
  Future<void> connectAgent(String agentId) async {
    _shouldReconnect = true;
    await _connect('/ws/agent/$agentId/');
  }

  Future<void> _connect(String path) async {
    final storage = const FlutterSecureStorage();
    final token = await storage.read(key: SecureStorageKeys.accessToken);
    final uri = Uri.parse('${ApiConstants.wsBaseUrl}$path?token=${token ?? ""}');
    try {
      _channel = WebSocketChannel.connect(uri);
      _backoffSec = 1;
      debugPrint('[Agent WS] connected $uri');
      _channel!.stream.listen(
        (raw) {
          try {
            final parsed = jsonDecode(raw as String) as Map<String, dynamic>;
            _events.add(parsed);
          } catch (e) {
            debugPrint('[Agent WS] parse error: $e');
          }
        },
        onError: (e) {
          debugPrint('[Agent WS] error: $e');
          _scheduleReconnect(path);
        },
        onDone: () {
          debugPrint('[Agent WS] disconnected');
          _scheduleReconnect(path);
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[Agent WS] connect failed: $e');
      _scheduleReconnect(path);
    }
  }

  void _scheduleReconnect(String path) {
    if (!_shouldReconnect) return;
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: _backoffSec), () {
      _backoffSec = (_backoffSec * 2).clamp(1, 60);
      _connect(path);
    });
  }

  void send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnect?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _events.close();
    disconnect();
  }
}
