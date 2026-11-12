import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class CambiarPasswordScreen extends StatefulWidget {
  const CambiarPasswordScreen({super.key});
  @override
  State<CambiarPasswordScreen> createState() => _CambiarPasswordScreenState();
}

class _CambiarPasswordScreenState extends State<CambiarPasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_next.text.length < 12 ||
        _next.text != _confirm.text ||
        _next.text == _current.text) {
      setState(
        () => _error =
            'Usa al menos 12 caracteres, una clave diferente y confirma la misma contraseña.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.cambiarPassword(_current.text, _next.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cambiar contraseña temporal'),
      automaticallyImplyLeading: false,
    ),
    body: Center(
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Debes cambiar tu contraseña antes de administrar. Después vuelve a iniciar sesión.',
              ),
              TextField(
                controller: _current,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña actual',
                ),
              ),
              TextField(
                controller: _next,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña',
                ),
              ),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar contraseña',
                ),
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Guardando...' : 'Guardar contraseña'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await ApiService.logout();
                        if (context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                            (_) => false,
                          );
                        }
                      },
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
