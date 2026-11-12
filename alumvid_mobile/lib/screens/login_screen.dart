import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'cambiar_password_screen.dart';
import '../core/sesion.dart';
import 'home_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _cargando = false;
  bool _mostrarPassword = false;
  String? _errorMensaje;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  static const _buscarToken = '__buscar_servidor__';
  bool _buscandoServidor = false;

  /// Escanea la Wi-Fi actual buscando el backend. Devuelve true si lo encontró.
  Future<bool> _buscarServidor() async {
    setState(() {
      _buscandoServidor = true;
      _errorMensaje = null;
    });
    try {
      final encontrado = await ApiService.descubrirServidor();
      if (!mounted) return encontrado != null;
      if (encontrado == null) {
        setState(
          () => _errorMensaje =
              'No se encontró el servidor en esta red. Verifica que la PC y el teléfono estén en la misma Wi-Fi y que el backend esté encendido (ejecuta mostrar_ip_servidor.bat en la PC).',
        );
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Servidor encontrado: $encontrado')),
      );
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _errorMensaje = 'Error buscando el servidor: $e');
      }
      return false;
    } finally {
      if (mounted) setState(() => _buscandoServidor = false);
    }
  }

  Future<void> _configurarServidor() async {
    final controller = TextEditingController(text: ApiService.baseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Servidor de AlumVid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'El teléfono y la computadora deben estar en la misma red. Usa la IP de la computadora y el puerto 8080.',
            ),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Dirección del servidor',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, _buscarToken),
            icon: const Icon(Icons.wifi_find),
            label: const Text('Buscar automáticamente'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    if (value == _buscarToken) {
      await _buscarServidor();
      return;
    }
    try {
      await ApiService.setServer(value);
      if (mounted) setState(() => _errorMensaje = null);
    } on FormatException catch (e) {
      if (mounted) setState(() => _errorMensaje = e.message);
    }
  }

  Future<void> _iniciarSesion() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _errorMensaje = 'Ingresa tu identificación y contraseña.');
      return;
    }
    setState(() {
      _cargando = true;
      _errorMensaje = null;
    });

    try {
      Map<String, dynamic> res;
      try {
        res = await ApiService.login(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } catch (e) {
        // Si cambiamos de red, el servidor guardado ya no responde: buscarlo y reintentar.
        if (!ApiService.esErrorDeConexion(e) || !mounted) rethrow;
        if (!await _buscarServidor()) return;
        res = await ApiService.login(
          _emailController.text.trim(),
          _passwordController.text,
        );
      }

      if (!mounted) return;

      final bool mustChange =
          res['mustChangePassword'] == true ||
          (res['user'] != null && res['user']['mustChangePassword'] == true);

      if (mustChange) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CambiarPasswordScreen(
              tempPassword: _passwordController.text,
              choferData: res,
            ),
          ),
        );
      } else {
        final sesion = await Sesion.establecer(res);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => pantallaInicial(sesion)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMensaje = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _buscandoServidor
                          ? 'Buscando servidor en la red...'
                          : 'Servidor: ${Uri.tryParse(ApiService.baseUrl)?.authority ?? ApiService.baseUrl}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_buscandoServidor)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  TextButton.icon(
                    onPressed: _cargando || _buscandoServidor
                        ? null
                        : _configurarServidor,
                    icon: const Icon(Icons.settings),
                    label: const Text('Servidor'),
                  ),
                ],
              ),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4ED8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text(
                    'GF',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'AlumVid',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'Operación móvil: pedidos, inventario y rutas',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 32),
              if (_errorMensaje != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0x33E11D48),
                    border: Border.all(color: const Color(0x66E11D48)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMensaje!,
                    style: const TextStyle(
                      color: Color(0xFFFB7185),
                      fontSize: 13,
                    ),
                  ),
                ),
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Identificación o Correo',
                  hintText: 'Cédula o usuario@alumvid.com',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFF111827),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: !_mostrarPassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Contrasena',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFF111827),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _mostrarPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: const Color(0xFF94A3B8),
                    ),
                    onPressed: () {
                      setState(() {
                        _mostrarPassword = !_mostrarPassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _cargando ? null : _iniciarSesion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _cargando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Iniciar Sesion',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
