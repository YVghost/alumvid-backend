import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

typedef VoidCallback = void Function();

class WebSocketMobileService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _isConnected = false;

  final String choferId;
  final VoidCallback onSesionRevocada;

  WebSocketMobileService({
    required this.choferId,
    required this.onSesionRevocada,
  });

  bool get isConnected => _isConnected;

  void connect() {
    _disconnectInternal();

    try {
      final baseUrl = ApiService.baseUrl;
      final uri = Uri.parse(baseUrl);
      final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
      final wsUri = Uri.parse('$wsScheme://${uri.host}:${uri.port}/ws-logistica/websocket');

      _channel = WebSocketChannel.connect(wsUri);
      _isConnected = true;

      // Frame STOMP CONNECT
      const connectFrame = 'CONNECT\naccept-version:1.1,1.0\nheart-beat:10000,10000\n\n\x00';
      _channel?.sink.add(connectFrame);

      _subscription = _channel!.stream.listen(
        (data) {
          _handleIncomingStompMessage(data.toString());
        },
        onError: (err) {
          debugPrint('[WS-Mobile] Error en WebSocket: $err');
          _onDisconnected();
        },
        onDone: () {
          debugPrint('[WS-Mobile] WebSocket cerrado');
          _onDisconnected();
        },
      );
    } catch (e) {
      debugPrint('[WS-Mobile] No se pudo conectar a WebSocket: $e');
      _onDisconnected();
    }
  }

  void _subscribeTopics() {
    // 1. Sesión revocada directa para este chofer
    final subChofer = 'SUBSCRIBE\nid:sub-rev-0\ndestination:/topic/choferes/$choferId/sesion-revocada\n\n\x00';
    _channel?.sink.add(subChofer);

    // 2. Broadcast de sesiones revocadas
    const subBroadcast = 'SUBSCRIBE\nid:sub-rev-1\ndestination:/topic/sesiones-revocadas\n\n\x00';
    _channel?.sink.add(subBroadcast);
  }

  void _handleIncomingStompMessage(String message) {
    if (message.startsWith('CONNECTED')) {
      _isConnected = true;
      _subscribeTopics();
      return;
    }

    if (message.startsWith('MESSAGE')) {
      if (message.contains('sesion-revocada') || message.contains('SESION_REVOCADA')) {
        // Verificar si es para este chofer o global
        if (message.contains(choferId) || !message.contains('userId')) {
          debugPrint('[WS-Mobile] ¡Sesión revocada detectada por WebSocket!');
          onSesionRevocada();
        }
      }
    }
  }

  void _onDisconnected() {
    _isConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isConnected) connect();
    });
  }

  void _disconnectInternal() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
  }

  void dispose() {
    _disconnectInternal();
  }
}
