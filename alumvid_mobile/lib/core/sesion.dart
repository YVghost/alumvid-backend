import 'dart:convert';

import 'package:alumvid_admin_desktop/models/user.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

/// Claves con las que el paquete del administrador guarda su sesión.
/// La app móvil las rellena al iniciar sesión para reutilizar su API.
const _kAdminToken = 'admin_auth_token';
const _kAdminUser = 'admin_user_data';

/// Módulos de la app. Los roles permitidos replican las reglas del backend
/// (PedidosSecurity, InventorySecurity, RetazosSecurity, UbicacionesSecurity)
/// y las del administrador de escritorio (logística y usuarios: solo ADMINISTRADOR).
enum Modulo {
  inicio('Inicio', Icons.space_dashboard_outlined, Icons.space_dashboard, {
    'ADMINISTRADOR',
    'VENDEDOR',
    'BODEGUERO',
    'CHOFER',
  }),
  misRutas('Mis rutas', Icons.local_shipping_outlined, Icons.local_shipping, {
    'CHOFER',
  }),
  monitoreo('Monitoreo', Icons.radar_outlined, Icons.radar, {'ADMINISTRADOR'}),
  rutas('Rutas', Icons.alt_route_outlined, Icons.alt_route, {'ADMINISTRADOR'}),
  pedidos('Pedidos', Icons.receipt_long_outlined, Icons.receipt_long, {
    'ADMINISTRADOR',
    'VENDEDOR',
    'BODEGUERO',
  }),
  inventario('Inventario', Icons.inventory_2_outlined, Icons.inventory_2, {
    'ADMINISTRADOR',
    'VENDEDOR',
    'BODEGUERO',
  }),
  retazos('Retazos', Icons.content_cut_outlined, Icons.content_cut, {
    'ADMINISTRADOR',
    'VENDEDOR',
    'BODEGUERO',
  }),
  bodega('Bodega', Icons.grid_view_outlined, Icons.grid_view_rounded, {
    'ADMINISTRADOR',
    'VENDEDOR',
    'BODEGUERO',
  }),
  usuarios('Usuarios', Icons.people_alt_outlined, Icons.people_alt, {
    'ADMINISTRADOR',
  });

  const Modulo(this.etiqueta, this.icono, this.iconoActivo, this.roles);
  final String etiqueta;
  final IconData icono;
  final IconData iconoActivo;
  final Set<String> roles;
}

class Sesion {
  Sesion._(this.usuario, this.datos);

  final AppUser usuario;

  /// Respuesta cruda del login (la usa el flujo del chofer).
  final Map<String, dynamic> datos;

  static Sesion? actual;

  @visibleForTesting
  factory Sesion.paraPruebas(AppUser usuario, [Map<String, dynamic>? datos]) =>
      Sesion._(usuario, datos ?? {'id': usuario.id, 'nombre': usuario.fullName});

  List<String> get roles => usuario.roles;
  bool tiene(String rol) => roles.contains(rol);
  bool get esAdmin => tiene('ADMINISTRADOR');

  /// Movimientos de stock, cortes y traslados: ADMINISTRADOR o BODEGUERO.
  bool get puedeMoverStock => esAdmin || tiene('BODEGUERO');

  /// Alta y edición del catálogo: solo ADMINISTRADOR.
  bool get puedeEditarCatalogo => esAdmin;

  bool puede(Modulo m) => m.roles.any(roles.contains);

  List<Modulo> get modulos => Modulo.values.where(puede).toList();

  /// Un chofer sin otros roles ve directamente su lista de rutas.
  bool get soloChofer => modulos.every(
    (m) => m == Modulo.inicio || m == Modulo.misRutas,
  );

  String get rolPrincipal {
    for (final r in const ['ADMINISTRADOR', 'BODEGUERO', 'VENDEDOR', 'CHOFER']) {
      if (tiene(r)) return r;
    }
    return roles.isEmpty ? 'SIN ROL' : roles.first;
  }

  static String _hostDesdeBaseUrl() =>
      ApiService.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');

  /// Registra la sesión a partir de la respuesta del login.
  static Future<Sesion> establecer(Map<String, dynamic> datos) async {
    final token = (datos['token'] ?? datos['accessToken'] ?? '').toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAdminToken, token);
    await prefs.setString(_kAdminUser, jsonEncode(datos));
    await adm.ApiService.setBaseHost(_hostDesdeBaseUrl());
    final user = AppUser.fromJson(
      datos['roles'] == null && datos['user'] is Map
          ? Map<String, dynamic>.from(datos['user'] as Map)
          : datos,
    );
    return actual = Sesion._(user, datos);
  }

  /// Recupera una sesión guardada si el token sigue siendo válido.
  static Future<Sesion?> restaurar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAdminUser);
    if (raw == null || prefs.getString('auth_token') == null) return null;
    await adm.ApiService.setBaseHost(_hostDesdeBaseUrl());
    final user = await adm.ApiService.getCurrentUser();
    if (user == null || user.mustChangePassword || !user.active) return null;
    final datos = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return actual = Sesion._(user, datos);
  }

  /// ApiService.logout también borra las claves compartidas con el admin.
  static Future<void> cerrar() async {
    actual = null;
    await ApiService.logout();
  }
}
