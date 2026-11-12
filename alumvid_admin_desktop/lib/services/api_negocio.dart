import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'api_service.dart';

/// Error de negocio con el mensaje que envía el backend.
class ApiError implements Exception {
  ApiError(this.status, this.mensaje);
  final int status;
  final String mensaje;
  @override
  String toString() => mensaje;
}

/// Cliente de las operaciones de negocio (pedidos, logística, inventario,
/// retazos y ubicaciones). Lo usan la app de escritorio y la app móvil.
/// Cada servicio hace solo lo suyo; aquí solo se llaman sus APIs.
class Api {
  Api._();

  static const _timeout = Duration(seconds: 20);

  static String nuevoId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    final s = List.generate(16, h).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  static Future<Map<String, String>> _headers() async {
    final token = await ApiService.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<dynamic> _request(String method, String path, {Object? body, Map<String, String>? query}) async {
    final host = await ApiService.getBaseHost();
    final uri = Uri.parse('$host$path').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final headers = await _headers();
    final payload = body == null ? null : jsonEncode(body);
    late http.Response res;
    try {
      res = await switch (method) {
        'GET' => http.get(uri, headers: headers),
        'POST' => http.post(uri, headers: headers, body: payload),
        'PUT' => http.put(uri, headers: headers, body: payload),
        'DELETE' => http.delete(uri, headers: headers),
        _ => throw ArgumentError(method),
      }.timeout(_timeout);
    } catch (e) {
      throw ApiError(0, 'No hay conexión con el servidor. Revisa la red e inténtalo de nuevo.');
    }
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return text.isEmpty ? null : jsonDecode(text);
    }
    var mensaje = switch (res.statusCode) {
      401 => 'Tu sesión venció. Vuelve a iniciar sesión.',
      403 => 'No tienes permisos para esta operación.',
      404 => 'No se encontró el registro solicitado.',
      _ => 'El servidor rechazó la operación (HTTP ${res.statusCode}).',
    };
    try {
      final data = jsonDecode(text);
      if (data is Map && (data['message'] ?? data['error']) != null) {
        mensaje = (data['message'] ?? data['error']).toString();
      }
    } catch (_) {}
    throw ApiError(res.statusCode, mensaje);
  }

  static Future<dynamic> get(String path, [Map<String, String>? query]) => _request('GET', path, query: query);
  static Future<dynamic> post(String path, [Object? body]) => _request('POST', path, body: body ?? const {});
  static Future<dynamic> put(String path, Object body) => _request('PUT', path, body: body);
  static Future<dynamic> delete(String path) => _request('DELETE', path);

