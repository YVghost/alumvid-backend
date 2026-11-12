import 'package:alumvid_admin_desktop/models/pedido_comercial.dart';
import 'package:alumvid_admin_desktop/models/producto.dart';
import 'package:alumvid_admin_desktop/models/ruta.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:flutter/material.dart';

import '../../core/sesion.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Resumen del día adaptado a los roles del usuario.
class InicioScreen extends StatefulWidget {
  const InicioScreen({
    super.key,
    required this.sesion,
    required this.onIrA,
    required this.onPerfil,
  });
  final Sesion sesion;
  final ValueChanged<Modulo> onIrA;
  final VoidCallback onPerfil;

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  bool _cargando = true;
  final List<String> _errores = [];
  List<PedidoComercial> _pedidos = [];
  List<Producto> _stockBajo = [];
  List<Ruta> _rutas = [];
  int _rutasChofer = 0;

  Sesion get s => widget.sesion;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _errores.clear();
    });
    Future<void> tarea(String nombre, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        _errores.add('$nombre: ${limpiarError(e)}');
      }
    }

    await Future.wait([
      if (s.puede(Modulo.pedidos))
        tarea('Pedidos', () async {
          _pedidos = await adm.ApiService.obtenerPedidosComerciales(size: 100);
        }),
      if (s.puede(Modulo.inventario))
        tarea('Inventario', () async {
          final r = await adm.ApiService.obtenerProductos(lowStock: true, size: 50);
          _stockBajo = (r['items'] as List).cast<Producto>();
        }),
      if (s.puede(Modulo.rutas))
        tarea('Rutas', () async {
          _rutas = await adm.ApiService.obtenerRutas();
        }),
      if (s.puede(Modulo.misRutas))
        tarea('Mis rutas', () async {
          final v = await ApiService.obtenerRutasChofer(s.usuario.id);
          _rutasChofer = v
              .where((r) => r['estado'] != 'COMPLETADA' && r['estado'] != 'CANCELADA')
              .length;
        }),
    ]);
    if (mounted) setState(() => _cargando = false);
  }

  int _pedidosEn(Set<String> estados) =>
      _pedidos.where((p) => estados.contains(p.state)).length;

  String _saludo() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final nombre = s.usuario.fullName.split(' ').first;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _cabecera(nombre),
              if (_errores.isNotEmpty) ...[
                const SizedBox(height: 12),
                _avisoErrores(),
              ],
              if (_cargando)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                ..._kpis(),
                ..._listas(),
                SeccionTitulo('Accesos rápidos'),
                _accesos(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecera(String nombre) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_saludo()},',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
              ),
              Text(
                nombre,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in s.roles)
                    EstadoChip(r, color: AppColors.primaryLight, texto: humanizar(r)),
                ],
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: 'Perfil y sesión',
          child: InkWell(
            borderRadius: BorderRadius.circular(40),
            onTap: widget.onPerfil,
            child: AvatarIniciales(s.usuario.fullName, radio: 26),
          ),
        ),
      ],
    );
  }

  Widget _avisoErrores() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errores.join('\n'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _kpis() {
    final tarjetas = <Widget>[];
    if (s.puede(Modulo.misRutas)) {
      tarjetas.add(KpiCard(
        titulo: 'Mis rutas activas',
        valor: '$_rutasChofer',
        icono: Icons.local_shipping,
        color: AppColors.primaryLight,
        onTap: () => widget.onIrA(Modulo.misRutas),
      ));
    }
    if (s.puede(Modulo.rutas)) {
      tarjetas.add(KpiCard(
        titulo: 'Rutas en curso',
        valor: '${_rutas.where((r) => r.isEnCurso).length}',
        icono: Icons.alt_route,
        color: AppColors.warning,
        onTap: () => widget.onIrA(Modulo.rutas),
      ));
      tarjetas.add(KpiCard(
        titulo: 'Rutas pendientes',
        valor: '${_rutas.where((r) => r.isPendiente).length}',
        icono: Icons.pending_actions,
        color: AppColors.info,
        onTap: () => widget.onIrA(Modulo.rutas),
      ));
    }
    if (s.puede(Modulo.pedidos)) {
      if (s.tiene('BODEGUERO') || s.esAdmin) {
        tarjetas.add(KpiCard(
          titulo: 'Por preparar',
          valor: '${_pedidosEn({'RESERVADO', 'PARCIAL', 'PENDIENTE_MATERIAL'})}',
          icono: Icons.handyman,
          color: AppColors.violet,
          onTap: () => widget.onIrA(Modulo.pedidos),
        ));
      }
      tarjetas.add(KpiCard(
        titulo: 'Listos / en reparto',
        valor: '${_pedidosEn({'LISTO', 'EN_REPARTO'})}',
        icono: Icons.inventory,
        color: AppColors.success,
        onTap: () => widget.onIrA(Modulo.pedidos),
      ));
      tarjetas.add(KpiCard(
        titulo: 'Retrasados',
        valor: '${_pedidosEn({'RETRASADO'})}',
        icono: Icons.schedule,
        color: AppColors.danger,
        onTap: () => widget.onIrA(Modulo.pedidos),
      ));
    }
    if (s.puede(Modulo.inventario)) {
      tarjetas.add(KpiCard(
        titulo: 'Stock bajo o agotado',
        valor: '${_stockBajo.length}',
        icono: Icons.trending_down,
        color: AppColors.warning,
        onTap: () => widget.onIrA(Modulo.inventario),
      ));
    }
    if (tarjetas.isEmpty) return [];
    return [
      SeccionTitulo('Resumen'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
        children: tarjetas,
      ),
    ];
  }

  List<Widget> _listas() {
    final out = <Widget>[];
    final urgentes = _pedidos
        .where((p) => p.state == 'RETRASADO' || p.state == 'PENDIENTE_MATERIAL')
        .take(4)
        .toList();
    if (urgentes.isNotEmpty) {
      out.add(SeccionTitulo('Pedidos que requieren atención'));
      out.add(Card(
        child: Column(
          children: [
            for (final p in urgentes)
              ListTile(
                leading: const Icon(Icons.priority_high, color: AppColors.danger),
                title: Text('#${p.number} · ${p.clientName}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(p.isEntregaDomicilio ? 'Entrega a domicilio' : 'Retiro en local'),
                trailing: EstadoChip(p.state),
                onTap: () => widget.onIrA(Modulo.pedidos),
              ),
          ],
        ),
      ));
    }
    if (_stockBajo.isNotEmpty) {
      out.add(SeccionTitulo('Stock por reponer'));
      out.add(Card(
        child: Column(
          children: [
            for (final p in _stockBajo.take(4))
              ListTile(
                leading: Icon(
                  p.isAgotado ? Icons.remove_shopping_cart : Icons.trending_down,
                  color: p.isAgotado ? AppColors.danger : AppColors.warning,
                ),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('Mínimo ${fmtNum(p.minStock)} ${humanizar(p.unit).toLowerCase()}'),
                trailing: Text(
                  fmtNum(p.stock),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: p.isAgotado ? AppColors.danger : AppColors.warning,
                  ),
                ),
                onTap: () => widget.onIrA(Modulo.inventario),
              ),
          ],
        ),
      ));
    }
    return out;
  }

  Widget _accesos() {
    final mods = s.modulos.where((m) => m != Modulo.inicio).toList();
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        for (final m in mods)
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => widget.onIrA(m),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(m.iconoActivo, color: AppColors.primaryLight, size: 28),
                  const SizedBox(height: 8),
                  Text(m.etiqueta, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
