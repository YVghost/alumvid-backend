import 'package:alumvid_admin_desktop/shared/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Apariencia.instancia.cargar();
  });
  test('Theme preference survives a reload', () async {
    expect(Apariencia.instancia.modo, ThemeMode.light);
    await Apariencia.instancia.cambiar(ThemeMode.dark);
    await Apariencia.instancia.cargar();
    expect(Apariencia.instancia.modo, ThemeMode.dark);
  });
  test('Both palettes keep readable text on their main surfaces', () {
    for (final dark in [false, true]) {
      final p = PaletaAlumVid(dark);
      for (final ink in [p.text, p.textMuted, p.primary]) {
        final a = ink.computeLuminance(), b = p.surface.computeLuminance();
        final contrast = (a > b
            ? (a + .05) / (b + .05)
            : (b + .05) / (a + .05));
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
    }
  });
  testWidgets('Changing theme preserves a form and updates its appearance', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Texto conservado');
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: Apariencia.instancia,
        builder: (context, _) => MaterialApp(
          theme: TemaAlumVid.claro,
          darkTheme: TemaAlumVid.oscuro,
          themeMode: Apariencia.instancia.modo,
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: controller),
                const SelectorTema(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(TextField))).brightness,
      Brightness.dark,
    );
    expect(controller.text, 'Texto conservado');
    expect(
      (await SharedPreferences.getInstance()).getString(Apariencia.clave),
      'dark',
    );
    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(TextField))).brightness,
      Brightness.light,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
