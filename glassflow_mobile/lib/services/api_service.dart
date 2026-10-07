import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Deteccion automatica de entorno: Web usa localhost, emulador Android usa 10.0.2.2
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8080/api/v1';
    }
    return 'http://10.0.2.2:8080/api/v1';
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

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final url = Uri.parse('$baseUrl/auth/login');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', data['token']);
      await prefs.setString('driver_id', data['id']);
      await prefs.setString('driver_name', data['nombre']);
      await prefs.setString('driver_email', data['email']);
      return data;
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? err['error'] ?? 'Credenciales invalidas');
    }
  }

  static Future<List<dynamic>> obtenerDespachosHoy(String choferId) async {
    final token = await getToken();
    final url = Uri.parse('$baseUrl/logistica/choferes/$choferId/despachos-hoy');
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

  static Future<Map<String, dynamic>> aceptarEIniciarRuta(String despachoId) async {
    final token = await getToken();
    final url = Uri.parse('$baseUrl/logistica/despachos/$despachoId/aceptar-inicio');
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
      throw Exception('Error al registrar consentimiento de inicio de ruta');
    }
  }

  static Future<Map<String, dynamic>> cancelarRuta(String despachoId, String motivo) async {
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
    final url = Uri.parse('$baseUrl/logistica/despachos/$despachoId/cerrar-entrega');
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
        'comentarios': comentarios ?? 'Entrega registrada desde aplicacion movil',
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Error al cerrar la entrega con prueba e-PoD');
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
