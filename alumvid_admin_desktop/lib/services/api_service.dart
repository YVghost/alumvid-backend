import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audit_event.dart';
import '../models/chofer.dart';
import '../models/despacho.dart';
import '../models/movimiento.dart';
import '../models/pedido.dart';
import '../models/producto.dart';
import '../models/ruta.dart';
import '../models/user.dart';

class ApiService {
  static const String _prefHostKey = 'server_host_custom';
  static const String _prefTokenKey = 'admin_auth_token';
  static const String _prefUserKey = 'admin_user_data';

  // Obtiene el host base (configurable en settings o automatico)
  static Future<String> getBaseHost() async {
    final prefs = await SharedPreferences.getInstance();
    final customHost = prefs.getString(_prefHostKey);
    if (customHost != null && customHost.trim().isNotEmpty) {
      if (customHost.contains(':8080')) {
        final migrado = customHost.replaceAll(':8080', ':8085').trim();
        await prefs.setString(_prefHostKey, migrado);
        return migrado;
      }
      return customHost.trim();
    }

    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return 'http://localhost:8085';
    }
    // Para emulador Android
    return 'http://10.0.2.2:8085';
  }

  static Future<void> setBaseHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefHostKey, host.trim());
  }

  static Future<String> getApiBase() async {
    final host = await getBaseHost();
    return '$host/api/v1';
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefTokenKey);
  }

  static Future<AppUser?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefUserKey);
    final token = prefs.getString(_prefTokenKey);
    if (raw != null && token != null && token.isNotEmpty) {
      try {
        final host = await getBaseHost();
        final url = Uri.parse('$host/api/auth/me');
        final res = await http.get(url, headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          return AppUser.fromJson(data);
        } else {
          // Token expirado o revocado en el backend: limpiar sesión automáticamente
          await logout();
          return null;
        }
      } catch (_) {
        // En caso de fallo o timeout de red con token dudoso
        return null;
      }
    }
    return null;
  }

  static Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // =========================================================================
  // 1. AUTENTICACION
  // =========================================================================

  static Future<AppUser> login(String identificationOrEmail, String password) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/auth/login');

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'identification': identificationOrEmail,
            'email': identificationOrEmail,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['token'] ?? data['accessToken'] ?? '';
      final user = AppUser.fromJson(data);

      if (!user.isAdmin) {
        throw Exception('Acceso restringido: Esta aplicación es exclusiva para usuarios con rol ADMINISTRADOR.');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefTokenKey, token.toString());
      await prefs.setString(_prefUserKey, jsonEncode(data));

      return user;
    } else {
      String mensaje = 'Credenciales inválidas.';
      try {
        final err = jsonDecode(response.body);
        mensaje = err['message'] ?? err['error'] ?? mensaje;
      } catch (_) {}
      throw Exception(mensaje);
    }
  }

  static Future<void> logout() async {
    try {
      final apiBase = await getApiBase();
      final url = Uri.parse('$apiBase/auth/logout');
      final headers = await _headers();
      await http.post(url, headers: headers).timeout(const Duration(seconds: 4));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefTokenKey);
    await prefs.remove(_prefUserKey);
  }

  // =========================================================================
  // 2. LOGISTICA: RUTAS, PEDIDOS Y CHOFERES
  // =========================================================================

  static Future<List<Ruta>> obtenerRutas() async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas');
    final headers = await _headers();

    final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.map((r) => Ruta.fromJson(r)).toList();
    }
    throw Exception('Error al obtener rutas: ${response.statusCode}');
  }

  static Future<Ruta> obtenerRutaPorId(String id) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/$id');
    final headers = await _headers();

    final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      return Ruta.fromJson(jsonDecode(response.body));
    }
    throw Exception('Error al obtener detalle de ruta: ${response.statusCode}');
  }

  static Future<List<Chofer>> obtenerChoferes() async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/choferes');
    final headers = await _headers();

    final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.map((c) => Chofer.fromJson(c)).toList();
    }
    throw Exception('Error al listar choferes');
  }

  static Future<List<Pedido>> obtenerPedidosPendientes() async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/pedidos/pendientes');
    final headers = await _headers();

    final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.map((p) => Pedido.fromJson(p)).toList();
    }
    throw Exception('Error al listar pedidos pendientes');
  }

  static Future<List<Pedido>> obtenerTodosLosPedidos() async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/pedidos');
    final headers = await _headers();

    final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.map((p) => Pedido.fromJson(p)).toList();
    }
    throw Exception('Error al listar todos los pedidos');
  }

  static Future<Ruta> crearRutaMultiDestino({
    required String codigoRuta,
    required String choferId,
    String? comentarios,
    required List<Map<String, dynamic>> destinos,
  }) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/multi-destino');
    final headers = await _headers();

    final response = await http
        .post(
          url,
          headers: headers,
          body: jsonEncode({
            'codigoRuta': codigoRuta,
            'choferId': choferId,
            'comentarios': comentarios ?? '',
            'destinos': destinos,
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Ruta.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Error al crear la ruta multi-destino');
  }

  static Future<Ruta> agregarDestinoRuta({
    required String rutaId,
    required String cliente,
    required String direccionTexto,
    required double latitud,
    required double longitud,
    String? comentarios,
  }) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/$rutaId/destinos');
    final headers = await _headers();

    final response = await http
        .post(
          url,
          headers: headers,
          body: jsonEncode({
            'cliente': cliente,
            'direccionTexto': direccionTexto,
            'latitudDestino': latitud,
            'longitudDestino': longitud,
            'comentarios': comentarios,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Ruta.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Error al agregar destino a la ruta');
  }

  static Future<Ruta> eliminarDestinoRuta(String rutaId, String despachoId) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/$rutaId/destinos/$despachoId');
    final headers = await _headers();

    final response = await http.delete(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      return Ruta.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Error al eliminar destino');
  }

  static Future<Ruta> optimizarRutaChofer(String rutaId, {required double latitud, required double longitud}) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/$rutaId/optimizar-chofer?latitud=$latitud&longitud=$longitud');
    final headers = await _headers();

    final response = await http.post(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      return Ruta.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Error al optimizar ruta del chofer');
  }

  static Future<Ruta> asignarChoferRuta(String rutaId, String? choferId) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/$rutaId/chofer');
    final headers = await _headers();

    final response = await http
        .put(
          url,
          headers: headers,
          body: jsonEncode({'choferId': choferId}),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      return Ruta.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Error al reasignar chofer');
  }

  static Future<Ruta> iniciarRuta(String rutaId) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/$rutaId/iniciar');
    final headers = await _headers();

    final response = await http.post(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      return Ruta.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Error al iniciar ruta');
  }

  static Future<Ruta> completarRuta(String rutaId) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/$rutaId/completar');
    final headers = await _headers();

    final response = await http.post(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      return Ruta.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? err['error'] ?? 'Error al completar ruta');
  }

  static Future<Ruta> cancelarRuta(String rutaId, String motivo) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/$rutaId/cancelar');
    final headers = await _headers();

    final response = await http
        .post(
          url,
          headers: headers,
          body: jsonEncode({'motivo': motivo}),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      return Ruta.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Error al cancelar ruta');
  }

  static Future<Ruta> crearRutaSimple({
    required String codigoRuta,
    String? choferId,
    String? comentarios,
  }) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/simple');
    final headers = await _headers();

    final response = await http
        .post(
          url,
          headers: headers,
          body: jsonEncode({
            'codigoRuta': codigoRuta,
            'choferId': choferId,
            'comentarios': comentarios,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Ruta.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Error al crear hoja de ruta simple');
  }

  static Future<void> eliminarRuta(String rutaId) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/rutas/$rutaId');
    final headers = await _headers();

    final response = await http.delete(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 && response.statusCode != 204) {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Error al eliminar la hoja de ruta');
    }
  }

  static Future<void> aceptarInicioRuta(String despachoId) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/despachos/$despachoId/aceptar-inicio');
    final headers = await _headers();

    final response = await http.post(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Error al aceptar e iniciar ruta');
    }
  }

  static Future<void> cancelarDespacho(String despachoId, String motivo) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/despachos/$despachoId/cancelar');
    final headers = await _headers();

    final response = await http
        .post(
          url,
          headers: headers,
          body: jsonEncode({'motivo': motivo}),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Error al cancelar despacho');
    }
  }


  static Future<Despacho> cerrarEntrega({
    required String despachoId,
    required String fotoPodUrl,
    required String firmaUrl,
    required double latitud,
    required double longitud,
    String? comentarios,
  }) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/despachos/$despachoId/cerrar-entrega');
    final headers = await _headers();

    final response = await http
        .post(
          url,
          headers: headers,
          body: jsonEncode({
            'fotoPodUrl': fotoPodUrl,
            'firmaUrl': firmaUrl,
            'latitud': latitud,
            'longitud': longitud,
            'comentarios': comentarios,
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      return Despacho.fromJson(jsonDecode(response.body));
    }
    final err = jsonDecode(response.body);
    throw Exception(err['message'] ?? 'Error al cerrar entrega e-PoD');
  }

  static Future<Map<String, dynamic>> obtenerEvidenciaPod(String despachoId) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/despachos/$despachoId/evidencia');
    final headers = await _headers();

    final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Error al consultar evidencia e-PoD');
  }

  // Telemetria GPS simulada o manual
  static Future<void> enviarTelemetria({
    required String? choferId,
    required String? despachoId,
    required double latitud,
    required double longitud,
    required double velocidadKmh,
    required double rumbo,
    required String? choferNombre,
  }) async {
    final apiBase = await getApiBase();
    final url = Uri.parse('$apiBase/logistica/telemetria');
    final headers = await _headers();

    await http
        .post(
          url,
          headers: headers,
          body: jsonEncode({
            'choferId': choferId,
            'despachoId': despachoId,
            'latitud': latitud,
            'longitud': longitud,
            'velocidadKmh': velocidadKmh,
            'rumbo': rumbo,
            'choferNombre': choferNombre,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }),
        )
        .timeout(const Duration(seconds: 4));
  }

  // Trazar ruta real con OSRM
  static Future<List<List<double>>> trazarRutaVial(
      double origLat, double origLon, double destLat, double destLon) async {
    try {
      final url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/$origLon,$origLat;$destLon,$destLat?overview=full&geometries=geojson');
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final coords = routes[0]['geometry']['coordinates'] as List<dynamic>;
          return coords.map((c) => [(c[1] as num).toDouble(), (c[0] as num).toDouble()]).toList();
        }
      }
    } catch (_) {}
    return [
      [origLat, origLon],
      [destLat, destLon]
    ];
  }

  // =========================================================================
  // 3. INVENTARIO & BODEGA (/api/products)
  // =========================================================================

  static Future<Map<String, dynamic>> obtenerProductos({
    String q = '',
    String category = '',
    bool lowStock = false,
    bool includeInactive = false,
    int page = 0,
    int size = 20,
  }) async {
    final host = await getBaseHost();
    final params = URLSearchParams({
      'q': q,
      'category': category,
      'lowStock': lowStock.toString(),
      'includeInactive': includeInactive.toString(),
      'page': page.toString(),
      'size': size.toString(),
    });

    final url = Uri.parse('$host/api/products?$params');
    final headers = await _headers();

    final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final List<dynamic> itemsRaw = data['items'] ?? [];
      final productos = itemsRaw.map((p) => Producto.fromJson(p)).toList();
      return {
        'items': productos,
        'total': int.tryParse(data['total']?.toString() ?? '') ?? productos.length,
      };
    }
    throw Exception('Error al consultar inventario');
  }

  static Future<Producto> crearProducto(Map<String, dynamic> datos) async {
    final host = await getBaseHost();
    final url = Uri.parse('$host/api/products');
    final headers = await _headers();

    final res = await http
        .post(url, headers: headers, body: jsonEncode(datos))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 200 || res.statusCode == 201) {
      return Producto.fromJson(jsonDecode(res.body));
    }
    final err = jsonDecode(res.body);
    throw Exception(err['message'] ?? 'Error al crear producto');
  }

  static Future<Producto> actualizarProducto(String id, Map<String, dynamic> datos) async {
    final host = await getBaseHost();
    final url = Uri.parse('$host/api/products/$id');
    final headers = await _headers();

    final res = await http
        .put(url, headers: headers, body: jsonEncode(datos))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      return Producto.fromJson(jsonDecode(res.body));
    }
    final err = jsonDecode(res.body);
    throw Exception(err['message'] ?? 'Error al actualizar producto');
  }

  static Future<MovimientoInventario> registrarMovimiento(
    String productoId, {
    required String type,
    required double quantity,
    required String reason,
    String reference = '',
  }) async {
    final host = await getBaseHost();
    final url = Uri.parse('$host/api/products/$productoId/movements');
    final headers = await _headers();

    final body = {
      'requestId': 'req-${DateTime.now().microsecondsSinceEpoch}',
      'type': type,
      'quantity': quantity,
      'reason': reason,
      'reference': reference,
    };

    final res = await http
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode == 200 || res.statusCode == 201) {
      return MovimientoInventario.fromJson(jsonDecode(res.body));
    }
    final err = jsonDecode(res.body);
    throw Exception(err['message'] ?? 'Error al registrar movimiento');
  }

  static Future<List<MovimientoInventario>> obtenerMovimientos(
    String productoId, {
    int page = 0,
    int size = 20,
  }) async {
    final host = await getBaseHost();
    final url = Uri.parse('$host/api/products/$productoId/movements?page=$page&size=$size');
    final headers = await _headers();

    final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final List<dynamic> items = data['items'] ?? [];
      return items.map((m) => MovimientoInventario.fromJson(m)).toList();
    }
    throw Exception('Error al obtener movimientos del producto');
  }

  static Future<List<MovimientoInventario>> obtenerMovimientosInventarioGlobal({
    DateTime? from,
    DateTime? to,
    String type = '',
    String q = '',
    int page = 0,
    int size = 150,
  }) async {
    final host = await getBaseHost();
    final queryParams = <String, String>{
      'page': page.toString(),
      'size': size.toString(),
    };
    if (from != null) queryParams['from'] = from.toIso8601String();
    if (to != null) queryParams['to'] = to.toIso8601String();
    if (type.isNotEmpty && type != 'TODOS') queryParams['type'] = type;
    if (q.isNotEmpty) queryParams['q'] = q;

    final uri = Uri.parse('$host/api/products/movements').replace(queryParameters: queryParams);
    final headers = await _headers();

    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final List<dynamic> items = data['items'] ?? [];
      return items.map((m) => MovimientoInventario.fromJson(m)).toList();
    }
    throw Exception('Error al obtener auditoría de movimientos de inventario');
  }

  // =========================================================================
  // 4. USUARIOS & CÉDULAS RBAC (/api/admin/users y /api/admin/audit)
  // =========================================================================

  static Future<List<AppUser>> obtenerUsuariosAdmin() async {
    final host = await getBaseHost();
    final url = Uri.parse('$host/api/admin/users');
    final headers = await _headers();

    final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final List<dynamic> list = jsonDecode(res.body);
      return list.map((u) => AppUser.fromJson(u)).toList();
    }
    throw Exception('Error al obtener lista de usuarios');
  }

  static Future<AppUser> crearUsuario({
    required String identification,
    required String fullName,
    required String email,
    String? telefono,
    required List<String> roles,
    required String temporaryPassword,
  }) async {
    final host = await getBaseHost();
    final url = Uri.parse('$host/api/admin/users');
    final headers = await _headers();

    final body = {
      'identification': identification,
      'fullName': fullName,
      'email': email,
      'telefono': telefono ?? '',
      'roles': roles,
      'temporaryPassword': temporaryPassword,
    };

    final res = await http.post(url, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200 || res.statusCode == 201) {
      return AppUser.fromJson(jsonDecode(res.body));
    }
    final err = jsonDecode(res.body);
    throw Exception(err['message'] ?? 'Error al crear usuario');
  }

  static Future<AppUser> actualizarUsuario(
    String id, {
    required String fullName,
    String? telefono,
    required List<String> roles,
    required bool active,
  }) async {
    final host = await getBaseHost();
    final url = Uri.parse('$host/api/admin/users/$id');
    final headers = await _headers();

    final body = {
      'fullName': fullName,
      'telefono': telefono ?? '',
      'roles': roles,
      'active': active,
    };

    final res = await http.put(url, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      return AppUser.fromJson(jsonDecode(res.body));
    }
    final err = jsonDecode(res.body);
    throw Exception(err['message'] ?? 'Error al actualizar usuario');
  }

  static Future<void> restablecerContrasenaUsuario(String id, String temporaryPassword) async {
    final host = await getBaseHost();
    final url = Uri.parse('$host/api/admin/users/$id/password');
    final headers = await _headers();

    final res = await http
        .post(url, headers: headers, body: jsonEncode({'temporaryPassword': temporaryPassword}))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 204) {
      final err = jsonDecode(res.body);
      throw Exception(err['message'] ?? 'Error al restablecer contraseña');
    }
  }

  static Future<void> notificarSesionRevocada(String userId) async {
    try {
      final apiBase = await getApiBase();
      final url = Uri.parse('$apiBase/logistica/notificaciones/sesion-revocada');
      final headers = await _headers();
      await http.post(url, headers: headers, body: jsonEncode({'userId': userId})).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<void> eliminarUsuario(String id, {bool esChofer = false}) async {
    final host = await getBaseHost();
    final headers = await _headers();

    if (esChofer) {
      try {
        final logHost = await getApiBase();
        await http.delete(Uri.parse('$logHost/logistica/choferes/$id'), headers: headers).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    final url = Uri.parse('$host/api/admin/users/$id');
    final res = await http.delete(url, headers: headers).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 204) {
      try {
        final err = jsonDecode(res.body);
        throw Exception(err['message'] ?? 'Error al eliminar usuario');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Error al eliminar usuario');
      }
    }
  }

  static Future<List<EventoAuditoria>> obtenerAuditoriaSeguridad() async {
    final host = await getBaseHost();
    final url = Uri.parse('$host/api/admin/audit');
    final headers = await _headers();

    final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final List<dynamic> list = jsonDecode(res.body);
      return list.map((a) => EventoAuditoria.fromJson(a)).toList();
    }
    throw Exception('Error al obtener bitácora de auditoría');
  }
}

// Helper para armar query params
class URLSearchParams {
  final Map<String, String> _params;
  URLSearchParams(this._params);

  @override
  String toString() {
    return _params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
  }
}
