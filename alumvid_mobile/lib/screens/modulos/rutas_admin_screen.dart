import 'dart:convert';

import 'package:alumvid_admin_desktop/models/chofer.dart';
import 'package:alumvid_admin_desktop/models/despacho.dart';
import 'package:alumvid_admin_desktop/models/ruta.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

const tileUrl = 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
const tileAgent = 'com.alumvid.mobile';

/// Gestión de rutas y despachos (solo ADMINISTRADOR).
class RutasAdminScreen extends StatefulWidget {
  const RutasAdminScreen({super.key});

  @override
  State<RutasAdminScreen> createState() => _RutasAdminScreenState();
}

class _RutasAdminScreenState extends State<RutasAdminScreen> {
  static const _pestanas = [
    ('EN_CURSO', 'En curso'),
    ('PENDIENTE', 'Pendientes'),
    ('COMPLETADA', 'Completadas'),
    ('CANCELADA', 'Canceladas'),
  ];

  bool _cargando = true;
  String? _error;
  List<Ruta> _rutas = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = _rutas.isEmpty;
      _error = null;
    });
    try {
      final r = await adm.ApiService.obtenerRutas();
      r.sort((a, b) => (b.fechaCreacion ?? DateTime(0)).compareTo(a.fechaCreacion ?? DateTime(0)));
      if (mounted) setState(() => _rutas = r);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Ruta> _de(String estado) {
    final q = _q.toLowerCase();
    return _rutas.where((r) {
      final est = r.estado == 'CANCELADO' ? 'CANCELADA' : r.estado;
      if (est != estado) return false;
      if (q.isEmpty) return true;
      return r.codigoRuta.toLowerCase().contains(q) ||
          (r.choferNombre ?? '').toLowerCase().contains(q) ||
          r.paradas.any((p) => p.cliente.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _abrir(Ruta r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RutaDetalleScreen(rutaId: r.id, inicial: r)),
    );
    _cargar();
  }

  Future<void> _nueva() async {
    final creada = await showModalBottomSheet<Ruta>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NuevaRutaSheet(),
    );
    if (creada == null || !mounted) return;
    avisoOk(context, 'Ruta ${creada.codigoRuta} creada');
    await _cargar();
    if (mounted) _abrir(creada);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _pestanas.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rutas y despachos'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final (estado, etiqueta) in _pestanas)
                Tab(
                  child: Row(
                    children: [
                      Text(etiqueta),
                      if (!_cargando) ...[
                        const SizedBox(width: 6),
                        _Contador(_de(estado).length, colorEstado(estado)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _nueva,
          icon: const Icon(Icons.add_road),
          label: const Text('Ruta'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: CampoBusqueda(
                hint: 'Código, chofer o cliente',
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: _cargando
                  ? const CargandoLista()
                  : _error != null
                  ? VistaError(mensaje: _error!, onReintentar: _cargar)
                  : TabBarView(
                      children: [
                        for (final (estado, etiqueta) in _pestanas) _lista(estado, etiqueta),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lista(String estado, String etiqueta) {
    final rutas = _de(estado);
    return RefreshIndicator(
      onRefresh: _cargar,
      child: rutas.isEmpty
          ? VistaVacia(icono: Icons.alt_route, titulo: 'Sin rutas ${etiqueta.toLowerCase()}')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: rutas.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => RutaCard(ruta: rutas[i], onTap: () => _abrir(rutas[i])),
            ),
    );
  }
}

class _Contador extends StatelessWidget {
  const _Contador(this.n, this.color);
  final int n;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text('$n', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
  );
}

class RutaCard extends StatelessWidget {
  const RutaCard({super.key, required this.ruta, required this.onTap});
  final Ruta ruta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = ruta;
    final color = colorEstado(r.estado);
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
                    child: Text(
                      r.comentarios?.isNotEmpty == true ? r.comentarios! : r.codigoRuta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  EstadoChip(r.estado),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    r.choferNombre == null ? Icons.person_off_outlined : Icons.person_outline,
                    size: 16,
                    color: r.choferNombre == null ? AppColors.warning : AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      r.choferNombre ?? 'Sin chofer asignado',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: r.choferNombre == null ? AppColors.warning : AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(Icons.pin_drop_outlined, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    '${r.paradasEntregadas}/${r.totalParadas} paradas',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: r.porcentajeAvance,
                  minHeight: 6,
                  color: color,
                  backgroundColor: AppColors.border,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detalle de ruta
// ---------------------------------------------------------------------------

class RutaDetalleScreen extends StatefulWidget {
  const RutaDetalleScreen({super.key, required this.rutaId, this.inicial});
  final String rutaId;
  final Ruta? inicial;

  @override
  State<RutaDetalleScreen> createState() => _RutaDetalleScreenState();
}

class _RutaDetalleScreenState extends State<RutaDetalleScreen> {
  late Ruta? _r = widget.inicial;
  bool _ocupado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<void> _recargar() async {
    try {
      final r = await adm.ApiService.obtenerRutaPorId(widget.rutaId);
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    }
  }

  Future<void> _accion(Future<void> Function() f, String ok) async {
    setState(() => _ocupado = true);
    try {
      await f();
      if (mounted) avisoOk(context, ok);
      await _recargar();
    } catch (e) {
      if (mounted) avisoError(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _asignarChofer() async {
    final r = _r!;
    final elegido = await showModalBottomSheet<Chofer?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ElegirChoferSheet(actualId: r.choferId),
    );
    if (elegido == null) return;
    await _accion(
      () => adm.ApiService.asignarChoferRuta(r.id, elegido.id),
      'Chofer ${elegido.nombre} asignado',
    );
  }

  Future<void> _iniciar() async {
    final r = _r!;
    if (r.choferId == null) {
      avisoError(context, 'Asigna un chofer antes de iniciar la ruta.');
      return;
    }
    if (!await confirmar(
      context,
      titulo: 'Iniciar ruta',
      mensaje: 'La ruta pasará a "En curso" y el chofer verá sus paradas.',
      accion: 'Iniciar',
    )) {
      return;
    }
    await _accion(() => adm.ApiService.iniciarRuta(r.id), 'Ruta iniciada');
  }

  Future<void> _cancelar() async {
    final motivo = await pedirTexto(
      context,
      titulo: 'Cancelar ruta',
      etiqueta: 'Motivo de la cancelación',
      accion: 'Cancelar ruta',
      peligro: true,
    );
    if (motivo == null) return;
    await _accion(() => adm.ApiService.cancelarRuta(_r!.id, motivo), 'Ruta cancelada');
  }

  Future<void> _eliminarRuta() async {
    if (!await confirmar(
      context,
      titulo: 'Eliminar ruta',
      mensaje: 'Se eliminará la ruta y sus paradas. Esta acción no se puede deshacer.',
      accion: 'Eliminar',
      peligro: true,
    )) {
      return;
    }
    setState(() => _ocupado = true);
    try {
      await adm.ApiService.eliminarRuta(_r!.id);
      if (!mounted) return;
      avisoOk(context, 'Ruta eliminada');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _ocupado = false);
        avisoError(context, e);
      }
    }
  }

  Future<void> _quitarParada(Despacho p) async {
    if (!await confirmar(
      context,
      titulo: 'Quitar parada',
      mensaje: '¿Quitar la parada de ${p.cliente} de esta ruta?',
      accion: 'Quitar',
      peligro: true,
    )) {
      return;
    }
    await _accion(() => adm.ApiService.eliminarDestinoRuta(_r!.id, p.id), 'Parada eliminada');
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null
            ? VistaError(mensaje: _error!, onReintentar: _recargar)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final paradas = [...r.paradas]..sort((a, b) => a.ordenParada.compareTo(b.ordenParada));
    final puedeQuitar = r.isPendiente && paradas.length > 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.comentarios?.isNotEmpty == true ? r.comentarios! : 'Ruta'),
        actions: [
          if (!r.isEnCurso)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'eliminar') _eliminarRuta();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'eliminar',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: AppColors.danger),
                    title: Text('Eliminar ruta'),
                  ),
                ),
              ],
            ),
        ],
        bottom: _ocupado
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      bottomNavigationBar: (r.isPendiente || r.isEnCurso) ? _barraAcciones(r) : null,
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _resumen(r),
            const SizedBox(height: 12),
            if (paradas.isNotEmpty) _mapa(paradas),
            SeccionTitulo('Paradas (${paradas.length})'),
            if (paradas.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Esta ruta no tiene paradas'),
                  subtitle: Text('Agrégalas desde el administrador de escritorio.'),
                ),
              ),
            for (final (i, p) in paradas.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ParadaCard(
                  orden: i + 1,
                  parada: p,
                  onQuitar: puedeQuitar && !p.isEntregado ? () => _quitarParada(p) : null,
                  onEvidencia: p.isEntregado ? () => _evidencia(p) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _barraAcciones(Ruta r) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _ocupado ? null : _cancelar,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.block),
                label: const Text('Cancelar'),
              ),
            ),
            if (r.isPendiente) ...[
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _ocupado ? null : _iniciar,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Iniciar'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resumen(Ruta r) {
    final color = colorEstado(r.estado);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EstadoChip(r.estado),
                const Spacer(),
                Text(
                  '${(r.porcentajeAvance * 100).round()}%',
                  style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: r.porcentajeAvance,
                minHeight: 8,
                color: color,
                backgroundColor: AppColors.border,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${r.paradasEntregadas} de ${r.totalParadas} paradas entregadas',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const Divider(height: 24),
            Row(
              children: [
                AvatarIniciales(r.choferNombre ?? '?', radio: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.choferNombre ?? 'Sin chofer asignado',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: r.choferNombre == null ? AppColors.warning : AppColors.text,
                        ),
                      ),
                      Text(
                        r.choferTelefono ?? 'Chofer',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if ((r.choferTelefono ?? '').isNotEmpty)
                  IconButton.filledTonal(
                    tooltip: 'Llamar al chofer',
                    onPressed: () => llamar(r.choferTelefono!),
                    icon: const Icon(Icons.call),
                  ),
                if (r.isPendiente || r.isEnCurso) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Cambiar chofer',
                    onPressed: _ocupado ? null : _asignarChofer,
                    icon: const Icon(Icons.swap_horiz),
                  ),
                ],
              ],
            ),
            const Divider(height: 24),
            DatoFila('Código', r.codigoRuta),
            DatoFila('Creada', fmtFecha(r.fechaCreacion)),
            if (r.fechaInicio != null) DatoFila('Iniciada', fmtFecha(r.fechaInicio)),
            if (r.fechaFin != null) DatoFila('Finalizada', fmtFecha(r.fechaFin)),
          ],
        ),
      ),
    );
  }

  Widget _mapa(List<Despacho> paradas) {
    final puntos = [for (final p in paradas) LatLng(p.latitud, p.longitud)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 200,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: puntos.length > 1
                ? CameraFit.coordinates(coordinates: puntos, padding: const EdgeInsets.all(36))
                : null,
            initialCenter: puntos.first,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          ),
          children: [
            TileLayer(urlTemplate: tileUrl, userAgentPackageName: tileAgent),
            if (puntos.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(points: puntos, color: AppColors.primaryLight, strokeWidth: 3),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final (i, p) in paradas.indexed)
                  Marker(
                    point: puntos[i],
                    width: 30,
                    height: 30,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorEstado(p.estado),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _evidencia(Despacho p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            const Text('Prueba de entrega', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(p.cliente, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            DatoFila('Entregado', fmtFecha(p.fechaEntrega)),
            if (p.desviacionMetros != null)
              DatoFila('Desviación', '${p.desviacionMetros!.round()} m'),
            if ((p.comentarios ?? '').isNotEmpty) DatoFila('Comentarios', p.comentarios!),
            if (p.hasAlertaDesviacion)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: EstadoChip('RETRASADO', texto: 'Entregado lejos del destino'),
              ),
            const SeccionTitulo('Foto'),
            _imagen(p.fotoPodUrl),
            const SeccionTitulo('Firma'),
            _imagen(p.firmaUrl, fondoBlanco: true),
          ],
        ),
      ),
    );
  }

  Widget _imagen(String? url, {bool fondoBlanco = false}) {
    if (url == null || url.isEmpty) {
      return const Card(child: ListTile(title: Text('No disponible')));
    }
    Widget img;
    if (url.startsWith('data:')) {
      try {
        img = Image.memory(base64Decode(url.split(',').last), fit: BoxFit.contain);
      } catch (_) {
        img = const Text('Imagen no válida');
      }
    } else {
      img = Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No se pudo cargar la imagen'),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: fondoBlanco ? Colors.white : AppColors.card,
        constraints: const BoxConstraints(minHeight: 120, maxHeight: 320),
        alignment: Alignment.center,
        child: img,
      ),
    );
  }
}

