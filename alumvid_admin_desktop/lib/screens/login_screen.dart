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
  final _identCtrl = TextEditingController(text: '1700000000');
  final _passCtrl = TextEditingController(text: 'AlumVidAdmin2026!');
  bool _ocultarPass = true;
  bool _cargando = false;
  String _hostActual = 'http://localhost:8080';

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
    final nuevoHost = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.settings_ethernet, color: AppTheme.primaryLight, size: 20),
            SizedBox(width: 8),
            Text('Conexión con el Servidor', style: TextStyle(fontSize: 15)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'En Windows Escritorio usa http://localhost:8080.\nPara emulador Android usa http://10.0.2.2:8080.',
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, hostCtrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nuevoHost != null && nuevoHost.isNotEmpty) {
      await ApiService.setBaseHost(nuevoHost);
      _cargarHost();
    }
  }

  Future<void> _iniciarSesion() async {
    final ident = _identCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (ident.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor complete su identificación y contraseña.')),
      );
      return;
    }

    setState(() => _cargando = true);

    try {
      final user = await ApiService.login(ident, pass);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminDashboardScreen(user: user)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      String msg = e.toString().replaceAll('Exception: ', '');
      if (msg.contains('SocketException') || msg.contains('rechazó la conexión') || msg.contains('errno = 1225')) {
        msg = 'Error de conexión con el API Gateway (http://localhost:8080). Espere unos segundos a que los microservicios terminen de iniciar o verifique Docker.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppTheme.statusAlerta,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo e Identidad AlumVid
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'AV',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'AlumVid — Centro de Control',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Supervisión y Gestión Logística en Tiempo Real',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Campo Identificación
                TextField(
                  controller: _identCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Identificación o Correo',
                    hintText: '1700000000 o admin@alumvid.com',
                    prefixIcon: Icon(Icons.badge, size: 20, color: AppTheme.primaryLight),
                  ),
                ),
                const SizedBox(height: 14),

                // Campo Contraseña
                TextField(
                  controller: _passCtrl,
                  obscureText: _ocultarPass,
                  decoration: InputDecoration(
                    labelText: 'Contraseña de Administrador',
                    prefixIcon: const Icon(Icons.lock, size: 20, color: AppTheme.primaryLight),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _ocultarPass ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.textDim,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() => _ocultarPass = !_ocultarPass);
                      },
                    ),
                  ),
                  onSubmitted: (_) => _iniciarSesion(),
                ),

                const SizedBox(height: 22),

                // Botón Ingresar
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                    onPressed: _cargando ? null : _iniciarSesion,
                    child: _cargando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Ingresar al Panel Administrativo',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // Conector e indicador de servidor
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.statusCompletada,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Servidor: $_hostActual',
                        style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings, size: 16, color: AppTheme.primaryLight),
                      tooltip: 'Cambiar dirección del servidor',
                      onPressed: _abrirConfiguracionHost,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
