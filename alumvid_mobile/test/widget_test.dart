import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alumvid_mobile/main.dart';

void main() {
  testWidgets('Login renders without embedded credentials', (tester) async {
    await tester.pumpWidget(const AlumVidApp());
    expect(find.text('AlumVid'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.controller!.text, isEmpty);
    }
  });

  testWidgets('Empty login is rejected without a network request', (tester) async {
    await tester.pumpWidget(const AlumVidApp());
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(find.text('Ingresa tu identificación y contraseña.'), findsOneWidget);
  });
}
