import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_negocio.dart';
import '../../shared/mapa_selector.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';
import 'crear_ruta.dart';
import 'rutas_modulo.dart';

/// Detalle de una ruta: paradas con su carga y acciones según el estado.
class RutaDetalle extends StatefulWidget {
  const RutaDetalle({super.key, required this.rutaId, required this.permisos});
  final String rutaId;
  final Permisos permisos;

  @override
  State<RutaDetalle> createState() => _RutaDetalleState();
}

class _RutaDetalleState extends State<RutaDetalle> {
  Map<String, dynamic>? _r;
  String? _error;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await Api.ruta(widget.rutaId);
      if (mounted) {
        setState(() {
          _r = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    }
  }

  List<Map<String, dynamic>> get _paradas =>
      ((_r?['paradas'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  String get _estado => aTexto(_r?['estado']);
  bool get _pendiente => _estado == 'PENDIENTE';

  Future<void> _accion(Future<dynamic> Function() f, String ok) async {
    setState(() => _ocupado = true);
    try {
      await f();
      if (mounted) avisoOk(context, ok);
      await _cargar();
    } catch (e) {
      if (mounted) avisoError(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ------------------------------------------------------------------ acciones

  Future<void> _cambiarChofer() async {
    final c = await elegirChofer(context, actualId: _r?['choferId']?.toString());
    if (c == null) return;
    await _accion(() => Api.asignarChofer(widget.rutaId, '${c['id']}'), 'Chofer ${c['nombre']} asignado');
  }

  Future<void> _agregarPedidos() async {
    final enRuta = _paradas.map((p) => '${p['pedidoComercialId']}').toSet();
    final pedidos = await elegirPedidosListos(context, excluir: enRuta);
    if (pedidos == null || !mounted) return;
    final items = await completarUbicaciones(context, pedidos);
    if (items == null) return;
    await _accion(() => Api.agregarPedidosRuta(widget.rutaId, items), '${pedidos.length} pedido(s) agregados');
  }

  Future<void> _iniciar() async {
    if (!await confirmar(context, titulo: 'Iniciar ruta', mensaje: 'El chofer verá sus paradas y comenzará el recorrido.', accion: 'Iniciar')) return;
    await _accion(() => Api.iniciarRuta(widget.rutaId), 'Ruta iniciada');
  }

  Future<void> _cancelar() async {
    final motivo = await pedirTexto(context, titulo: 'Cancelar ruta', etiqueta: 'Motivo', accion: 'Cancelar ruta', peligro: true);
    if (motivo == null) return;
    await _accion(() => Api.cancelarRuta(widget.rutaId, motivo),
        _pendiente ? 'Ruta cancelada: el material vuelve a estar listo en bodega' : 'Ruta cancelada: lo no entregado debe volver a bodega');
  }

  Future<void> _eliminar() async {
    if (!await confirmar(context,
        titulo: 'Eliminar ruta', mensaje: 'Los pedidos vuelven a "Por asignar". Esta acción no se puede deshacer.', accion: 'Eliminar', peligro: true)) {
      return;
    }
    setState(() => _ocupado = true);
    try {
      await Api.eliminarRuta(widget.rutaId);
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

  Future<void> _quitar(Map<String, dynamic> p) async {
    if (!await confirmar(context,
        titulo: 'Quitar parada',
        mensaje: 'El pedido #${p['numeroPedido']} vuelve a "Por asignar" y su material queda listo en bodega.',
        accion: 'Quitar',
        peligro: true)) {
      return;
    }
    await _accion(() => Api.quitarParada(widget.rutaId, '${p['id']}'), 'Parada quitada');
  }

  Future<void> _modificarCarga(Map<String, dynamic> parada) async {
    Map<String, dynamic> pedido;
    try {
      pedido = await Api.pedido('${parada['pedidoComercialId']}');
    } catch (e) {
      if (mounted) avisoError(context, e);
      return;
    }
    if (!mounted) return;
    final lineas = (pedido['lines'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    // Máximo por línea = lo preparado que sigue en bodega + lo que ya lleva esta parada.
    final enBodega = <String, double>{};
    for (final f in (pedido['fulfillments'] as List)) {
      final libre = aNum(f['quantity']) - aNum(f['delivered_quantity']) - aNum(f['returned_quantity']) - aNum(f['dispatched_quantity']);
      enBodega['${f['line_id']}'] = (enBodega['${f['line_id']}'] ?? 0) + libre;
    }
    final enParada = <String, double>{};
    for (final c in (parada['carga'] as List? ?? const [])) {
      enParada['${c['line_id']}'] = (enParada['${c['line_id']}'] ?? 0) + aNum(c['quantity']);
    }
    final editables = lineas.where((l) => (enBodega['${l['id']}'] ?? 0) + (enParada['${l['id']}'] ?? 0) > 0).toList();
    final ctrls = {for (final l in editables) '${l['id']}': TextEditingController(text: fmtNum(enParada['${l['id']}'] ?? 0))};
    final nueva = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Modificar carga · pedido #${parada['numeroPedido']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const Text('Ajusta lo que lleva el chofer. Lo que no viaje queda listo en bodega.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 14),
              for (final l in editables)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: ctrls['${l['id']}'],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '${l['product_name']} ${medidas(l['length_m'], l['width_cm'], l['height_cm'])}',
                      helperText: 'Máximo ${fmtNum((enBodega['${l['id']}'] ?? 0) + (enParada['${l['id']}'] ?? 0))}',
                    ),
                  ),
                ),
              FilledButton(
                onPressed: () {
                  final r = <Map<String, dynamic>>[];
                  for (final l in editables) {
                    final id = '${l['id']}';
                    final v = double.tryParse(ctrls[id]!.text.replaceAll(',', '.')) ?? 0;
                    final max = (enBodega[id] ?? 0) + (enParada[id] ?? 0);
                    if (v > max + 1e-9) {
                      avisoError(ctx, '${l['product_name']}: máximo ${fmtNum(max)}');
                      return;
                    }
                    if (v > 0) r.add({'lineId': id, 'quantity': v});
                  }
                  if (r.isEmpty) {
                    avisoError(ctx, 'La carga no puede quedar vacía; usa "Quitar parada"');
                    return;
                  }
                  Navigator.pop(ctx, r);
                },
                child: const Text('Guardar carga'),
              ),
            ],
          ),
        ),
      ),
    );
    for (final c in ctrls.values) {
      c.dispose();
    }
    if (nueva == null) return;
    await _accion(() => Api.modificarCarga(widget.rutaId, '${parada['id']}', nueva), 'Carga actualizada');
  }

  void _verUbicacion(Map<String, dynamic> p) {
    final d = p['pedido'] as Map? ?? const {};
    final lat = aNumONulo(d['latitudDestino']), lon = aNumONulo(d['longitudDestino']);
    if (lat == null || lon == null) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(aTexto(d['cliente']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(aTexto(d['direccionTexto']), style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 12),
              MiniMapa(punto: LatLng(lat, lon), alto: 260),
            ],
          ),
        ),
      ),
    );
  }

