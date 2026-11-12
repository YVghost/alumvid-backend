import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';

/// Cambio de la propia contraseña. Al terminar, el backend cierra todas las
/// sesiones, así que [alTerminar] debe llevar al inicio de sesión.
Future<void> cambiarMiClave(BuildContext context, {required VoidCallback alTerminar}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CambiarClave(),
  );
  if (ok == true) alTerminar();
}

class _CambiarClave extends StatefulWidget {
  const _CambiarClave();

  @override
  State<_CambiarClave> createState() => _CambiarClaveState();
}

class _CambiarClaveState extends State<_CambiarClave> {
  final _form = GlobalKey<FormState>();
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _repite = TextEditingController();
  bool _ver = false;
  bool _enviando = false;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _repite.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _enviando = true);
    try {
      await ApiService.cambiarPassword(_actual.text, _nueva.text);
      if (!mounted) return;
      avisoOk(context, 'Contraseña actualizada. Inicia sesión con tu nueva clave.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        avisoError(context, e.toString().contains('400') ? 'La contraseña actual es incorrecta o la nueva no cumple las reglas' : e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label, {String? help}) => InputDecoration(
      labelText: label,
      helperText: help,
      suffixIcon: IconButton(
        tooltip: _ver ? 'Ocultar' : 'Mostrar',
        icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
        onPressed: () => setState(() => _ver = !_ver),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Cambiar mi contraseña', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Text('Por seguridad se cerrarán tus sesiones abiertas.', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _actual,
              obscureText: !_ver,
              decoration: deco('Contraseña actual'),
              validator: (v) => (v ?? '').isEmpty ? 'Obligatoria' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nueva,
              obscureText: !_ver,
              decoration: deco('Contraseña nueva', help: 'Mínimo 12 caracteres'),
              validator: (v) {
                if ((v ?? '').length < 12) return 'Mínimo 12 caracteres';
                if (v == _actual.text) return 'Debe ser distinta de la actual';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _repite,
              obscureText: !_ver,
              decoration: deco('Repite la contraseña nueva'),
              validator: (v) => v != _nueva.text ? 'No coincide' : null,
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _enviando ? null : _guardar, child: const Text('Cambiar contraseña')),
          ],
        ),
      ),
    );
  }
}
