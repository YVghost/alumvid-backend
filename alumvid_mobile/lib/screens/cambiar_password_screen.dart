import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'rutas_screen.dart';

class CambiarPasswordScreen extends StatefulWidget {
  final String tempPassword;
  final Map<String, dynamic> choferData;

  const CambiarPasswordScreen({
    super.key,
    required this.tempPassword,
    required this.choferData,
  });

  @override
  State<CambiarPasswordScreen> createState() => _CambiarPasswordScreenState();
}

class _CambiarPasswordScreenState extends State<CambiarPasswordScreen> {
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _mostrarPassword = false;
  bool _cargando = false;
  String? _errorMensaje;

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarNuevaContrasena() async {
    final nueva = _newPasswordCtrl.text.trim();
    final confirm = _confirmPasswordCtrl.text.trim();

    if (nueva.length < 12) {
      setState(() => _errorMensaje = 'La contraseña debe contener al menos 12 caracteres.');
      return;
    }

    if (nueva == widget.tempPassword.trim()) {
      setState(() => _errorMensaje = 'La nueva contraseña debe ser diferente a la contraseña temporal asignada.');
      return;
    }

    if (nueva != confirm) {
      setState(() => _errorMensaje = 'Las contraseñas ingresadas no coinciden.');
      return;
    }

    setState(() {
      _cargando = true;
      _errorMensaje = null;
    });

    try {
      // 1. Ejecutar el cambio de clave en el backend
      await ApiService.cambiarPassword(
        currentPassword: widget.tempPassword,
        newPassword: nueva,
      );

      // 2. Iniciar sesión automáticamente con la nueva credencial definitiva
      final emailOrIdent = widget.choferData['email'] ?? widget.choferData['identification'] ?? '';
      final freshLogin = await ApiService.login(emailOrIdent, nueva);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña actualizada con éxito. ¡Bienvenido a AlumVid!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );

      // 3. Redirigir directamente al panel de rutas
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => RutasScreen(choferData: freshLogin)),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMensaje = e.toString().replaceAll('Exception: ', '');
          _cargando = false;
        });
      }
    }
  }

  void _cancelarYSalir() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.choferData['nombre'] ?? widget.choferData['fullName'] ?? 'Colaborador';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icono de Seguridad
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF3B82F6), width: 2),
                ),
                child: const Icon(Icons.lock_reset, color: Color(0xFF60A5FA), size: 36),
              ),
              const SizedBox(height: 20),

              const Text(
                'Actualización Obligatoria de Contraseña',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'Hola $nombre, por políticas de seguridad del sistema AlumVid debes definir tu contraseña personal definitiva antes de iniciar tu jornada.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              if (_errorMensaje != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0x33E11D48),
                    border: Border.all(color: const Color(0x66E11D48)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFFB7185), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMensaje!,
                          style: const TextStyle(color: Color(0xFFFB7185), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Campo Nueva Contraseña
              TextField(
                controller: _newPasswordCtrl,
                obscureText: !_mostrarPassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nueva Contraseña Definitiva',
                  hintText: 'Mínimo 12 caracteres',
                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFF111827),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  prefixIcon: const Icon(Icons.key, color: Color(0xFF60A5FA), size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _mostrarPassword ? Icons.visibility : Icons.visibility_off,
                      color: const Color(0xFF94A3B8),
                    ),
                    onPressed: () => setState(() => _mostrarPassword = !_mostrarPassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Campo Confirmar Contraseña
              TextField(
                controller: _confirmPasswordCtrl,
                obscureText: !_mostrarPassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Confirmar Nueva Contraseña',
                  hintText: 'Repita la contraseña exactamente',
                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFF111827),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  prefixIcon: const Icon(Icons.check_circle_outline, color: Color(0xFF60A5FA), size: 20),
                ),
              ),
              const SizedBox(height: 24),

              // Botón Guardar
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
                onPressed: _cargando ? null : _guardarNuevaContrasena,
                child: _cargando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Actualizar Contraseña y Continuar',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(height: 12),

              // Botón Cancelar y Cerrar Sesión
              TextButton(
                onPressed: _cargando ? null : _cancelarYSalir,
                child: const Text(
                  'Cancelar y Cerrar Sesión',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