  void _verEvidencia(Map<String, dynamic> p) {
    Widget imagen(String? url, {bool blanco = false}) {
      if (url == null || url.isEmpty) return const Card(child: ListTile(title: Text('No disponible')));
      Widget img;
      if (url.startsWith('data:')) {
        try {
          img = Image.memory(base64Decode(url.split(',').last), fit: BoxFit.contain);
        } catch (_) {
          img = const Text('Imagen no válida');
        }
      } else {
        img = Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('No se pudo cargar la imagen'));
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: blanco ? Colors.white : AppColors.card,
          constraints: const BoxConstraints(minHeight: 120, maxHeight: 320),
          alignment: Alignment.center,
          child: img,
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            const Text('Prueba de entrega', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(aTexto((p['pedido'] as Map?)?['cliente']), style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 10),
            DatoFila('Entregado', fmtFecha(aFecha(p['fechaEntrega']))),
            if (p['desviacionMetros'] != null) DatoFila('Distancia al destino', '${aNum(p['desviacionMetros']).round()} m'),
            if (aTexto(p['comentarios']).isNotEmpty) DatoFila('Comentarios', aTexto(p['comentarios'])),
            if (p['alertaDesviacion'] == true)
              const Padding(padding: EdgeInsets.only(top: 6), child: EstadoChip('', texto: 'Entregado lejos del destino', color: AppColors.danger)),
            const SeccionTitulo('Foto'),
            imagen(p['fotoPodUrl'] as String?),
            const SeccionTitulo('Firma'),
            imagen(p['firmaUrl'] as String?, blanco: true),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    if (_r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ruta')),
        body: _error != null ? VistaError(mensaje: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator()),
      );
    }
    final paradas = _paradas;
    return Scaffold(
      appBar: AppBar(
        title: Text(tituloRuta(_r!)),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _cargar, icon: const Icon(Icons.refresh)),
          if (_estado == 'PENDIENTE' || _estado == 'EN_CURSO')
            PopupMenuButton<String>(
              tooltip: 'Más acciones',
              onSelected: (v) => v == 'cancelar' ? _cancelar() : _eliminar(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'cancelar', child: ListTile(leading: Icon(Icons.block, color: AppColors.danger), title: Text('Cancelar ruta'))),
                if (_pendiente)
                  const PopupMenuItem(value: 'eliminar', child: ListTile(leading: Icon(Icons.delete_outline, color: AppColors.danger), title: Text('Eliminar ruta'))),
              ],
            ),
        ],
        bottom: _ocupado ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3)) : null,
      ),
      bottomNavigationBar: _barra(paradas),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _resumen(paradas),
            const SizedBox(height: 12),
            if (paradas.any((p) => (p['pedido'] as Map?)?['latitudDestino'] != null)) _mapa(paradas),
            SeccionTitulo('Paradas (${paradas.length})'),
            if (paradas.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Esta ruta no tiene paradas'),
                  subtitle: _pendiente ? const Text('Agrega pedidos listos desde la bandeja.') : null,
                ),
              ),
            for (final (i, p) in paradas.indexed) _parada(i + 1, p),
          ],
        ),
      ),
    );
  }

  Widget? _barra(List<Map<String, dynamic>> paradas) {
    if (_pendiente) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _ocupado ? null : _agregarPedidos,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Agregar pedidos'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _ocupado || paradas.isEmpty ? null : _iniciar,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Iniciar ruta'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_estado == 'EN_CURSO' && paradas.isNotEmpty && paradas.every((p) => {'ENTREGADO', 'CANCELADA'}.contains(p['estado']))) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _ocupado ? null : () => _accion(() => Api.completarRuta(widget.rutaId), 'Ruta completada'),
            icon: const Icon(Icons.flag),
            label: const Text('Finalizar ruta'),
          ),
        ),
      );
    }
    return null;
  }

  Widget _resumen(List<Map<String, dynamic>> paradas) {
    final r = _r!;
    final entregadas = paradas.where((p) => p['estado'] == 'ENTREGADO').length;
    final avance = paradas.isEmpty ? 0.0 : entregadas / paradas.length;
    final color = colorEstado(_estado);
    final chofer = r['choferNombre'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EstadoChip(_estado),
                const Spacer(),
                Text('${(avance * 100).round()}%', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: avance, minHeight: 8, color: color, backgroundColor: AppColors.border),
            ),
            const SizedBox(height: 6),
            Text('$entregadas de ${paradas.length} paradas entregadas', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const Divider(height: 24),
            Row(
              children: [
                AvatarIniciales(chofer ?? '?'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(chofer ?? 'Sin chofer', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(aTexto(r['choferTelefono'], 'Chofer'), style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
                if (aTexto(r['choferTelefono']).isNotEmpty)
                  IconButton.filledTonal(tooltip: 'Llamar', onPressed: () => llamar(aTexto(r['choferTelefono'])), icon: const Icon(Icons.call)),
                if (_pendiente) ...[
                  const SizedBox(width: 6),
                  TextButton.icon(onPressed: _ocupado ? null : _cambiarChofer, icon: const Icon(Icons.swap_horiz), label: const Text('Cambiar')),
                ],
              ],
            ),
            if (_estado == 'EN_CURSO')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('El chofer no se puede cambiar mientras la ruta está en curso.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            const Divider(height: 24),
            DatoFila('Código', aTexto(r['codigoRuta'])),
            DatoFila('Creada', fmtFecha(aFecha(r['fechaCreacion']))),
            if (r['fechaInicio'] != null) DatoFila('Iniciada', fmtFecha(aFecha(r['fechaInicio']))),
            if (r['fechaFin'] != null) DatoFila('Finalizada', fmtFecha(aFecha(r['fechaFin']))),
          ],
        ),
      ),
    );
  }

  Widget _mapa(List<Map<String, dynamic>> paradas) {
    final puntos = <(int, LatLng, String)>[];
    for (final (i, p) in paradas.indexed) {
      final d = p['pedido'] as Map? ?? const {};
      final lat = aNumONulo(d['latitudDestino']), lon = aNumONulo(d['longitudDestino']);
      if (lat != null && lon != null) puntos.add((i + 1, LatLng(lat, lon), aTexto(p['estado'])));
    }
    final coords = puntos.map((e) => e.$2).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: coords.length > 1 ? CameraFit.coordinates(coordinates: coords, padding: const EdgeInsets.all(40)) : null,
            initialCenter: coords.first,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.scrollWheelZoom),
          ),
          children: [
            TileLayer(urlTemplate: mapaTiles, userAgentPackageName: mapaAgente),
            if (coords.length > 1) PolylineLayer(polylines: [Polyline(points: coords, color: AppColors.primaryLight, strokeWidth: 3)]),
            MarkerLayer(markers: [
              for (final (n, punto, estado) in puntos)
                Marker(
                  point: punto,
                  width: 30,
                  height: 30,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorEstado(estado),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _parada(int n, Map<String, dynamic> p) {
    final estado = aTexto(p['estado']);
    final d = p['pedido'] as Map? ?? const {};
    final carga = (p['carga'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final color = colorEstado(estado);
    final editable = _pendiente && estado != 'CANCELADA' && p['pedidoComercialId'] != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: color.withValues(alpha: 0.2),
                  child: Text('$n', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [if (p['numeroPedido'] != null) '#${p['numeroPedido']}', aTexto(d['cliente'])].join(' · '),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(aTexto(d['direccionTexto']), style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
                EstadoChip(estado),
              ],
            ),
            if (carga.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Carga', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              for (final c in carga)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${c['product_name']} ${medidas(c['length_m'], c['width_cm'], c['height_cm'])}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text('× ${fmtNum(aNum(c['quantity']))}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
            if (estado == 'CANCELADA' && aTexto(p['comentarios']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(aTexto(p['comentarios']), style: const TextStyle(color: AppColors.warning, fontSize: 12)),
              ),
            Wrap(
              spacing: 4,
              children: [
                if (d['latitudDestino'] != null)
                  TextButton.icon(onPressed: () => _verUbicacion(p), icon: const Icon(Icons.place_outlined, size: 18), label: const Text('Ver ubicación')),
                if (editable)
                  TextButton.icon(
                    onPressed: _ocupado ? null : () => _modificarCarga(p),
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('Modificar carga'),
                  ),
                if (editable)
                  TextButton.icon(
                    onPressed: _ocupado ? null : () => _quitar(p),
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Quitar parada'),
                  ),
                if (estado == 'ENTREGADO')
                  TextButton.icon(
                    onPressed: () => _verEvidencia(p),
                    style: TextButton.styleFrom(foregroundColor: AppColors.success),
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Ver evidencia'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
