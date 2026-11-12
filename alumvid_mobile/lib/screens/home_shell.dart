import 'package:flutter/material.dart';

import '../core/sesion.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'login_screen.dart';
import 'package:alumvid_admin_desktop/modulos/bodega/bodega_modulo.dart';
import 'package:alumvid_admin_desktop/modulos/inventario/inventario_modulo.dart';
import 'package:alumvid_admin_desktop/modulos/pedidos/pedidos_modulo.dart';
import 'package:alumvid_admin_desktop/modulos/piezas/piezas_modulo.dart';
import 'package:alumvid_admin_desktop/modulos/rutas/rutas_modulo.dart';
import 'package:alumvid_admin_desktop/modulos/usuarios/cambiar_clave.dart';
import 'package:alumvid_admin_desktop/modulos/usuarios/usuarios_modulo.dart';
import 'modulos/inicio_screen.dart';
import 'modulos/monitoreo_screen.dart';
import 'rutas_screen.dart';

/// Pantalla de inicio tras el login: muestra solo los módulos que permiten
/// los roles del usuario. Un chofer sin otros roles entra directo a sus rutas.
Widget pantallaInicial(Sesion s) =>
    s.soloChofer ? RutasScreen(choferData: s.datos) : HomeShell(sesion: s);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.sesion});
  final Sesion sesion;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _maxPestanas = 5;

  late final List<Modulo> _modulos = widget.sesion.modulos;
  late final bool _conMas = _modulos.length > _maxPestanas;
  late final List<Modulo> _principales =
      _conMas ? _modulos.take(_maxPestanas - 1).toList() : _modulos;
  late final List<Modulo> _extra =
      _conMas ? _modulos.skip(_maxPestanas - 1).toList() : const [];

  int _indice = 0;

  /// Pestañas ya visitadas: se construyen bajo demanda y se conservan.
  final Set<int> _visitadas = {0};

  int get _totalPestanas => _principales.length + (_conMas ? 1 : 0);

  void _seleccionar(int i) => setState(() {
    _indice = i;
    _visitadas.add(i);
  });

  void _irA(Modulo m) {
    final i = _principales.indexOf(m);
    if (i >= 0) {
      _seleccionar(i);
    } else {
      _abrirModulo(m);
    }
  }

  void _abrirModulo(Modulo m) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _pantalla(m)));
  }

  Widget _pantalla(Modulo m) {
    final s = widget.sesion;
    return switch (m) {
      Modulo.inicio => InicioScreen(sesion: s, onIrA: _irA, onPerfil: _perfil),
      Modulo.misRutas => RutasScreen(choferData: s.datos),
      Modulo.monitoreo => MonitoreoScreen(permisos: s.permisos),
      Modulo.rutas => RutasModulo(permisos: s.permisos),
      Modulo.pedidos => PedidosModulo(permisos: s.permisos),
      Modulo.inventario => InventarioModulo(permisos: s.permisos),
      Modulo.retazos => PiezasModulo(permisos: s.permisos),
      Modulo.bodega => BodegaModulo(permisos: s.permisos),
      Modulo.usuarios => UsuariosModulo(permisos: s.permisos),
    };
  }

  Future<void> _cerrarSesion() async {
    final ok = await confirmar(
      context,
      titulo: 'Cerrar sesión',
      mensaje: '¿Quieres salir de tu cuenta en este dispositivo?',
      accion: 'Cerrar sesión',
      peligro: true,
    );
    if (!ok) return;
    await Sesion.cerrar();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _perfil() {
    final s = widget.sesion;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: _PerfilContenido(
            sesion: s,
            onCerrarSesion: () {
              Navigator.pop(ctx);
              _cerrarSesion();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _indice == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _seleccionar(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _indice,
          children: [
            for (var i = 0; i < _totalPestanas; i++)
              !_visitadas.contains(i)
                  ? const SizedBox.shrink()
                  : i < _principales.length
                  ? _pantalla(_principales[i])
                  : _MasScreen(
                      modulos: _extra,
                      sesion: widget.sesion,
                      onAbrir: _abrirModulo,
                      onCerrarSesion: _cerrarSesion,
                    ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _indice,
          onDestinationSelected: _seleccionar,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final m in _principales)
              NavigationDestination(
                icon: Icon(m.icono),
                selectedIcon: Icon(m.iconoActivo),
                label: m.etiqueta,
              ),
            if (_conMas)
              const NavigationDestination(
                icon: Icon(Icons.apps_outlined),
                selectedIcon: Icon(Icons.apps),
                label: 'Más',
              ),
          ],
        ),
      ),
    );
  }
}

class _MasScreen extends StatelessWidget {
  const _MasScreen({
    required this.modulos,
    required this.sesion,
    required this.onAbrir,
    required this.onCerrarSesion,
  });
  final List<Modulo> modulos;
  final Sesion sesion;
  final ValueChanged<Modulo> onAbrir;
  final VoidCallback onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const SeccionTitulo('Módulos'),
          Card(
            child: Column(
              children: [
                for (final m in modulos)
                  ListTile(
                    leading: Icon(m.iconoActivo, color: AppColors.primaryLight),
                    title: Text(m.etiqueta, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onAbrir(m),
                  ),
              ],
            ),
          ),
          const SeccionTitulo('Cuenta'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _PerfilContenido(sesion: sesion, onCerrarSesion: onCerrarSesion),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerfilContenido extends StatelessWidget {
  const _PerfilContenido({required this.sesion, required this.onCerrarSesion});
  final Sesion sesion;
  final VoidCallback onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    final u = sesion.usuario;
    final servidor = Uri.tryParse(ApiService.baseUrl)?.authority ?? ApiService.baseUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AvatarIniciales(u.fullName, radio: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(u.identification, style: const TextStyle(color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in u.roles)
              EstadoChip(r, texto: humanizar(r), color: AppColors.primaryLight),
          ],
        ),
        const SizedBox(height: 8),
        DatoFila('Correo', u.email, icono: Icons.mail_outline),
        DatoFila('Servidor', servidor, icono: Icons.dns_outlined),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => cambiarMiClave(context, alTerminar: () async {
            await Sesion.cerrar();
            if (!context.mounted) return;
            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
            );
          }),
          icon: const Icon(Icons.key_outlined),
          label: const Text('Cambiar mi contraseña'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onCerrarSesion,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
