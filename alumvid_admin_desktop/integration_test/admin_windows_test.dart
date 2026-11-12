import 'package:alumvid_admin_desktop/screens/login_screen.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:alumvid_admin_desktop/main.dart' as app;
import 'package:alumvid_admin_desktop/services/api_service.dart';
import 'package:alumvid_admin_desktop/screens/admin_dashboard_screen.dart';
import 'package:alumvid_admin_desktop/views/pedidos_view.dart';
import 'package:alumvid_admin_desktop/views/retazos_view.dart';
import 'package:alumvid_admin_desktop/views/ubicaciones_view.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(finder, findsWidgets);
  }
  testWidgets('Windows: login real, pedidos, retazos, ubicaciones y logout', (tester) async {
    final identifier = Platform.environment['ALUMVID_QA_IDENTIFIER'];
    final password = Platform.environment['ALUMVID_QA_PASSWORD'];
    expect(identifier, isNotNull, reason: 'Usa scripts/test-admin-windows.ps1');
    expect(password, isNotNull, reason: 'Usa scripts/test-admin-windows.ps1');
    await ApiService.logout();
    app.main();
    try {
      await waitFor(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField).at(0), identifier!);
      await tester.enterText(find.byType(TextField).at(1), password!);
      await tester.tap(find.byType(ElevatedButton).first);
      await waitFor(tester, find.byType(AdminDashboardScreen));
      for (final entry in <(IconData, Type)>[
        (Icons.receipt_long_rounded, PedidosView),
        (Icons.content_cut_rounded, RetazosView),
        (Icons.grid_view_rounded, UbicacionesView),
      ]) {
        await tester.tap(find.byIcon(entry.$1).first);
        await waitFor(tester, find.byType(entry.$2));
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Abrir gestión completa'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Cerrar Sesión'));
      await waitFor(tester, find.byType(LoginScreen));
      expect(await ApiService.getToken() == null, isTrue, reason: 'La sesión debe eliminarse después del logout');
    } finally {
      await ApiService.logout();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
