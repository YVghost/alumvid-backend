import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preference is local to the device and survives login/logout.
class Apariencia extends ChangeNotifier {
  Apariencia._();
  static final Apariencia instancia = Apariencia._();
  static const clave = 'alumvid_theme_mode';
  ThemeMode _modo = ThemeMode.light;
  ThemeMode get modo => _modo;
  bool get esOscuro => _modo == ThemeMode.dark;

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _modo = prefs.getString(clave) == 'dark' ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> cambiar(ThemeMode value) async {
    if (value == _modo) return;
    _modo = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(clave, value == ThemeMode.dark ? 'dark' : 'light');
  }
}

class SelectorTema extends StatelessWidget {
  const SelectorTema({super.key, this.compacto = false});
  final bool compacto;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Apariencia.instancia,
    builder: (context, _) {
      final actual = Apariencia.instancia;
      if (compacto) {
        return IconButton(
          tooltip: actual.esOscuro ? 'Usar tema claro' : 'Usar tema oscuro',
          onPressed: () => actual.cambiar(
            actual.esOscuro ? ThemeMode.light : ThemeMode.dark,
          ),
          icon: Icon(
            actual.esOscuro
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
        );
      }
      return SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('Claro'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('Oscuro'),
          ),
        ],
        selected: {actual.modo},
        onSelectionChanged: (selection) => actual.cambiar(selection.first),
      );
    },
  );
}
