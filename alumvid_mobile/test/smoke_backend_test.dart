// Prueba de humo contra un backend real (no corre por defecto).
//
//   $env:ALUMVID_SMOKE_STATE = "..\entrega-pruebas\estado.local.json"
//   $env:ALUMVID_SMOKE_SERVER = "http://localhost:8080"
//   flutter test test/smoke_backend_test.dart
//
// Inicia sesión con cada usuario DEMO y consulta todos los módulos que su rol
// puede ver en la app, igual que lo harían las pantallas.
import 'dart:convert';
import 'dart:io';

import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:alumvid_mobile/core/sesion.dart';
import 'package:alumvid_mobile/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final statePath = Platform.environment['ALUMVID_SMOKE_STATE'];
  final server = Platform.environment['ALUMVID_SMOKE_SERVER'] ?? 'http://localhost:8080';
  if (statePath == null) {
    test('smoke backend (omitida: define ALUMVID_SMOKE_STATE)', () {}, skip: true);
    return;
  }
  final cuentas = Map<String, dynamic>.from(
    jsonDecode(File(statePath).readAsStringSync())['accounts'] as Map,
  );

  Future<Sesion> entrar(String clave) async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.initialize();
    await ApiService.setServer(server);
    final a = cuentas[clave] as Map<String, dynamic>;
    final res = await ApiService.login(a['identification'] as String, a['password'] as String);
    return Sesion.establecer(res);
  }

  Future<void> modulos(Sesion s) async {
    if (s.puede(Modulo.pedidos)) {
      expect(await adm.ApiService.obtenerPedidosComerciales(size: 100), isNotEmpty);
    }
    if (s.puede(Modulo.inventario)) {
      final r = await adm.ApiService.obtenerProductos(size: 100);
      expect(r['items'], isNotEmpty);
      final bajo = await adm.ApiService.obtenerProductos(lowStock: true);
      expect(bajo['items'], isA<List>());
      final p = (r['items'] as List).first;
      await adm.ApiService.obtenerMovimientos(p.id as String);
    }
    if (s.puede(Modulo.retazos)) {
      final r = (await adm.ApiService.obtenerProductosRetazos(size: 100))
          .where((p) => p.piecesManaged)
          .toList();
      expect(r, isNotEmpty);
      for (final p in r) {
        await adm.ApiService.obtenerPiezasRetazo(p.id);
      }
    }
    if (s.puede(Modulo.bodega)) {
      final e = await adm.ApiService.obtenerEspaciosUbicacion(size: 100);
      expect(e, isNotEmpty);
      final c = await adm.ApiService.obtenerContenidoEspacio(e.first.id);
      expect(c, contains('space'));
    }
    if (s.puede(Modulo.rutas)) {
      final r = await adm.ApiService.obtenerRutas();
      expect(r, isNotEmpty);
      await adm.ApiService.obtenerRutaPorId(r.first.id);
      await adm.ApiService.obtenerChoferes();
      await adm.ApiService.obtenerTelemetriaActiva();
    }
    if (s.puede(Modulo.usuarios)) {
      expect(await adm.ApiService.obtenerUsuariosAdmin(), isNotEmpty);
      if (s.usuario.master) {
        await adm.ApiService.obtenerAuditoriaSeguridad();
      } else {
        // La auditoría es exclusiva de la cuenta maestra.
        await expectLater(adm.ApiService.obtenerAuditoriaSeguridad(), throwsException);
      }
    }
    if (s.puede(Modulo.misRutas)) {
      await ApiService.obtenerRutasChofer(s.usuario.id);
    }
  }

  for (final (clave, roles) in [
    ('ADMIN', ['ADMINISTRADOR']),
    ('VENTAS', ['VENDEDOR']),
    ('BODEGA', ['BODEGUERO']),
    ('CHOFER1', ['CHOFER']),
    ('MULTI', ['VENDEDOR', 'BODEGUERO', 'CHOFER']),
  ]) {
    test('$clave ($roles) carga sus módulos', () async {
      final s = await entrar(clave);
      expect(s.roles, unorderedEquals(roles));
      try {
        await modulos(s);
        // Sesión restaurable al reabrir la app.
        expect((await Sesion.restaurar())?.usuario.id, s.usuario.id);
      } finally {
        await Sesion.cerrar();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('VENDEDOR no puede registrar movimientos (lo bloquea el backend)', () async {
    await entrar('VENTAS');
    try {
      final r = await adm.ApiService.obtenerProductos(size: 1);
      final p = (r['items'] as List).first;
      await expectLater(
        adm.ApiService.registrarMovimiento(p.id as String, type: 'INGRESO', quantity: 1, reason: 'smoke'),
        throwsException,
      );
    } finally {
      await Sesion.cerrar();
    }
  });
}
