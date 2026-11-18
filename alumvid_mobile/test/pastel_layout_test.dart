import 'package:alumvid_admin_desktop/shared/tema.dart';
import 'package:alumvid_admin_desktop/shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'Resumen sin recortes con texto aumentado: ${dark ? 'oscuro' : 'claro'}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: TemaAlumVid.crear(dark),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: const Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 175,
                    height: 180,
                    child: KpiCard(
                      titulo: 'Stock bajo o agotado',
                      valor: '123',
                      icono: Icons.inventory_2_outlined,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Stock bajo o agotado'), findsOneWidget);
      },
    );
  }
}
