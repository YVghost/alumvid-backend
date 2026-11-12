// Renderiza los módulos compartidos con datos reales del backend (no corre por defecto).
//
//   $env:ALUMVID_SMOKE_STATE = "..\entrega-pruebas\estado.local.json"
//   flutter test test/render_modulos_test.dart
//
// Detecta errores de diseño (desbordes, restricciones inválidas) que el
// analizador no ve, en tamaño teléfono y escritorio.
import 'dart:convert';
import 'dart:io';

import 'package:alumvid_admin_desktop/modulos/bodega/bodega_modulo.dart';
import 'package:alumvid_admin_desktop/modulos/inventario/inventario_modulo.dart';
import 'package:alumvid_admin_desktop/modulos/pedidos/pedidos_modulo.dart';
import 'package:alumvid_admin_desktop/modulos/piezas/piezas_modulo.dart';
import 'package:alumvid_admin_desktop/modulos/rutas/rutas_modulo.dart';
import 'package:alumvid_admin_desktop/modulos/usuarios/usuarios_modulo.dart';
import 'package:alumvid_admin_desktop/models/producto.dart';
import 'package:alumvid_admin_desktop/modulos/inventario/ficha_pieza.dart';
import 'package:alumvid_admin_desktop/modulos/inventario/producto_detalle.dart';
import 'package:alumvid_admin_desktop/modulos/pedidos/pedido_detalle.dart';
import 'package:alumvid_admin_desktop/modulos/pedidos/pedido_form.dart';
import 'package:alumvid_admin_desktop/modulos/rutas/crear_ruta.dart';
import 'package:alumvid_admin_desktop/modulos/rutas/ruta_detalle.dart';
import 'package:alumvid_admin_desktop/services/api_negocio.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:alumvid_admin_desktop/shared/tema.dart';
import 'package:alumvid_mobile/core/sesion.dart';
import 'package:alumvid_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final statePath = Platform.environment['ALUMVID_SMOKE_STATE'];
  final server = Platform.environment['ALUMVID_SMOKE_SERVER'] ?? 'http://localhost:8080';
  if (statePath == null) {
    test('render de módulos (omitida: define ALUMVID_SMOKE_STATE)', () {}, skip: true);
    return;
  }
  final estado = jsonDecode(File(statePath).readAsStringSync()) as Map<String, dynamic>;
  final cuentas = Map<String, dynamic>.from(estado['accounts'] as Map);
  final pasos = Map<String, dynamic>.from(estado['steps'] as Map);
  String id(String paso) => '${(pasos[paso] as Map)['order'] is Map ? ((pasos[paso] as Map)['order'] as Map)['id'] : (pasos[paso] as Map)['id']}';
  late Sesion sesion;

  setUpAll(() async {
    HttpOverrides.global = null; // red real
    // La caché de mapas pide un directorio nativo que no existe en pruebas.
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await initializeDateFormatting('es');
  });

  Future<void> entrar(WidgetTester t) async {
    await t.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await ApiService.initialize();
      await ApiService.setServer(server);
      final a = cuentas['ADMIN'] as Map<String, dynamic>;
      sesion = await Sesion.establecer(await ApiService.login(a['identification'] as String, a['password'] as String));
    });
  }

  /// Deja que lleguen las respuestas HTTP y redibuja.
  Future<void> esperarDatos(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  final pantallas = {'teléfono': const Size(412, 915), 'escritorio': const Size(1440, 900)};
  final modulos = <String, Widget Function()>{
    'Pedidos': () => PedidosModulo(permisos: sesion.permisos),
    'Inventario': () => InventarioModulo(permisos: sesion.permisos),
    'Piezas': () => PiezasModulo(permisos: sesion.permisos),
    'Bodega': () => BodegaModulo(permisos: sesion.permisos),
    'Rutas': () => RutasModulo(permisos: sesion.permisos),
    'Usuarios': () => UsuariosModulo(permisos: sesion.permisos),
  };

  /// Excepción de diseño real (ignora plugins nativos que no existen en pruebas).
  void sinErrores(WidgetTester t) {
    final e = t.takeException();
    if (e is MissingPluginException) return;
    if (e is FlutterError) debugPrint(e.toStringDeep());
    expect(e, isNull);
  }

  // Pantallas de detalle y formularios con datos demo concretos.
  final detalles = <String, Future<Widget> Function()>{
    'Pedido listo (detalle)': () async => PedidoDetalle(pedidoId: id('order:LISTO_DESPACHO'), permisos: sesion.permisos),
    'Pedido con falta de material': () async => PedidoDetalle(pedidoId: id('order:FALTANTE'), permisos: sesion.permisos),
    'Nuevo pedido': () async => const PedidoForm(),
    'Perfil de aluminio (piezas)': () async => ProductoDetalle(producto: await _producto(id('product:ALU-PER')), permisos: sesion.permisos),
    'Tornillos (unidades)': () async => ProductoDetalle(producto: await _producto(id('product:TOR')), permisos: sesion.permisos),
    'Ficha de pieza': () async => FichaPieza(piezaId: '${(await Api.buscarPiezas(tipo: 'VIDRIO')).first['id']}', permisos: sesion.permisos),
    'Ruta (detalle)': () async => RutaDetalle(rutaId: '${(await Api.rutas()).first['id']}', permisos: sesion.permisos),
    'Crear ruta': () async => const CrearRuta(),
  };
  for (final p in pantallas.entries) {
    for (final d in detalles.entries) {
      testWidgets('${d.key} en ${p.key}', (t) async {
        await entrar(t);
        final original = FlutterError.onError;
        FlutterError.onError = (e) {
          if (e.exception is! MissingPluginException) debugPrint(e.toString());
          original?.call(e);
        };
        addTearDown(() => FlutterError.onError = original);
        t.view.physicalSize = p.value;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        late Widget pantalla;
        await t.runAsync(() async => pantalla = await d.value());
        await t.pumpWidget(MaterialApp(theme: TemaAlumVid.oscuro, home: pantalla));
        await esperarDatos(t);
        sinErrores(t);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 30));
        sinErrores(t);
      });
    }
  }

  for (final p in pantallas.entries) {
    for (final m in modulos.entries) {
      testWidgets('${m.key} en ${p.key}', (t) async {
        await entrar(t);
        final original = FlutterError.onError;
        FlutterError.onError = (d) {
          if (d.exception is! MissingPluginException) debugPrint(d.toString());
          original?.call(d);
        };
        addTearDown(() => FlutterError.onError = original);
        t.view.physicalSize = p.value;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(theme: TemaAlumVid.oscuro, home: m.value()));
        await esperarDatos(t);
        sinErrores(t);
        // Abre el primer elemento (detalle) cuando hay tarjetas.
        final tarjetas = find.byType(InkWell);
        if (tarjetas.evaluate().length > 3 && m.key != 'Usuarios') {
          await t.tap(tarjetas.at(3), warnIfMissed: false);
          await esperarDatos(t);
          sinErrores(t);
        }
        // Vacía los temporizadores de timeout de peticiones en curso.
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 30));
        sinErrores(t);
      });
    }
  }
}

Future<Producto> _producto(String productoId) async {
  final r = await adm.ApiService.obtenerProductos(includeInactive: true, size: 100);
  return (r['items'] as List).cast<Producto>().firstWhere((p) => p.id == productoId);
}
