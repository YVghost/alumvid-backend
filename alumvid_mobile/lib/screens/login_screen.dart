import 'package:alumvid_admin_desktop/shared/server_config.dart';
import 'package:alumvid_admin_desktop/shared/tema.dart';
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
    final localServer = await ApiService.getLocalServer();
    final railwayServer = await ApiService.getRailwayServer();
    if (!mounted) return;
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Servidor de AlumVid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Local: misma Wi-Fi e IP de la computadora. Railway: pega el dominio HTTPS del gateway y guarda. Puedes volver a Local en cualquier momento.',
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
            onPressed: () => Navigator.pop(ctx, localServer),
            child: const Text('Local'),
          ),
          TextButton(
            onPressed: () {
              if (railwayServer.isEmpty) {
                controller.text = 'https://';
                return;
              }
              Navigator.pop(ctx, railwayServer);
            },
            child: const Text('Railway'),
          ),
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
        if (!ApiService.esErrorDeConexion(e) ||
            !mounted ||
            !ServerConfig.isLocal(Uri.parse(ApiService.baseUrl))) {
          rethrow;
        }
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
    Theme.of(context); // Rebuild semantic colors when the appearance changes.

    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.layers_outlined,
                        color: colors.primary,
                        size: 25,
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text(
                          'AlumVid',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.8,
                          ),
                        ),
                      ),
                      const SelectorTema(compacto: true),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Apariencia.instancia.esOscuro
                            ? colors.primary.withValues(alpha: .15)
                            : AppColors.lavender,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: Icon(
                        Icons.space_dashboard_outlined,
                        size: 30,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Todo listo para\nuna nueva jornada.',
                    style: TextStyle(
                      fontSize: 31,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tus materiales, pedidos y rutas. Cada herramienta, según tu rol.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Inicia sesión',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_errorMensaje != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _errorMensaje!,
                              style: TextStyle(
                                color: colors.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        TextField(
                          controller: _emailController,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Identificación o correo',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_mostrarPassword,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _iniciarSesion(),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _mostrarPassword
                                  ? 'Ocultar contraseña'
                                  : 'Mostrar contraseña',
                              onPressed: () => setState(
                                () => _mostrarPassword = !_mostrarPassword,
                              ),
                              icon: Icon(
                                _mostrarPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        ElevatedButton(
                          onPressed: _cargando ? null : _iniciarSesion,
                          child: _cargando
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.onPrimary,
                                  ),
                                )
                              : const Text('Iniciar sesión'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(
                        Icons.dns_outlined,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _buscandoServidor
                              ? 'Buscando servidor…'
                              : Uri.tryParse(ApiService.baseUrl)?.authority ??
                                    ApiService.baseUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _buscandoServidor
                            ? null
                            : _configurarServidor,
                        child: const Text('Servidor'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
