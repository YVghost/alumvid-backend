import 'cambiar_password_screen.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'admin_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _ocultarPass = true;
  bool _cargando = false;
  String _hostActual = 'http://localhost:8080';

  @override
  void dispose() {
    _identCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargarHost();
  }

  Future<void> _cargarHost() async {
    final host = await ApiService.getBaseHost();
    if (mounted) {
      setState(() => _hostActual = host);
    }
  }

  Future<void> _abrirConfiguracionHost() async {
    final hostCtrl = TextEditingController(text: _hostActual);
    final localServer = await ApiService.getLocalServer();
    final railwayServer = await ApiService.getRailwayServer();
    if (!mounted) return;
    final nuevoHost = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: [
            Icon(
              Icons.settings_ethernet,
              color: AppTheme.primaryLight,
              size: 20,
            ),
            SizedBox(width: 8),
            Text('Conexión con el Servidor', style: TextStyle(fontSize: 15)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Local: http://localhost:8080 o IP de la PC.\nRailway: dominio HTTPS público del gateway, sin /api/v1.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: hostCtrl,
              decoration: const InputDecoration(
                labelText: 'Host del API Gateway',
                hintText: 'http://localhost:8080',
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
                hostCtrl.text = 'https://';
                return;
              }
              Navigator.pop(ctx, railwayServer);
            },
            child: const Text('Railway'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancelar',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, hostCtrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nuevoHost != null && nuevoHost.isNotEmpty) {
      try {
        await ApiService.setBaseHost(nuevoHost, clearSession: true);
      } on FormatException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
        return;
      }
      _cargarHost();
    }
  }

  Future<void> _iniciarSesion() async {
    final ident = _identCtrl.text.trim();
    final pass = _passCtrl.text;

    if (ident.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor complete su identificación y contraseña.'),
        ),
      );
      return;
    }

    setState(() => _cargando = true);

    try {
      final user = await ApiService.login(ident, pass);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => user.mustChangePassword
              ? const CambiarPasswordScreen()
              : AdminDashboardScreen(user: user),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      String msg = e.toString().replaceAll('Exception: ', '');
      if (msg.contains('SocketException') ||
          msg.contains('rechazó la conexión') ||
          msg.contains('errno = 1225')) {
        msg =
            'Error de conexión con el API Gateway (http://localhost:8080). Espere unos segundos a que los microservicios terminen de iniciar o verifique Docker.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.statusAlerta),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild semantic colors when the appearance changes.

    final colors = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.layers_outlined,
                        color: colors.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'AlumVid',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      const SelectorTema(),
                    ],
                  ),
                  const SizedBox(height: 52),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (wide) ...[
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 76),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(
                                      alpha: .10,
                                    ),
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Text(
                                    'TU OPERACIÓN, EN UN SOLO LUGAR',
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontSize: 10,
                                      letterSpacing: 1.1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                const Text(
                                  'Claridad para\ncada jornada.',
                                  style: TextStyle(
                                    fontSize: 46,
                                    height: 1.12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1.7,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Organiza tus materiales, acompaña cada pedido y mantén a tu equipo conectado.',
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 15,
                                    height: 1.7,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                for (final feature in <(IconData, String)>[
                                  (
                                    Icons.inventory_2_outlined,
                                    'Inventario y materiales',
                                  ),
                                  (
                                    Icons.receipt_long_outlined,
                                    'Pedidos y preparación',
                                  ),
                                  (
                                    Icons.local_shipping_outlined,
                                    'Rutas y entregas',
                                  ),
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 15),
                                    child: Row(
                                      children: [
                                        Icon(
                                          feature.$1,
                                          color: colors.primary,
                                          size: 21,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          feature.$2,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(34),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Bienvenido de nuevo',
                                style: TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.7,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ingresa a tu espacio de administración.',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 30),
                              TextField(
                                controller: _identCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Identificación o correo',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                              ),
                              const SizedBox(height: 18),
                              TextField(
                                controller: _passCtrl,
                                obscureText: _ocultarPass,
                                onSubmitted: (_) => _iniciarSesion(),
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _ocultarPass
                                        ? 'Mostrar contraseña'
                                        : 'Ocultar contraseña',
                                    onPressed: () => setState(
                                      () => _ocultarPass = !_ocultarPass,
                                    ),
                                    icon: Icon(
                                      _ocultarPass
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 25),
                              ElevatedButton(
                                onPressed: _cargando ? null : _iniciarSesion,
                                child: _cargando
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Ingresar'),
                              ),
                              const SizedBox(height: 20),
                              TextButton.icon(
                                onPressed: _abrirConfiguracionHost,
                                icon: const Icon(Icons.dns_outlined, size: 17),
                                label: const Text('Configurar servidor'),
                              ),
                              Text(
                                _hostActual,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 38),
                  Text(
                    'AlumVid · Gestión simple, trabajo conectado',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                    ),
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
