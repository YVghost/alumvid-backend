import 'package:alumvid_admin_desktop/models/user.dart';
import 'package:alumvid_mobile/core/sesion.dart';
import 'package:alumvid_mobile/screens/home_shell.dart';
import 'package:alumvid_mobile/screens/rutas_screen.dart';
import 'package:alumvid_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Sesion sesionCon(List<String> roles) => Sesion.paraPruebas(
  AppUser(
    id: 'u1',
    identification: 'TEST',
    fullName: 'Usuario Prueba',
    email: 'test@example.test',
    roles: roles,
    master: false,
    active: true,
  ),
);

void main() {
  group('Matriz de permisos (igual que el backend)', () {
    test('ADMINISTRADOR ve todos los módulos administrativos', () {
      final s = sesionCon(['ADMINISTRADOR']);
      expect(s.modulos, [
        Modulo.inicio,
        Modulo.monitoreo,
        Modulo.rutas,
        Modulo.pedidos,
        Modulo.inventario,
        Modulo.retazos,
        Modulo.bodega,
        Modulo.usuarios,
      ]);
      expect(s.puedeMoverStock, isTrue);
      expect(s.puedeEditarCatalogo, isTrue);
      expect(s.soloChofer, isFalse);
    });

    test('VENDEDOR consulta, pero no mueve stock ni ve logística ni usuarios', () {
      final s = sesionCon(['VENDEDOR']);
      expect(s.modulos, [
        Modulo.inicio,
        Modulo.pedidos,
        Modulo.inventario,
        Modulo.retazos,
        Modulo.bodega,
      ]);
      expect(s.puedeMoverStock, isFalse);
      expect(s.puedeEditarCatalogo, isFalse);
    });

    test('BODEGUERO mueve stock pero no edita el catálogo', () {
      final s = sesionCon(['BODEGUERO']);
      expect(s.puede(Modulo.inventario), isTrue);
      expect(s.puede(Modulo.usuarios), isFalse);
      expect(s.puede(Modulo.rutas), isFalse);
      expect(s.puedeMoverStock, isTrue);
      expect(s.puedeEditarCatalogo, isFalse);
    });

    test('CHOFER sin otros roles entra directo a sus rutas', () {
      final s = sesionCon(['CHOFER']);
      expect(s.soloChofer, isTrue);
      expect(s.puede(Modulo.pedidos), isFalse);
      expect(pantallaInicial(s), isA<RutasScreen>());
    });

    test('Varios roles suman sus módulos', () {
      final s = sesionCon(['VENDEDOR', 'BODEGUERO', 'CHOFER']);
      expect(s.puede(Modulo.misRutas), isTrue);
      expect(s.puede(Modulo.pedidos), isTrue);
      expect(s.puede(Modulo.usuarios), isFalse);
      expect(s.soloChofer, isFalse);
      expect(pantallaInicial(s), isA<HomeShell>());
    });
  });

  group('Navegación por rol', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> abrir(WidgetTester t, List<String> roles) async {
      await t.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: HomeShell(sesion: sesionCon(roles))),
      );
      await t.pump(const Duration(milliseconds: 100));
    }

    String? etiqueta(Widget w) => w is NavigationDestination ? w.label : null;

    testWidgets('VENDEDOR: cinco pestañas sin "Más"', (t) async {
      await abrir(t, ['VENDEDOR']);
      final labels = t
          .widgetList(find.byType(NavigationDestination))
          .map(etiqueta)
          .toList();
      expect(labels, ['Inicio', 'Pedidos', 'Inventario', 'Piezas', 'Bodega']);
    });

    testWidgets('ADMINISTRADOR: módulos extra agrupados en "Más"', (t) async {
      await abrir(t, ['ADMINISTRADOR']);
      final labels = t
          .widgetList(find.byType(NavigationDestination))
          .map(etiqueta)
          .toList();
      expect(labels, ['Inicio', 'Monitoreo', 'Rutas', 'Pedidos', 'Más']);
      await t.tap(find.text('Más'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Usuarios'), findsOneWidget);
      expect(find.text('Inventario'), findsWidgets);
    });
  });
}
