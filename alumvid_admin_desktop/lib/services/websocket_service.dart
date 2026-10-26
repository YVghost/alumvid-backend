import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/telemetria.dart';
import 'api_service.dart';

typedef TelemetriaCallback = void Function(TelemetriaGps telemetria);
typedef TableroUpdateCallback = void Function();

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _pollingFallbackTimer;
  bool _isConnected = false;

  final List<TelemetriaCallback> _telemetriaListeners = [];
  final List<TableroUpdateCallback> _tableroListeners = [];

  bool get isConnected => _isConnected;

  void addTelemetriaListener(TelemetriaCallback listener) {
    _telemetriaListeners.add(listener);
  }

  void removeTelemetriaListener(TelemetriaCallback listener) {
    _telemetriaListeners.remove(listener);
  }

  void addTableroListener(TableroUpdateCallback listener) {
    _tableroListeners.add(listener);
  }

  void removeTableroListener(TableroUpdateCallback listener) {
    _tableroListeners.remove(listener);
  }

  Future<void> connect() async {
    _disconnectInternal();

    try {
      final host = await ApiService.getBaseHost();
      String baseWs = host.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
      if (baseWs.contains(':8080')) {
        baseWs = baseWs.replaceAll(':8080', ':8083');
      }
      final wsUri = Uri.parse('$baseWs/ws-logistica');

      _channel = WebSocketChannel.connect(wsUri);
      _isConnected = true;

      // Enviar frame de conexion STOMP
      _sendStompConnect();

      _subscription = _channel!.stream.listen(
        (data) {
          _handleIncomingStompMessage(data.toString());
        },
        onError: (err) {
          debugPrint('Error en WebSocket: $err');
          _onDisconnected();
        },
        onDone: () {
          debugPrint('WebSocket cerrado');
          _onDisconnected();
        },
      );
    } catch (e) {
      debugPrint('No se pudo establecer WebSocket nativo: $e');
      _onDisconnected();
    }

    // Iniciar polling de respaldo garantizado cada 6 segundos
    _iniciarPollingFallback();
  }

  void _sendStompConnect() {
    const connectFrame = 'CONNECT\naccept-version:1.1,1.0\nheart-beat:10000,10000\n\n\x00';
    _channel?.sink.add(connectFrame);
  }

  void _subscribeTopics() {
    // 1. Telemetria de choferes activos
    const subChoferes = 'SUBSCRIBE\nid:sub-0\ndestination:/topic/choferes-activos\n\n\x00';
    _channel?.sink.add(subChoferes);

    // 2. Notificaciones de actualizacion de pedidos o rutas
    const subTablero = 'SUBSCRIBE\nid:sub-1\ndestination:/topic/tablero-actualizado\n\n\x00';
    _channel?.sink.add(subTablero);
  }

  void _handleIncomingStompMessage(String message) {
    if (message.startsWith('CONNECTED')) {
      _isConnected = true;
      _subscribeTopics();
      return;
    }

    if (message.startsWith('MESSAGE')) {
      // Extraer payload JSON del body de STOMP
      final split = message.split('\n\n');
      if (split.length >= 2) {
        String body = split.sublist(1).join('\n\n');
        if (body.endsWith('\x00')) {
          body = body.substring(0, body.length - 1);
        }

        try {
          final data = jsonDecode(body.trim());
          if (data is Map<String, dynamic>) {
            if (data.containsKey('latitud') && data.containsKey('longitud')) {
              final telemetria = TelemetriaGps.fromJson(data);
              for (final listener in _telemetriaListeners) {
                listener(telemetria);
              }
            } else {
              // Notificacion de actualizacion
              _notifyTableroUpdate();
            }
          }
        } catch (_) {}
      }
    }
  }

  void _notifyTableroUpdate() {
    for (final listener in _tableroListeners) {
      listener();
    }
  }

  void _onDisconnected() {
    _isConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 8), () {
      connect();
    });
  }

  void _iniciarPollingFallback() {
    _pollingFallbackTimer?.cancel();
    // Dispara actualizacion periodica para que la interfaz este 100% al dia
    _pollingFallbackTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _notifyTableroUpdate();
    });
  }

  void _disconnectInternal() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _pollingFallbackTimer?.cancel();
    _disconnectInternal();
    _telemetriaListeners.clear();
    _tableroListeners.clear();
  }
}
