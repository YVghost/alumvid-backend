import 'package:alumvid_admin_desktop/shared/tema.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/app_toast.dart';
import 'login_screen.dart';
import '../core/sesion.dart';
import 'home_shell.dart';

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
      setState(
        () => _errorMensaje =
            'La contraseña debe contener al menos 12 caracteres.',
      );
      return;
    }

    if (nueva == widget.tempPassword.trim()) {
      setState(
        () => _errorMensaje = 'La nueva contraseña debe ser diferente a la contraseña temporal asignada.',
      );
      return;
    }

    if (nueva != confirm) {
      setState(
        () => _errorMensaje = 'Las contraseñas ingresadas no coinciden.',
      );
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
      final emailOrIdent =
          widget.choferData['email'] ??
          widget.choferData['identification'] ??
          '';
      final freshLogin = await ApiService.login(emailOrIdent, nueva);

      final sesion = await Sesion.establecer(freshLogin);
      if (!mounted) return;
      AppToast.success(
        context,
        'Contraseña actualizada con éxito. ¡Bienvenido a AlumVid!',
      );

      // 3. Redirigir directamente al panel de rutas
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => pantallaInicial(sesion)),
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
    Theme.of(context); // Rebuild semantic colors when the appearance changes.

    final nombre =
        widget.choferData['nombre'] ??
        widget.choferData['fullName'] ??
        'Colaborador';

    return Scaffold(
      backgroundColor: AppColors.background,
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
                  color: AppColors.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF3B82F6), width: 2),
                ),
                child: const Icon(
                  Icons.lock_reset,
                  color: Color(0xFF60A5FA),
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Actualización Obligatoria de Contraseña',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'Hola $nombre, por políticas de seguridad del sistema AlumVid debes definir tu contraseña personal definitiva antes de iniciar tu jornada.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
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
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFFB7185),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMensaje!,
                          style: const TextStyle(
                            color: Color(0xFFFB7185),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Campo Nueva Contraseña
              TextField(
                controller: _newPasswordCtrl,
                obscureText: !_mostrarPassword,
                style: TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  labelText: 'Nueva Contraseña Definitiva',
                  hintText: 'Mínimo 12 caracteres',
                  hintStyle: TextStyle(color: AppColors.textDim, fontSize: 12),
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  prefixIcon: const Icon(
                    Icons.key,
                    color: Color(0xFF60A5FA),
                    size: 20,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _mostrarPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () =>
                        setState(() => _mostrarPassword = !_mostrarPassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Campo Confirmar Contraseña
              TextField(
                controller: _confirmPasswordCtrl,
                obscureText: !_mostrarPassword,
                style: TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  labelText: 'Confirmar Nueva Contraseña',
                  hintText: 'Repita la contraseña exactamente',
                  hintStyle: TextStyle(color: AppColors.textDim, fontSize: 12),
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  prefixIcon: const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF60A5FA),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Botón Guardar
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
                onPressed: _cargando ? null : _guardarNuevaContrasena,
                child: _cargando
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: AppColors.text,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Actualizar Contraseña y Continuar',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 12),

              // Botón Cancelar y Cerrar Sesión
              TextButton(
                onPressed: _cargando ? null : _cancelarYSalir,
                child: Text(
                  'Cancelar y Cerrar Sesión',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