class _ParadaCard extends StatelessWidget {
  const _ParadaCard({
    required this.orden,
    required this.parada,
    this.onQuitar,
    this.onEvidencia,
  });
  final int orden;
  final Despacho parada;
  final VoidCallback? onQuitar;
  final VoidCallback? onEvidencia;

  @override
  Widget build(BuildContext context) {
    final p = parada;
    final color = colorEstado(p.estado);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: color.withValues(alpha: 0.2),
              child: Text(
                '$orden',
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.cliente, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    p.direccionTexto,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      EstadoChip(p.estado),
                      if (p.hasAlertaDesviacion)
                        const EstadoChip('RETRASADO', texto: 'Desviación'),
                      if (p.fechaEntrega != null)
                        Text(
                          fmtFecha(p.fechaEntrega),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (onEvidencia != null)
              IconButton(
                tooltip: 'Ver prueba de entrega',
                onPressed: onEvidencia,
                icon: const Icon(Icons.verified_outlined, color: AppColors.success),
              ),
            if (onQuitar != null)
              IconButton(
                tooltip: 'Quitar parada',
                onPressed: onQuitar,
                icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ElegirChoferSheet extends StatefulWidget {
  const _ElegirChoferSheet({this.actualId});
  final String? actualId;

  @override
  State<_ElegirChoferSheet> createState() => _ElegirChoferSheetState();
}

class _ElegirChoferSheetState extends State<_ElegirChoferSheet> {
  late final Future<List<Chofer>> _f = adm.ApiService.obtenerChoferes();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: FutureBuilder<List<Chofer>>(
          future: _f,
          builder: (ctx, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(limpiarError(snap.error!)),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final choferes = snap.data!;
            return ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Asignar chofer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                if (choferes.isEmpty)
                  const ListTile(title: Text('No hay choferes registrados')),
                for (final c in choferes)
                  ListTile(
                    leading: AvatarIniciales(c.nombre),
                    title: Text(c.nombre),
                    subtitle: Text(humanizar(c.estadoDisponibilidad)),
                    trailing: c.id == widget.actualId
                        ? const Icon(Icons.check_circle, color: AppColors.success)
                        : EstadoChip(c.estadoDisponibilidad),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NuevaRutaSheet extends StatefulWidget {
  const _NuevaRutaSheet();

  @override
  State<_NuevaRutaSheet> createState() => _NuevaRutaSheetState();
}

class _NuevaRutaSheetState extends State<_NuevaRutaSheet> {
  final _codigo = TextEditingController(
    text: 'RUTA-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
  );
  final _comentarios = TextEditingController();
  late final Future<List<Chofer>> _choferes = adm.ApiService.obtenerChoferes();
  String? _choferId;
  bool _guardando = false;

  @override
  void dispose() {
    _codigo.dispose();
    _comentarios.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (_codigo.text.trim().isEmpty) return;
    setState(() => _guardando = true);
    try {
      final r = await adm.ApiService.crearRutaSimple(
        codigoRuta: _codigo.text.trim(),
        choferId: _choferId,
        comentarios: _comentarios.text.trim().isEmpty ? null : _comentarios.text.trim(),
      );
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        avisoError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Nueva ruta', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Las paradas con mapa se agregan desde el administrador de escritorio.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codigo,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Código de ruta'),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Chofer>>(
            future: _choferes,
            builder: (ctx, snap) => DropdownButtonFormField<String?>(
              initialValue: _choferId,
              decoration: InputDecoration(
                labelText: 'Chofer',
                helperText: snap.hasError ? 'No se pudieron cargar los choferes' : null,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin asignar')),
                for (final c in snap.data ?? const <Chofer>[])
                  DropdownMenuItem(value: c.id, child: Text(c.nombre)),
              ],
              onChanged: (v) => setState(() => _choferId = v),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comentarios,
            decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _guardando ? null : _crear,
            child: _guardando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Crear ruta'),
          ),
        ],
      ),
    );
  }
}
