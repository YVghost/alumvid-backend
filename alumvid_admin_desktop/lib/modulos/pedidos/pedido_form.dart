import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_negocio.dart';
import '../../shared/adaptable.dart';
import '../../shared/mapa_selector.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';
import 'clientes.dart';

/// Línea en edición del pedido nuevo.
class _Linea {
  _Linea(this.producto);
  final Map<String, dynamic> producto;
  final cantidad = TextEditingController(text: '1');
  final precio = TextEditingController();
  final medida = TextEditingController(); // largo (m) para aluminio, ancho (cm) para vidrio
  Map<String, dynamic>? disponibilidad;

  bool get porPiezas => producto['piecesManaged'] == true;
  String get tipo => aTexto(producto['kind']);
  double? get altoVidrio => aNumONulo(producto['fullHeightCm']);
  double? get largoCompleto => aNumONulo(producto['fullLengthM']);
  double? get anchoCompleto => aNumONulo(producto['fullWidthCm']);

  void dispose() {
    cantidad.dispose();
    precio.dispose();
    medida.dispose();
  }

  Map<String, dynamic> json() {
    double n(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
    final m = medida.text.trim().isEmpty ? null : n(medida);
    return {
      'productId': producto['id'],
      'quantity': n(cantidad),
      'unitPrice': n(precio),
      if (porPiezas && tipo == 'ALUMINIO' && m != null) 'lengthM': m,
      if (porPiezas && tipo == 'VIDRIO' && m != null) ...{'widthCm': m, 'heightCm': altoVidrio},
    };
  }
}

/// Pedido nuevo: queda confirmado y el sistema reserva el material automáticamente.
class PedidoForm extends StatefulWidget {
  const PedidoForm({super.key});

  @override
  State<PedidoForm> createState() => _PedidoFormState();
}

class _PedidoFormState extends State<PedidoForm> {
  final _form = GlobalKey<FormState>();
  Map<String, dynamic>? _cliente;
  bool _entrega = false;
  final _direccion = TextEditingController();
  final _recibe = TextEditingController();
  final _factura = TextEditingController();
  final _notas = TextEditingController();
  LatLng? _punto;
  final List<_Linea> _lineas = [];
  bool _consultando = false;
  bool _guardando = false;
  String? _avisoDisponibilidad;

  @override
  void dispose() {
    for (final c in [_direccion, _recibe, _factura, _notas]) {
      c.dispose();
    }
    for (final l in _lineas) {
      l.dispose();
    }
    super.dispose();
  }

  double get _total => _lineas.fold(0.0, (s, l) {
    final j = l.json();
    return s + (j['quantity'] as double) * (j['unitPrice'] as double);
  });

