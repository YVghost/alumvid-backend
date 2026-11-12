import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static String? _serverOverride;
  static String normalizeServer(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/', '/api/v1', '/api/v1/'].contains(uri.path)) {
      throw const FormatException(
        'Usa una dirección como http://192.168.1.10:8080',
      );
    }
    return uri.replace(path: '/api/v1').toString();
  }

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('api_base_url');
    _serverOverride = null;
    if (saved != null) {
      try {
        _serverOverride = normalizeServer(saved);
      } on FormatException {
        /* Usar configuración inicial. */
      }
    }
  }

  static Future<void> setServer(String input) async {
    final next = normalizeServer(input);
    await logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', next);
    _serverOverride = next;
  }

  /// Puerto del API Gateway de AlumVid (compose.yaml: GATEWAY_PORT=8080).
  static const int gatewayPort = 8080;

  /// Comprueba si [host] responde como el API Gateway de AlumVid.
  static Future<bool> _esGatewayAlumVid(
    String host, {
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('http://$host:$gatewayPort/platform-info'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return false;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return body.contains('AlumVid API Gateway');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Busca el backend en la red local del teléfono (misma Wi-Fi que la PC).
  /// Devuelve la URL encontrada (ya guardada como servidor) o null.
  static Future<String?> descubrirServidor() async {
    // 1) El servidor actual sigue funcionando: no hace falta buscar.
    final actual = Uri.tryParse(baseUrl);
    if (actual != null &&
        actual.host.isNotEmpty &&
        await _esGatewayAlumVid(actual.host)) {
      return baseUrl;
    }

    // 2) Recorrer las subredes /24 privadas de las interfaces del teléfono.
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final propias = <String>{};
    final prefijos = <String>{};
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final p = addr.address.split('.');
        if (p.length != 4) continue;
        final a = int.tryParse(p[0]) ?? 0, b = int.tryParse(p[1]) ?? 0;
        final privada =
            a == 10 ||
            (a == 172 && b >= 16 && b <= 31) ||
            (a == 192 && b == 168);
        if (!privada) continue;
        propias.add(addr.address);
        prefijos.add('${p[0]}.${p[1]}.${p[2]}');
      }
    }

    for (final prefijo in prefijos) {
      final candidatos = [
        for (var i = 1; i < 255; i++) '$prefijo.$i',
      ].where((h) => !propias.contains(h)).toList();
      const lote = 48;
      for (var i = 0; i < candidatos.length; i += lote) {
        final grupo = candidatos.skip(i).take(lote).toList();
        final resultados = await Future.wait(grupo.map(_esGatewayAlumVid));
        final idx = resultados.indexOf(true);
        if (idx >= 0) {
          await setServer('http://${grupo[idx]}:$gatewayPort');
          return baseUrl;
        }
      }
    }
    return null;
  }

  static bool esErrorDeConexion(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException;

  // --dart-define=API_BASE_URL=http://IP-del-servidor:8080/api/v1
  static String get baseUrl {
    if (_serverOverride != null) return _serverOverride!;
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) {
      return configured.replaceFirst(RegExp(r'/+$'), '');
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api/v1';
    }
    return 'http://localhost:8080/api/v1';
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<String?> getDriverId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('driver_id');
  }

  static Future<String?> getDriverName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('driver_name');
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final url = Uri.parse('$baseUrl/auth/login');
    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'identification': email,
            'email': email,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final prefs = await SharedPreferences.getInstance();
      final token = data['token'] ?? data['accessToken'] ?? '';
      final driverId =
          data['id'] ?? (data['user'] != null ? data['user']['id'] : '');
      final driverName =
          data['nombre'] ??
          data['fullName'] ??
          (data['user'] != null ? data['user']['fullName'] : '');
      final driverEmail =
          data['email'] ??
          (data['user'] != null ? data['user']['email'] : email);

      await prefs.setString('auth_token', token.toString());
      await prefs.setString('driver_id', driverId.toString());
      await prefs.setString('driver_name', driverName.toString());
      await prefs.setString('driver_email', driverEmail.toString());
      return data;
    } else {
      try {
        if (response.body.trim().isNotEmpty) {
          final err = jsonDecode(response.body);
          if (err is Map<String, dynamic>) {
            final msg = err['message'] ?? err['error'];
            if (msg != null && msg.toString().trim().isNotEmpty) {
              throw Exception(msg.toString());
            }
          }
        }
      } catch (e) {
        if (e is Exception &&
            !e.toString().contains('FormatException') &&
            !e.toString().contains('FormatSyntaxError')) {
          rethrow;
        }
      }
      throw Exception(
        'Credenciales invalidas o cuenta no registrada en el sistema.',
      );
    }
  }

  static Future<List<dynamic>> obtenerDespachosHoy(String choferId) async {
    final token = await getToken();
    final url = Uri.parse(
      '$baseUrl/logistica/choferes/$choferId/despachos-hoy',
    );
    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Error al consultar rutas asignadas');
    }
  }

  static Future<List<dynamic>> obtenerRutasChofer(String choferId) async {
    final token = await getToken();
    final url = Uri.parse('$baseUrl/logistica/choferes/$choferId/rutas');
    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Error al consultar hojas de ruta del chofer');
    }
  }

  static Future<Map<String, dynamic>> obtenerRutaPorId(String rutaId) async {
    final token = await getToken();
    final url = Uri.parse('$baseUrl/logistica/rutas/$rutaId');
    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Error al consultar detalle de la ruta');
    }
  }

  static Future<Map<String, dynamic>> optimizarRutaChofer(
    String rutaId, {
    required double latitud,
    required double longitud,
  }) async {
    final token = await getToken();
    final url = Uri.parse(
      '$baseUrl/logistica/rutas/$rutaId/optimizar-chofer?latitud=$latitud&longitud=$longitud',
    );
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Error al optimizar paradas desde GPS');
    }
  }

  static Future<void> enviarTelemetriaHttp({
    required String choferId,
    required String despachoId,
    required double lat,
    required double lon,
    required double velocidad,
    required double rumbo,
    required String choferNombre,
  }) async {
    try {
      final token = await getToken();
      final url = Uri.parse('$baseUrl/logistica/telemetria');
      await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'choferId': choferId,
              'despachoId': despachoId,
              'latitud': lat,
              'longitud': lon,
              'velocidadKmh': velocidad,
              'rumbo': rumbo,
              'choferNombre': choferNombre,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
          )
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('Error enviando telemetria GPS: $e');
    }
  }

  static Future<Map<String, dynamic>> obtenerRutaVialOsrm(
    double origenLat,
    double origenLon,
    double destLat,
    double destLon,
  ) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$origenLon,$origenLat;$destLon,$destLat?overview=full&geometries=geojson',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final coords = route['geometry']['coordinates'] as List<dynamic>;
          final distM = (route['distance'] as num?)?.toDouble() ?? 0.0;
          final durS = (route['duration'] as num?)?.toDouble() ?? 0.0;

          return {
            'coordinates': coords,
            'distanciaKm': distM / 1000.0,
            'duracionMin': (durS / 60.0).round(),
          };
        }
      }
    } catch (e) {
      debugPrint('Fallo al consultar OSRM vial: $e');
    }
    // Respaldo de contingencia vial por las calles reales de Quito
    // para garantizar que nunca se dibuje una línea recta aérea sobre edificaciones
    const List<List<double>> respaldoVialQuito = [
      [-78.439604, -0.089274],
      [-78.440026, -0.089204],
      [-78.440355, -0.089664],
      [-78.440556, -0.089954],
      [-78.440785, -0.090286],
      [-78.441337, -0.091082],
      [-78.441781, -0.091714],
      [-78.441946, -0.091962],
      [-78.442490, -0.092769],
      [-78.442933, -0.093376],
      [-78.443378, -0.094377],
      [-78.443623, -0.094979],
      [-78.444009, -0.095912],
      [-78.444342, -0.096767],
      [-78.444632, -0.097454],
      [-78.444976, -0.098267],
      [-78.445209, -0.098915],
      [-78.445229, -0.099215],
      [-78.445374, -0.099460],
      [-78.445772, -0.099723],
      [-78.446200, -0.099996],
      [-78.446827, -0.100391],
      [-78.447318, -0.100717],
      [-78.447933, -0.101132],
      [-78.448738, -0.101554],
      [-78.449215, -0.101817],
      [-78.450184, -0.102385],
      [-78.451414, -0.103122],
      [-78.451496, -0.103170],
      [-78.451479, -0.102235],
    ];

    return {
      'coordinates': respaldoVialQuito,
      'distanciaKm': 2.2,
      'duracionMin': 4,
    };
  }

  static Future<Map<String, dynamic>> aceptarEIniciarRuta(
    String despachoId,
  ) async {
    final token = await getToken();
    final url = Uri.parse(
      '$baseUrl/logistica/despachos/$despachoId/aceptar-inicio',
    );
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      try {
        final err = jsonDecode(response.body);
        if (err is Map && err.containsKey('message')) {
          throw Exception(err['message']);
        }
      } catch (e) {
        if (e is! FormatException && !e.toString().contains('FormatException')) rethrow;
      }
      throw Exception('Error al registrar consentimiento de inicio de ruta');
    }
  }

  static Future<Map<String, dynamic>> reintentarParada(String despachoId) async {
    final token = await getToken();
    final url = Uri.parse('$baseUrl/logistica/despachos/$despachoId/reintentar');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      try {
        final err = jsonDecode(response.body);
        if (err is Map && err.containsKey('message')) {
          throw Exception(err['message']);
        }
      } catch (e) {
        if (e is! FormatException && !e.toString().contains('FormatException')) rethrow;
      }
      throw Exception('Error al reintentar la entrega');
    }
  }

  static Future<Map<String, dynamic>> cancelarRuta(
    String despachoId,
    String motivo,
  ) async {
    final token = await getToken();
    final url = Uri.parse('$baseUrl/logistica/despachos/$despachoId/cancelar');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'motivo': motivo}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Error al cancelar la ruta');
    }
  }

  static Future<Map<String, dynamic>> cerrarEntrega({
    required String despachoId,
    required String fotoPodUrl,
    required String firmaUrl,
    required double latitud,
    required double longitud,
    String? comentarios,
  }) async {
    final token = await getToken();
    final url = Uri.parse(
      '$baseUrl/logistica/despachos/$despachoId/cerrar-entrega',
    );
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'fotoPodUrl': fotoPodUrl,
        'firmaUrl': firmaUrl,
        'latitud': latitud,
        'longitud': longitud,
        'comentarios':
            comentarios ?? 'Entrega registrada desde aplicacion movil',
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final err = jsonDecode(response.body);
      throw Exception(
        err['message'] ?? 'Error al cerrar la entrega con prueba e-PoD',
      );
    }
  }

  static Future<void> cambiarPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = await getToken();
    final url = Uri.parse('$baseUrl/auth/password');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      try {
        final err = jsonDecode(response.body);
        throw Exception(err['message'] ?? 'Error al actualizar contraseña');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Error al actualizar contraseña');
      }
    }
  }

  static Future<bool> verificarSesionActiva() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;

    try {
      final url = Uri.parse('$baseUrl/auth/me');
      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 4));

      return response.statusCode == 200;
    } catch (_) {
      // Si hay error de red temporal, no expulsamos
      return true;
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    try {
      if (token != null && token.isNotEmpty) {
        await http
            .post(
              Uri.parse('$baseUrl/auth/logout'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 4));
      }
    } catch (_) {
      // Sin red se cierra la sesion local; el servidor conserva su vencimiento.
      debugPrint(
        'No se pudo revocar la sesion remota; se borro la sesion local.',
      );
    } finally {
      for (final key in [
        'auth_token',
        'driver_id',
        'driver_name',
        'driver_email',
        // Sesión compartida con los módulos administrativos (ver core/sesion.dart).
        'admin_auth_token',
        'admin_user_data',
      ]) {
        await prefs.remove(key);
      }
    }
  }
}