  static List<Map<String, dynamic>> _items(dynamic data) {
    final list = data is Map ? (data['items'] as List? ?? const []) : (data as List? ?? const []);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ===================================================================
  // PEDIDOS (pedidos-service): ventas, clientes, preparación y entregas
  // ===================================================================

  static Future<List<Map<String, dynamic>>> pedidos({String estado = '', String q = '', int size = 100}) async =>
      _items(await get('/api/pedidos/orders', {'state': estado, 'q': q, 'size': '$size'}));

  static Future<Map<String, dynamic>> pedido(String id) async =>
      Map<String, dynamic>.from(await get('/api/pedidos/orders/$id') as Map);

  /// Productos con stock disponible (stock - reservado) y formato de piezas.
  static Future<List<Map<String, dynamic>>> productosVenta({String q = ''}) async =>
      _items(await get('/api/pedidos/products', {'q': q, 'size': '100'}));

  static Future<Map<String, dynamic>> disponibilidad(List<Map<String, dynamic>> lineas) async =>
      Map<String, dynamic>.from(await post('/api/pedidos/availability', {'lines': lineas}) as Map);

  static Future<Map<String, dynamic>> crearPedido(Map<String, dynamic> datos) async =>
      Map<String, dynamic>.from(await post('/api/pedidos/orders', {'requestId': nuevoId(), ...datos}) as Map);

  /// confirm, retry, prepare, delay, resume, cancel, deliver, receive-return.
  static Future<dynamic> accionPedido(String id, String accion,
          {required String motivo, List<Map<String, dynamic>>? lineas, String? recibe}) =>
      post('/api/pedidos/orders/$id/$accion', {
        'requestId': nuevoId(),
        'reason': motivo,
        'lines': ?lineas,
        'receiverName': ?recibe,
      });

  static Future<dynamic> recibirDevolucion(String envioId, String motivo) =>
      post('/api/pedidos/shipments/$envioId/receive-return', {'requestId': nuevoId(), 'reason': motivo});

  /// Bandeja de entregas: pedidos a domicilio con material por enviar.
  static Future<List<Map<String, dynamic>>> entregasPendientes() async =>
      _items(await get('/api/pedidos/deliveries/pending'));

  static Future<List<Map<String, dynamic>>> clientes({String q = '', bool inactivos = false}) async =>
      _items(await get('/api/pedidos/clients', {'q': q, 'size': '100', if (inactivos) 'includeInactive': 'true'}));

  static Future<dynamic> guardarCliente(String? id, Map<String, dynamic> datos) =>
      id == null ? post('/api/pedidos/clients', datos) : put('/api/pedidos/clients/$id', datos);

  // ===================================================================
  // LOGÍSTICA (logistica-service): rutas, paradas y choferes
  // ===================================================================

  static Future<List<Map<String, dynamic>>> choferes() async => _items(await get('/api/v1/logistica/choferes'));

  static Future<List<Map<String, dynamic>>> rutas() async => _items(await get('/api/v1/logistica/rutas'));

  static Future<Map<String, dynamic>> ruta(String id) async =>
      Map<String, dynamic>.from(await get('/api/v1/logistica/rutas/$id') as Map);

  static Future<Map<String, dynamic>> crearRuta({
    required String choferId,
    String? codigo,
    String? comentarios,
    List<Map<String, dynamic>> pedidos = const [],
  }) async =>
      Map<String, dynamic>.from(await post('/api/v1/logistica/rutas', {
        'codigoRuta': codigo,
        'choferId': choferId,
        'comentarios': comentarios,
        'pedidos': pedidos,
      }) as Map);

  static Future<dynamic> agregarPedidosRuta(String rutaId, List<Map<String, dynamic>> pedidos) =>
      post('/api/v1/logistica/rutas/$rutaId/pedidos', {'pedidos': pedidos});

  static Future<dynamic> modificarCarga(String rutaId, String paradaId, List<Map<String, dynamic>> lineas) =>
      put('/api/v1/logistica/rutas/$rutaId/destinos/$paradaId/carga', {'lineas': lineas});

  static Future<dynamic> quitarParada(String rutaId, String paradaId) =>
      delete('/api/v1/logistica/rutas/$rutaId/destinos/$paradaId');

  static Future<dynamic> asignarChofer(String rutaId, String choferId) =>
      put('/api/v1/logistica/rutas/$rutaId/chofer', {'choferId': choferId});

  static Future<dynamic> iniciarRuta(String rutaId) => post('/api/v1/logistica/rutas/$rutaId/iniciar');
  static Future<dynamic> cancelarRuta(String rutaId, String motivo) =>
      post('/api/v1/logistica/rutas/$rutaId/cancelar', {'motivo': motivo});
  static Future<dynamic> completarRuta(String rutaId) => post('/api/v1/logistica/rutas/$rutaId/completar');
  static Future<dynamic> eliminarRuta(String rutaId) => delete('/api/v1/logistica/rutas/$rutaId');

  // ===================================================================
  // INVENTARIO (inventario-service): catálogo y movimientos manuales
  // ===================================================================

  /// Recepción de compra (INGRESO) o conteo físico (AJUSTE, solo administración).
  static Future<dynamic> movimientoInventario(String productoId,
          {required String tipo, required num cantidad, required String motivo, String referencia = ''}) =>
      post('/api/products/$productoId/movements', {
        'requestId': nuevoId(),
        'type': tipo,
        'quantity': cantidad,
        'reason': motivo,
        'reference': referencia,
      });

  // ===================================================================
  // RETAZOS (retazos-service): piezas con medida
  // ===================================================================

  static Future<Map<String, dynamic>> resumenPiezas(String productoId) async =>
      Map<String, dynamic>.from(await get('/api/retazos/products/$productoId/summary') as Map);

  static Future<List<Map<String, dynamic>>> piezasDeProducto(String productoId, {String estado = 'DISPONIBLE'}) async =>
      _items(await get('/api/retazos/products/$productoId/pieces', {'state': estado, 'size': '100'}));

  static Future<List<Map<String, dynamic>>> buscarPiezas({
    String q = '',
    String tipo = '',
    String estado = 'DISPONIBLE',
    num? minLargoM,
    num? minAnchoCm,
    num? minAltoCm,
  }) async =>
      _items(await get('/api/retazos/pieces', {
        'q': q,
        'kind': tipo,
        'state': estado,
        'size': '100',
        if (minLargoM != null) 'minLengthM': '$minLargoM',
        if (minAnchoCm != null) 'minWidthCm': '$minAnchoCm',
        if (minAltoCm != null) 'minHeightCm': '$minAltoCm',
      }));

  static Future<Map<String, dynamic>> fichaPieza(String piezaId) async =>
      Map<String, dynamic>.from(await get('/api/retazos/pieces/$piezaId') as Map);

  /// Ingreso de piezas nuevas (compra de perfiles o planchas completas o sobrantes recibidos).
  static Future<dynamic> registrarPiezas(String productoId,
          {required int cantidad, num? largoM, num? anchoCm, num? altoCm, String ubicacion = '', required String motivo}) =>
      post('/api/retazos/products/$productoId/pieces', {
        'requestId': nuevoId(),
        'mode': 'NUEVO',
        'quantity': cantidad,
        'lengthM': largoM,
        'widthCm': anchoCm,
        'heightCm': altoCm,
        'location': ubicacion,
        'reason': motivo,
      });

  static Future<dynamic> descartarPieza(String productoId, String piezaId, String motivo) =>
      post('/api/retazos/products/$productoId/pieces/$piezaId/discard', {'requestId': nuevoId(), 'reason': motivo});

  static Future<List<Map<String, dynamic>>> operacionesPiezas(String productoId) async =>
      _items(await get('/api/retazos/products/$productoId/operations', {'size': '30'}));

  // ===================================================================
  // UBICACIONES (ubicaciones-service): dónde está cada material
  // ===================================================================

  static Future<List<Map<String, dynamic>>> espacios({String q = ''}) async =>
      _items(await get('/api/ubicaciones/spaces', {'q': q, 'size': '100'}));

  static Future<Map<String, dynamic>> contenidoEspacio(String espacioId) async =>
      Map<String, dynamic>.from(await get('/api/ubicaciones/spaces/$espacioId/contents') as Map);

  static Future<dynamic> guardarEspacio(String? id, {required String codigo, String descripcion = '', bool activo = true}) {
    final body = {'code': codigo, 'description': descripcion, 'active': activo};
    return id == null ? post('/api/ubicaciones/spaces', body) : put('/api/ubicaciones/spaces/$id', body);
  }

  /// Materiales que coinciden con la búsqueda (para ubicar).
  static Future<List<Map<String, dynamic>>> materiales({String q = ''}) async =>
      _items(await get('/api/ubicaciones/products', {'q': q, 'size': '50'}));

  /// Dónde está un material: cantidades por espacio y piezas con su ubicación.
  static Future<Map<String, dynamic>> ubicacionesDe(String productoId) async =>
      Map<String, dynamic>.from(await get('/api/ubicaciones/products/$productoId') as Map);

  /// Traslada una cantidad (productos por unidad) o piezas concretas (productos por pieza).
  static Future<dynamic> trasladar({
    required String productoId,
    String? desdeEspacioId,
    required String haciaEspacioId,
    num? cantidad,
    List<String>? piezas,
    required String motivo,
  }) =>
      post('/api/ubicaciones/moves', {
        'requestId': nuevoId(),
        'productId': productoId,
        'fromSpaceId': desdeEspacioId,
        'toSpaceId': haciaEspacioId,
        'quantity': cantidad,
        'pieceIds': piezas,
        'reason': motivo,
      });
}