  Future<void> _elegirCliente() async {
    final c = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: SelectorCliente()),
    );
    if (c != null) {
      setState(() {
        _cliente = c;
        if (_direccion.text.isEmpty) _direccion.text = aTexto(c['address']);
        if (_recibe.text.isEmpty) _recibe.text = aTexto(c['name']);
      });
    }
  }

  Future<void> _agregarProducto() async {
    final p = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: _SelectorProducto()),
    );
    if (p != null) setState(() => _lineas.add(_Linea(p)));
  }

  Future<void> _elegirPunto() async {
    final u = await Navigator.of(context).push<UbicacionElegida>(
      MaterialPageRoute(builder: (_) => ConTemaAlumVid(child: MapaSelectorScreen(inicial: _punto))),
    );
    if (u == null) return;
    setState(() {
      _punto = u.punto;
      if (_direccion.text.trim().isEmpty && (u.direccion ?? '').isNotEmpty) _direccion.text = u.direccion!;
    });
  }

  Future<void> _consultar() async {
    if (_lineas.isEmpty || !_form.currentState!.validate()) return;
    setState(() => _consultando = true);
    try {
      final r = await Api.disponibilidad(_lineas.map((l) => l.json()).toList());
      final filas = (r['lines'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        for (var i = 0; i < _lineas.length && i < filas.length; i++) {
          _lineas[i].disponibilidad = filas[i];
        }
        _avisoDisponibilidad = r['available'] == true
            ? 'Todo el material está disponible: se reservará al confirmar.'
            : 'Hay material faltante: el pedido quedará como "Falta material" hasta que ingrese stock.';
      });
    } catch (e) {
      if (mounted) avisoError(context, e);
    } finally {
      if (mounted) setState(() => _consultando = false);
    }
  }

  Future<void> _guardar() async {
    if (_cliente == null) {
      avisoError(context, 'Selecciona un cliente');
      return;
    }
    if (_lineas.isEmpty) {
      avisoError(context, 'Agrega al menos un producto');
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (_entrega && _punto == null) {
      avisoError(context, 'Marca la ubicación de entrega en el mapa: se usa para planificar la ruta');
      return;
    }
    setState(() => _guardando = true);
    try {
      final r = await Api.crearPedido({
        'clientId': _cliente!['id'],
        'deliveryMode': _entrega ? 'ENTREGA' : 'RETIRO',
        'deliveryAddress': _entrega ? _direccion.text.trim() : '',
        'receiverName': _recibe.text.trim(),
        'notes': _notas.text.trim(),
        'externallyConfirmed': true,
        'externalInvoiceReference': _factura.text.trim(),
        if (_entrega) 'deliveryLatitude': _punto!.latitude,
        if (_entrega) 'deliveryLongitude': _punto!.longitude,
        'lines': _lineas.map((l) => l.json()).toList(),
      });
      final orden = Map<String, dynamic>.from(r['order'] as Map);
      if (!mounted) return;
      avisoOk(
        context,
        orden['state'] == 'RESERVADO'
            ? 'Pedido #${orden['number']} creado y material reservado'
            : 'Pedido #${orden['number']} creado: ${humanizar(aTexto(orden['state'])).toLowerCase()}',
      );
      Navigator.pop(context, '${orden['id']}');
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        avisoError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo pedido')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    Text(fmtDinero(_total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Confirmar pedido'),
              ),
            ],
          ),
        ),
      ),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SeccionTitulo('Cliente'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: AvatarIniciales(aTexto(_cliente?['name'], '?')),
                title: Text(_cliente == null ? 'Seleccionar cliente' : aTexto(_cliente!['name'])),
                subtitle: _cliente == null
                    ? const Text('Busca en el catálogo o regístralo')
                    : Text([aTexto(_cliente!['identification']), aTexto(_cliente!['phone'])].where((x) => x.isNotEmpty).join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _elegirCliente,
              ),
            ),
            const SeccionTitulo('Entrega'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Retiro en local'), icon: Icon(Icons.storefront_outlined)),
                ButtonSegment(value: true, label: Text('A domicilio'), icon: Icon(Icons.local_shipping_outlined)),
              ],
              selected: {_entrega},
              onSelectionChanged: (v) => setState(() => _entrega = v.first),
            ),
            const SizedBox(height: 12),
            if (_entrega) ...[
              TextFormField(
                controller: _direccion,
                decoration: const InputDecoration(labelText: 'Dirección de entrega *'),
                validator: (v) => _entrega && (v ?? '').trim().isEmpty ? 'Indica la dirección' : null,
              ),
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Icon(Icons.map_outlined, color: _punto == null ? AppColors.warning : AppColors.success),
                  title: Text(_punto == null ? 'Marcar ubicación en el mapa *' : 'Ubicación marcada'),
                  subtitle: Text(_punto == null
                      ? 'Necesaria para planificar la ruta'
                      : '${_punto!.latitude.toStringAsFixed(5)}, ${_punto!.longitude.toStringAsFixed(5)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _elegirPunto,
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _recibe,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: _entrega ? 'Quién recibe' : 'Quién retira'),
            ),
            SeccionTitulo('Productos (${_lineas.length})',
                accion: TextButton.icon(onPressed: _agregarProducto, icon: const Icon(Icons.add), label: const Text('Agregar'))),
            if (_lineas.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.add_box_outlined),
                  title: const Text('Agrega los productos del pedido'),
                  onTap: _agregarProducto,
                ),
              ),
            for (final (i, l) in _lineas.indexed) _lineaCard(i, l),
            if (_lineas.isNotEmpty) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _consultando ? null : _consultar,
                icon: _consultando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.fact_check_outlined),
                label: const Text('Consultar disponibilidad'),
              ),
              if (_avisoDisponibilidad != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_avisoDisponibilidad!, style: const TextStyle(color: AppColors.textMuted)),
                ),
            ],
            const SeccionTitulo('Datos adicionales'),
            TextFormField(controller: _factura, decoration: const InputDecoration(labelText: 'Referencia de factura (opcional)')),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notas,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'El pedido se registra como confirmado y pagado fuera del sistema. La reserva dura 72 horas y se renueva con cada avance.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineaCard(int i, _Linea l) {
    final p = l.producto;
    final disp = l.disponibilidad;
    final esVidrio = l.porPiezas && l.tipo == 'VIDRIO';
    final esPerfil = l.porPiezas && l.tipo == 'ALUMINIO';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('Disponible: ${fmtNum(aNum(p['availableStock']))} · ${p['code']}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                if (disp != null) EstadoChip(aTexto(disp['state']), texto: disp['state'] == 'RESERVADO' ? 'Disponible' : 'Falta ${fmtNum(aNum(disp['missingQuantity']))}'),
                IconButton(
                  tooltip: 'Quitar producto',
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  onPressed: () => setState(() => _lineas.removeAt(i).dispose()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: l.cantidad,
                      keyboardType: TextInputType.numberWithOptions(decimal: !l.porPiezas),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(l.porPiezas ? r'[0-9]' : r'[0-9.,]'))],
                      decoration: InputDecoration(labelText: l.porPiezas ? 'Piezas' : 'Cantidad'),
                      validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <= 0 ? 'Requerido' : null,
                    ),
                  ),
                  if (esPerfil)
                    SizedBox(
                      width: 150,
                      child: TextFormField(
                        controller: l.medida,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Largo (m)', helperText: 'Máx. ${fmtNum(l.largoCompleto ?? 0)} m'),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                          if (n == null || n <= 0) return 'Indica el largo';
                          if (l.largoCompleto != null && n > l.largoCompleto!) return 'Supera el perfil';
                          return null;
                        },
                      ),
                    ),
                  if (esVidrio)
                    SizedBox(
                      width: 170,
                      child: TextFormField(
                        controller: l.medida,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Ancho (cm)',
                          helperText: 'Alto fijo ${fmtNum(l.altoVidrio ?? 0)} cm',
                        ),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                          if (n == null || n <= 0) return 'Indica el ancho';
                          if (l.anchoCompleto != null && n > l.anchoCompleto!) return 'Supera la plancha';
                          return null;
                        },
                      ),
                    ),
                  SizedBox(
                    width: 130,
                    child: TextFormField(
                      controller: l.precio,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Precio unit.', prefixText: r'$ '),
                      validator: (v) => double.tryParse((v ?? '').replaceAll(',', '.')) == null ? 'Requerido' : null,
                    ),
                  ),
                ],
              ),
            ),
            if (disp != null && aTexto(disp['notice']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(aTexto(disp['notice']), style: const TextStyle(color: AppColors.warning, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Buscador de productos con su disponibilidad real (stock menos reservado).
class _SelectorProducto extends StatefulWidget {
  const _SelectorProducto();

  @override
  State<_SelectorProducto> createState() => _SelectorProductoState();
}

class _SelectorProductoState extends State<_SelectorProducto> {
  String _q = '';
  late Future<List<Map<String, dynamic>>> _f = Api.productosVenta();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: CampoBusqueda(
            hint: 'Buscar producto',
            onChanged: (v) => setState(() {
              _q = v;
              _f = Api.productosVenta(q: _q);
            }),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _f,
            builder: (ctx, snap) {
              if (snap.hasError) return VistaError(mensaje: limpiarError(snap.error!), onReintentar: () => setState(() => _f = Api.productosVenta(q: _q)));
              if (!snap.hasData) return const CargandoLista();
              final items = snap.data!;
              if (items.isEmpty) return const VistaVacia(icono: Icons.search_off, titulo: 'Sin productos');
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final p = items[i];
                  final disp = aNum(p['availableStock']);
                  return ListTile(
                    leading: Icon(
                      p['piecesManaged'] == true
                          ? (p['kind'] == 'VIDRIO' ? Icons.window_outlined : Icons.straighten)
                          : Icons.inventory_2_outlined,
                    ),
                    title: Text('${p['name']}'),
                    subtitle: Text('${p['code']}${p['piecesManaged'] == true ? ' · por medida' : ''}',
                        style: const TextStyle(color: AppColors.textMuted)),
                    trailing: Text(
                      fmtNum(disp),
                      style: TextStyle(fontWeight: FontWeight.w800, color: disp > 0 ? AppColors.success : AppColors.danger),
                    ),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
