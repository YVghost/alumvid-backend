import 'package:alumvid_admin_desktop/models/retazo_pieza.dart';
import 'package:alumvid_admin_desktop/models/pedido_comercial.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alumvid_admin_desktop/main.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('El administrador usa gateway 8080', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await ApiService.getBaseHost(), 'http://localhost:8080');
  });
  test('Un host personalizado no se migra a otro puerto', () async {
    await ApiService.setBaseHost('http://localhost:8090');
    expect(await ApiService.getBaseHost(), 'http://localhost:8090');
  });
  testWidgets('Login sin credenciales embebidas', (tester) async {
    await tester.pumpWidget(const AlumVidAdminApp());
    await tester.pumpAndSettle();
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.length, 2);
    for (final field in fields) {
      expect(field.controller!.text, isEmpty);
    }
  });
  test('Los decimales de las APIs admiten texto y numeros', () {
    expect(ProductoRetazo.fromJson({'stock': '1.500000000000'}).stock, 1.5);
    expect(PiezaRetazo.fromJson({'lengthM': '3.2'}).lengthM, 3.2);
    expect(PiezaRetazo.fromJson({'widthCm': 183, 'heightCm': 244}).heightCm, 244);
    final order = PedidoComercial.fromJson({'number': 12, 'total': '25.50', 'expiresAt': '2026-11-14T12:00:00Z'});
    expect(order.total, 25.5);
    expect(order.expiresAt, isNotNull);
  });
}
