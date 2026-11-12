import 'package:flutter/material.dart';

import '../../services/api_negocio.dart';
import '../../shared/adaptable.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';
import 'crear_ruta.dart';
import 'ruta_detalle.dart';

/// Rutas de reparto. Los pedidos con entrega llegan solos a "Por asignar";
/// desde ahí se arma la ruta con un chofer disponible.
class RutasModulo extends StatefulWidget {
  const RutasModulo({super.key, required this.permisos});
  final Permisos permisos;

  @override
  State<RutasModulo> createState() => _RutasModuloState();
}

class _RutasModuloState extends State<RutasModulo> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _bandeja = [];
  List<Map<String, dynamic>> _rutas = [];
  final Set<String> _sel = {};
  String _q = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _rutas.isEmpty && _bandeja.isEmpty;
      _error = null;
    });
    try {
      final r = await Future.wait([Api.entregasPendientes(), Api.rutas()]);
      if (!mounted) return;
      setState(() {
        _bandeja = r[0];
        _rutas = r[1]..sort((a, b) => aTexto(b['fechaCreacion']).compareTo(aTexto(a['fechaCreacion'])));
        _sel.removeWhere((id) => !_bandeja.any((p) => '${p['id']}' == id && listoParaRuta(p)));
      });
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> _de(Set<String> estados) {
    final q = _q.toLowerCase();
    return _rutas.where((r) {
      if (!estados.contains(r['estado'])) return false;
      if (q.isEmpty) return true;
      final paradas = (r['paradas'] as List? ?? const []);
      return '${r['codigoRuta']} ${r['choferNombre'] ?? ''} ${r['comentarios'] ?? ''}'.toLowerCase().contains(q) ||
          paradas.any((p) => '${p['pedido']?['cliente'] ?? ''} ${p['numeroPedido'] ?? ''}'.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _abrir(Map<String, dynamic> r) async {
    await abrirPanel(context, (_) => RutaDetalle(rutaId: '${r['id']}', permisos: widget.permisos), ancho: 680);
    _cargar();
  }

  Future<void> _crearRuta({List<Map<String, dynamic>> pedidos = const []}) async {
    final ruta = await abrirPanel<Map<String, dynamic>>(context, (_) => CrearRuta(pedidos: pedidos));
    if (ruta == null) return;
    _sel.clear();
    await _cargar();
    if (mounted) _abrir(ruta);
  }

  Future<void> _agregarARuta() async {
    final pendientes = _de({'PENDIENTE'});
    final pedidos = _bandeja.where((p) => _sel.contains('${p['id']}')).toList();
    final ruta = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Agregar a una ruta pendiente', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            if (pendientes.isEmpty) const ListTile(title: Text('No hay rutas pendientes. Crea una nueva.')),
            for (final r in pendientes)
              ListTile(
                leading: const Icon(Icons.alt_route),
                title: Text(tituloRuta(r)),
                subtitle: Text('${r['choferNombre'] ?? 'Sin chofer'} · ${(r['paradas'] as List).length} paradas'),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (ruta == null || !mounted) return;
    final items = await completarUbicaciones(context, pedidos);
    if (items == null) return;
    try {
      await Api.agregarPedidosRuta('${ruta['id']}', items);
      if (!mounted) return;
      avisoOk(context, '${pedidos.length} pedido(s) agregados a ${tituloRuta(ruta)}');
      _sel.clear();
      await _cargar();
    } catch (e) {
      if (mounted) avisoError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = _de({'PENDIENTE'});
    final enCurso = _de({'EN_CURSO'});
    final cerradas = _de({'COMPLETADA', 'CANCELADA'});
    final listos = _bandeja.where(listoParaRuta).length;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rutas y entregas'),
          actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargar, icon: const Icon(Icons.refresh))],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              _tab('Por asignar', listos, AppColors.success),
              _tab('Pendientes', pendientes.length, AppColors.info),
              _tab('En curso', enCurso.length, AppColors.warning),
              _tab('Finalizadas', cerradas.length, AppColors.neutral),
            ],
          ),
        ),
        floatingActionButton: _sel.isEmpty
            ? FloatingActionButton.extended(
                heroTag: 'nueva-ruta',
                onPressed: () => _crearRuta(),
                icon: const Icon(Icons.add_road),
                label: const Text('Nueva ruta'),
              )
            : null,
        bottomNavigationBar: _sel.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _agregarARuta,
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Agregar a ruta'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _crearRuta(pedidos: _bandeja.where((p) => _sel.contains('${p['id']}')).toList()),
                          icon: const Icon(Icons.add_road),
                          label: Text('Crear ruta (${_sel.length})'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        body: _cargando
            ? const CargandoLista()
            : _error != null
            ? VistaError(mensaje: _error!, onReintentar: _cargar)
            : TabBarView(
                children: [
                  _bandejaVista(),
                  _listaRutas(pendientes, 'Sin rutas pendientes', 'Crea una ruta desde "Por asignar".'),
                  _listaRutas(enCurso, 'Ninguna ruta en curso', null),
                  _listaRutas(cerradas, 'Sin rutas finalizadas', null),
                ],
              ),
      ),
    );
  }

  Tab _tab(String texto, int n, Color c) => Tab(
    child: Row(
      children: [
        Text(texto),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
          child: Text('$n', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );

  Widget _bandejaVista() {
    return RefreshIndicator(
      onRefresh: _cargar,
      child: _bandeja.isEmpty
          ? const VistaVacia(
              icono: Icons.inbox_outlined,
              titulo: 'Sin entregas pendientes',
              mensaje: 'Los pedidos a domicilio aparecen aquí apenas se registran.',
            )
          : AnchoLegible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  const Text(
                    'Selecciona los pedidos listos y crea la ruta. Los que siguen en preparación se habilitan cuando bodega los prepara.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  for (final p in _bandeja) ...[
                    EntregaCard(
                      pedido: p,
                      seleccionado: _sel.contains('${p['id']}'),
                      onSeleccion: listoParaRuta(p)
                          ? (v) => setState(() => v ? _sel.add('${p['id']}') : _sel.remove('${p['id']}'))
                          : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _listaRutas(List<Map<String, dynamic>> rutas, String vacio, String? ayuda) {
    return RefreshIndicator(
      onRefresh: _cargar,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: CampoBusqueda(hint: 'Ruta, chofer, cliente o n.º de pedido', onChanged: (v) => setState(() => _q = v)),
          ),
          Expanded(
            child: rutas.isEmpty
                ? VistaVacia(icono: Icons.alt_route, titulo: vacio, mensaje: ayuda)
                : AnchoLegible(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: rutas.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => TarjetaRuta(ruta: rutas[i], onTap: () => _abrir(rutas[i])),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

String tituloRuta(Map<String, dynamic> r) =>
    aTexto(r['comentarios']).isNotEmpty && !aTexto(r['comentarios']).startsWith('Cancelada')
        ? '${r['codigoRuta']} · ${r['comentarios']}'
        : '${r['codigoRuta']}';

/// Listo para ruta: tiene material preparado en bodega y su estado permite despacharlo.
bool listoParaRuta(Map<String, dynamic> p) =>
    aNum(p['ready_quantity']) > 0 && {'PARCIAL', 'LISTO', 'EN_REPARTO'}.contains(p['state']);

class EntregaCard extends StatelessWidget {
  const EntregaCard({super.key, required this.pedido, required this.seleccionado, this.onSeleccion});
  final Map<String, dynamic> pedido;
  final bool seleccionado;
  final ValueChanged<bool>? onSeleccion;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final listo = onSeleccion != null;
    final sinUbicacion = p['delivery_latitude'] == null;
    final (String texto, Color color) = listo
        ? ('Listo para ruta', AppColors.success)
        : switch (p['state']) {
            'PENDIENTE_MATERIAL' => ('Falta material', AppColors.danger),
            'RETRASADO' => ('Retrasado', AppColors.danger),
            _ when aNum(p['pending_preparation']) > 0 => ('En preparación (bodega)', AppColors.info),
            _ => ('En reparto', AppColors.warning),
          };
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: seleccionado ? AppColors.primaryLight : Colors.transparent, width: 1.6),
      ),
      child: InkWell(
        onTap: listo ? () => onSeleccion!(!seleccionado) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 14, 10),
          child: Row(
            children: [
              Checkbox(value: seleccionado, onChanged: listo ? (v) => onSeleccion!(v == true) : null),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#${p['number']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(aTexto(p['client_name']), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(aTexto(p['delivery_address'], 'Sin dirección'),
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        EstadoChip('', texto: texto, color: color),
                        if (sinUbicacion) const EstadoChip('', texto: 'Sin ubicación en mapa', color: AppColors.warning),
                        if (p['expires_at'] != null)
                          Text('Vence ${fmtFecha(aFecha(p['expires_at']))}', style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TarjetaRuta extends StatelessWidget {
  const TarjetaRuta({super.key, required this.ruta, required this.onTap});
  final Map<String, dynamic> ruta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = ruta;
    final paradas = (r['paradas'] as List? ?? const []);
    final entregadas = paradas.where((p) => p['estado'] == 'ENTREGADO').length;
    final avance = paradas.isEmpty ? 0.0 : entregadas / paradas.length;
    final estado = aTexto(r['estado']);
    final chofer = r['choferNombre'] as String?;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(tituloRuta(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  EstadoChip(estado),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(chofer == null ? Icons.person_off_outlined : Icons.person_outline, size: 16,
                      color: chofer == null ? AppColors.warning : AppColors.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(chofer ?? 'Sin chofer', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: chofer == null ? AppColors.warning : AppColors.textMuted, fontSize: 13)),
                  ),
                  const Icon(Icons.pin_drop_outlined, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text('$entregadas/${paradas.length} entregadas', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: avance, minHeight: 6, color: colorEstado(estado), backgroundColor: AppColors.border),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
