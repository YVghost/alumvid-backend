import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_negocio.dart';
import '../../shared/mapa_selector.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';

const _cerrados = {'ENTREGADO', 'CANCELADO', 'VENCIDO'};

/// Ficha del pedido con sus acciones según estado y rol.
class PedidoDetalle extends StatefulWidget {
  const PedidoDetalle({super.key, required this.pedidoId, required this.permisos});
  final String pedidoId;
  final Permisos permisos;

  @override
  State<PedidoDetalle> createState() => _PedidoDetalleState();
}

class _PedidoDetalleState extends State<PedidoDetalle> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _ocupado = false;

  Permisos get p => widget.permisos;
  Map<String, dynamic> get _o => Map<String, dynamic>.from(_d!['order'] as Map);
  List<Map<String, dynamic>> _lista(String k) =>
      ((_d![k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final d = await Api.pedido(widget.pedidoId);
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    }
  }

  Future<void> _ejecutar(Future<void> Function() accion, String ok) async {
    setState(() => _ocupado = true);
    try {
      await accion();
      if (mounted) avisoOk(context, ok);
      await _cargar();
    } catch (e) {
      if (mounted) avisoError(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ------------------------------------------------------------------ cálculos

  /// Por línea: pedido, preparado, entregado y lo que sigue en bodega listo para salir.
  Map<String, double> _listoPorLinea() {
    final r = <String, double>{};
    for (final f in _lista('fulfillments')) {
      final libre = aNum(f['quantity']) - aNum(f['delivered_quantity']) - aNum(f['returned_quantity']) - aNum(f['dispatched_quantity']);
      r['${f['line_id']}'] = (r['${f['line_id']}'] ?? 0) + libre;
    }
    return r;
  }

  double get _porPreparar => _lista('lines').fold(0.0, (s, l) => s + aNum(l['quantity']) - aNum(l['prepared_quantity']));
  double get _listoEnBodega => _listoPorLinea().values.fold(0.0, (s, v) => s + (v > 0 ? v : 0));

  // ------------------------------------------------------------------ acciones

  Future<void> _preparar({bool parcial = false}) async {
    List<Map<String, dynamic>>? lineas;
    if (parcial) {
      final pendientes = {
        for (final l in _lista('lines'))
          if (aNum(l['quantity']) - aNum(l['prepared_quantity']) > 0) l: aNum(l['quantity']) - aNum(l['prepared_quantity']),
      };
      lineas = await _elegirCantidades('Preparar parcialmente', pendientes, 'Cantidad a preparar');
      if (lineas == null) return;
    } else if (!await confirmar(context,
        titulo: 'Preparar pedido completo',
        mensaje: 'Se separa el material reservado (y se cortan las medidas) y se descuenta del inventario automáticamente.',
        accion: 'Preparar')) {
      return;
    }
    await _ejecutar(
      () => Api.accionPedido(widget.pedidoId, 'prepare', motivo: 'Preparado en bodega', lineas: lineas),
      'Material preparado',
    );
  }

  Future<void> _entregarEnLocal() async {
    final listos = _listoPorLinea();
    final disponibles = {
      for (final l in _lista('lines'))
        if ((listos['${l['id']}'] ?? 0) > 0) l: listos['${l['id']}']!,
    };
    if (disponibles.isEmpty) return;
    final recibe = TextEditingController(text: aTexto(_o['receiver_name']));
    final lineas = await _elegirCantidades('Entregar en local', disponibles, 'Cantidad que retira', extra: TextField(
      controller: recibe,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Quién retira'),
    ));
    if (lineas == null) return;
    await _ejecutar(
      () => Api.accionPedido(widget.pedidoId, 'deliver', motivo: 'Retiro en local', lineas: lineas,
          recibe: recibe.text.trim().isEmpty ? null : recibe.text.trim()),
      'Entrega registrada',
    );
  }

  Future<void> _conMotivo(String accion, String titulo, String etiqueta, String ok, {bool peligro = false}) async {
    final motivo = await pedirTexto(context, titulo: titulo, etiqueta: etiqueta, accion: titulo, peligro: peligro);
    if (motivo == null) return;
    await _ejecutar(() => Api.accionPedido(widget.pedidoId, accion, motivo: motivo), ok);
  }

  Future<void> _recibirEnvio(Map<String, dynamic> envio) async {
    if (!await confirmar(context,
        titulo: 'Recibir devolución',
        mensaje: 'Confirma que el material del reparto volvió físicamente a bodega.',
        accion: 'Recibido')) {
      return;
    }
    await _ejecutar(() => Api.recibirDevolucion('${envio['id']}', 'Material recibido en bodega'), 'Devolución registrada');
  }

  /// Hoja para elegir cantidades por línea (valores iniciales: el máximo).
  Future<List<Map<String, dynamic>>?> _elegirCantidades(
      String titulo, Map<Map<String, dynamic>, double> maximos, String etiqueta, {Widget? extra}) {
    final ctrls = {for (final e in maximos.entries) e.key: TextEditingController(text: fmtNum(e.value))};
    return showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              for (final e in maximos.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: ctrls[e.key],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '${e.key['product_name']} ${medidas(e.key['length_m'], e.key['width_cm'], e.key['height_cm'])}',
                      helperText: '$etiqueta (máximo ${fmtNum(e.value)})',
                    ),
                  ),
                ),
              ?extra,
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final r = <Map<String, dynamic>>[];
                  for (final e in maximos.entries) {
                    final v = double.tryParse(ctrls[e.key]!.text.replaceAll(',', '.')) ?? 0;
                    if (v > e.value + 1e-9) {
                      avisoError(ctx, 'La cantidad de ${e.key['product_name']} supera el máximo');
                      return;
                    }
                    if (v > 0) r.add({'lineId': e.key['id'], 'quantity': v});
                  }
                  if (r.isEmpty) {
                    avisoError(ctx, 'Indica al menos una cantidad');
                    return;
                  }
                  Navigator.pop(ctx, r);
                },
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    if (_d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: _error != null ? VistaError(mensaje: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator()),
      );
    }
    final o = _o;
    final estado = aTexto(o['state']);
    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${o['number']}'),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargar, icon: const Icon(Icons.refresh))],
        bottom: _ocupado
            ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3))
            : null,
      ),
      bottomNavigationBar: _acciones(estado),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _cabecera(o, estado),
            const SizedBox(height: 12),
            _siguientePaso(o, estado),
            const SeccionTitulo('Productos'),
            ..._lineas(),
            ..._materialAsignado(),
            ..._envios(),
            const SeccionTitulo('Historial'),
            _historial(),
          ],
        ),
      ),
    );
  }

  Widget _cabecera(Map<String, dynamic> o, String estado) {
    final entrega = o['delivery_mode'] == 'ENTREGA';
    final lat = aNumONulo(o['delivery_latitude']), lon = aNumONulo(o['delivery_longitude']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(aTexto(o['client_name'], 'Cliente'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                EstadoChip(estado),
              ],
            ),
            const SizedBox(height: 10),
            DatoFila('Total', fmtDinero(aNum(o['total'])), icono: Icons.payments_outlined),
            DatoFila('Modalidad', entrega ? 'Entrega a domicilio' : 'Retiro en local',
                icono: entrega ? Icons.local_shipping_outlined : Icons.storefront_outlined),
            if (entrega) DatoFila('Dirección', aTexto(o['delivery_address']), icono: Icons.place_outlined),
            DatoFila('Recibe', aTexto(o['receiver_name']), icono: Icons.person_outline),
            if (aTexto(o['external_invoice_reference']).isNotEmpty)
              DatoFila('Factura', aTexto(o['external_invoice_reference']), icono: Icons.description_outlined),
            DatoFila('Creado', fmtFecha(aFecha(o['created_at'])), icono: Icons.event_outlined),
            if (!_cerrados.contains(estado) && o['expires_at'] != null)
              DatoFila('Reserva vence', fmtFecha(aFecha(o['expires_at'])), icono: Icons.timer_outlined),
            if (aTexto(o['notes']).isNotEmpty) DatoFila('Notas', aTexto(o['notes']), icono: Icons.notes),
            if (entrega && lat != null && lon != null) ...[
              const SizedBox(height: 10),
              MiniMapa(punto: LatLng(lat, lon), alto: 150),
            ],
          ],
        ),
      ),
    );
  }

  /// Explica qué falta y quién debe hacerlo (reduce dudas de uso).
  Widget _siguientePaso(Map<String, dynamic> o, String estado) {
    final entrega = o['delivery_mode'] == 'ENTREGA';
    final (IconData icono, Color color, String texto) = switch (estado) {
      'PENDIENTE_MATERIAL' => (Icons.inventory_outlined, AppColors.danger,
          'Falta material. Cuando ingrese stock, vende puede "Reintentar reserva".'),
      'RESERVADO' => (Icons.handyman_outlined, AppColors.info, 'Material reservado. Bodega debe prepararlo.'),
      'PARCIAL' when _porPreparar > 0 => (Icons.handyman_outlined, AppColors.violet,
          'Parte del pedido está lista. Bodega puede preparar lo pendiente.'),
      'LISTO' || 'PARCIAL' => entrega
          ? (Icons.alt_route, AppColors.success, 'Listo para despacho: aparece en Rutas → "Por asignar".')
          : (Icons.storefront_outlined, AppColors.success, 'Listo para retirar en local. Bodega registra la entrega.'),
      'EN_REPARTO' => (Icons.local_shipping, AppColors.warning, 'En reparto: el chofer confirma la entrega con foto y firma.'),
      'RETRASADO' => (Icons.schedule, AppColors.danger, 'Pedido retrasado. Reanúdalo cuando se pueda continuar.'),
      'ENTREGADO' => (Icons.verified, AppColors.success, 'Pedido entregado por completo.'),
      'CANCELADO' || 'VENCIDO' => (Icons.assignment_return_outlined, AppColors.neutral,
          'Pedido cerrado. Si hay material fuera de bodega, se recibe con "Recibir devolución".'),
      _ => (Icons.info_outline, AppColors.textMuted, 'Revisa el estado del pedido.'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }

  List<Widget> _lineas() {
    return [
      for (final l in _lista('lines'))
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l['product_name']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(fmtDinero(aNum(l['unit_price']) * aNum(l['quantity'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                Text(
                  [
                    '${fmtNum(aNum(l['quantity']))} × ${fmtDinero(aNum(l['unit_price']))}',
                    if (medidas(l['length_m'], l['width_cm'], l['height_cm']).isNotEmpty)
                      'medida ${medidas(l['length_m'], l['width_cm'], l['height_cm'])}',
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 10),
                _Avance(
                  pedido: aNum(l['quantity']),
                  reservado: aNum(l['reserved_quantity']),
                  preparado: aNum(l['prepared_quantity']),
                  entregado: aNum(l['delivered_quantity']),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// Qué pieza o cantidad tomar y de dónde (guía para bodega).
  List<Widget> _materialAsignado() {
    final asignado = _lista('allocations').where((a) => a['state'] == 'ACTIVA').toList();
    if (asignado.isEmpty || !p.bodega) return [];
    final nombres = {for (final l in _lista('lines')) '${l['id']}': '${l['product_name']}'};
    return [
      const SeccionTitulo('Material reservado para preparar'),
      Card(
        child: Column(
          children: [
            for (final a in asignado)
              ListTile(
                leading: Icon(a['piece_id'] != null ? Icons.content_cut : Icons.inventory_2_outlined),
                title: Text(nombres['${a['line_id']}'] ?? 'Material'),
                subtitle: Text(
                  a['piece_id'] != null
                      ? 'Cortar ${fmtNum(aNum(a['used_extent']))} de una pieza en ${aTexto(a['location'], 'sin ubicación')}'
                      : '${fmtNum(aNum(a['quantity']))} unidades',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _envios() {
    final envios = _lista('shipments');
    if (envios.isEmpty) return [];
    return [
      const SeccionTitulo('Despachos a domicilio'),
      Card(
        child: Column(
          children: [
            for (final e in envios)
              ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(switch (e['state']) {
                  'EN_REPARTO' => 'En ruta con el chofer',
                  'ENTREGADO' => 'Entregado',
                  'RETORNO_PENDIENTE' => 'No entregado: debe volver a bodega',
                  'DEVUELTO_BODEGA' => 'Devuelto a bodega',
                  _ => humanizar(aTexto(e['state'])),
                }),
                subtitle: Text(fmtFecha(aFecha(e['delivered_at'] ?? e['returned_at'] ?? e['created_at'])),
                    style: const TextStyle(color: AppColors.textMuted)),
                trailing: e['state'] == 'RETORNO_PENDIENTE' && p.bodega
                    ? FilledButton.tonal(onPressed: _ocupado ? null : () => _recibirEnvio(e), child: const Text('Recibir'))
                    : EstadoChip(aTexto(e['state'])),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _historial() {
    final eventos = _lista('events').reversed.toList();
    return Card(
      child: Column(
        children: [
          for (final e in eventos)
            ListTile(
              dense: true,
              leading: const Icon(Icons.history, size: 20),
              title: Text(humanizar(aTexto(e['action']))),
              subtitle: Text('${aTexto(e['reason'])}\n${aTexto(e['actor_name'])} · ${fmtFecha(aFecha(e['created_at']))}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              isThreeLine: true,
            ),
        ],
      ),
    );
  }

  Widget? _acciones(String estado) {
    final o = _o;
    final entrega = o['delivery_mode'] == 'ENTREGA';
    final principales = <Widget>[];
    final menu = <PopupMenuEntry<VoidCallback>>[];

    if (p.bodega && {'RESERVADO', 'PARCIAL', 'LISTO', 'EN_REPARTO'}.contains(estado) && _porPreparar > 0) {
      principales.add(FilledButton.icon(
        onPressed: _ocupado ? null : () => _preparar(),
        icon: const Icon(Icons.handyman),
        label: const Text('Preparar'),
      ));
      menu.add(PopupMenuItem(value: () => _preparar(parcial: true), child: const Text('Preparar parcialmente')));
    }
    if (p.bodega && !entrega && {'PARCIAL', 'LISTO'}.contains(estado) && _listoEnBodega > 0) {
      principales.add(FilledButton.icon(
        onPressed: _ocupado ? null : _entregarEnLocal,
        icon: const Icon(Icons.how_to_reg),
        label: const Text('Entregar en local'),
      ));
    }
    if (p.vende && estado == 'PENDIENTE_MATERIAL') {
      principales.add(FilledButton.icon(
        onPressed: _ocupado ? null : () => _ejecutar(() => Api.accionPedido(widget.pedidoId, 'retry', motivo: 'Reintento de reserva'), 'Reserva actualizada'),
        icon: const Icon(Icons.refresh),
        label: const Text('Reintentar reserva'),
      ));
    }
    if (p.gestionaPedidos && estado == 'RETRASADO') {
      principales.add(FilledButton.icon(
        onPressed: _ocupado ? null : () => _ejecutar(() => Api.accionPedido(widget.pedidoId, 'resume', motivo: 'Se reanuda el pedido'), 'Pedido reanudado'),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Reanudar'),
      ));
    }
    if (p.gestionaPedidos && {'PENDIENTE_MATERIAL', 'RESERVADO', 'PARCIAL', 'LISTO', 'EN_REPARTO'}.contains(estado)) {
      menu.add(PopupMenuItem(
          value: () => _conMotivo('delay', 'Retrasar', 'Motivo del retraso', 'Pedido marcado como retrasado'),
          child: const Text('Marcar como retrasado')));
    }
    if (p.bodega && {'CANCELADO', 'VENCIDO'}.contains(estado) && _listoEnBodega > 0) {
      menu.add(PopupMenuItem(
          value: () => _conMotivo('receive-return', 'Devolver a inventario', 'Observación', 'Material devuelto al inventario'),
          child: const Text('Devolver material preparado al inventario')));
    }
    if (p.vende && {'BORRADOR', 'PENDIENTE_MATERIAL', 'RESERVADO', 'PARCIAL', 'RETRASADO', 'LISTO', 'EN_REPARTO'}.contains(estado)) {
      menu.add(PopupMenuItem(
          value: () => _conMotivo('cancel', 'Cancelar pedido', 'Motivo de la cancelación', 'Pedido cancelado', peligro: true),
          child: const Text('Cancelar pedido', style: TextStyle(color: AppColors.danger))));
    }
    if (principales.isEmpty && menu.isEmpty) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Row(
          children: [
            for (final b in principales) ...[Expanded(child: b), const SizedBox(width: 8)],
            if (principales.isEmpty) const Spacer(),
            if (menu.isNotEmpty)
              PopupMenuButton<VoidCallback>(
                tooltip: 'Más acciones',
                enabled: !_ocupado,
                icon: const Icon(Icons.more_vert),
                onSelected: (f) => f(),
                itemBuilder: (_) => menu,
              ),
          ],
        ),
      ),
    );
  }
}

/// Barra de avance por línea: reservado, preparado, entregado.
class _Avance extends StatelessWidget {
  const _Avance({required this.pedido, required this.reservado, required this.preparado, required this.entregado});
  final double pedido, reservado, preparado, entregado;

  @override
  Widget build(BuildContext context) {
    double f(double v) => pedido <= 0 ? 0 : (v / pedido).clamp(0, 1);
    Widget barra(String etiqueta, double v, Color c) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(etiqueta, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: f(v), minHeight: 6, color: c, backgroundColor: AppColors.border),
            ),
          ),
          SizedBox(width: 56, child: Text(' ${fmtNum(v)}/${fmtNum(pedido)}', style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
    return Column(children: [
      barra('Reservado', (reservado > preparado ? reservado : preparado).clamp(0, pedido).toDouble(), AppColors.info),
      barra('Preparado', preparado, AppColors.violet),
      barra('Entregado', entregado, AppColors.success),
    ]);
  }
}
