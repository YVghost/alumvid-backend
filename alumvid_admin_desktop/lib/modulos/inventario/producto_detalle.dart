import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/movimiento.dart';
import '../../models/producto.dart';
import '../../services/api_negocio.dart';
import '../../services/api_service.dart';
import '../../shared/adaptable.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';
import '../bodega/traslado.dart';
import 'ficha_pieza.dart';
import 'inventario_modulo.dart';
import 'producto_form.dart';

const _estadosPieza = <String, String>{
  'DISPONIBLE': 'Disponibles',
  'PREPARADO': 'Preparadas',
  'ENTREGADO': 'Entregadas',
  'TRANSFORMADO': 'Cortadas',
  'CONSUMIDO': 'Consumidas',
  'DESCARTADO': 'Descartadas',
};

/// Ficha del material: existencias reales (unidades por ubicación o piezas
/// con medida), movimientos y operaciones manuales permitidas.
class ProductoDetalle extends StatefulWidget {
  const ProductoDetalle({super.key, required this.producto, required this.permisos});
  final Producto producto;
  final Permisos permisos;

  @override
  State<ProductoDetalle> createState() => _ProductoDetalleState();
}

class _ProductoDetalleState extends State<ProductoDetalle> {
  late Producto _p = widget.producto;
  Map<String, dynamic>? _resumen; // piezas
  Map<String, dynamic>? _ubicaciones; // unidades
  List<Map<String, dynamic>> _piezas = [];
  List<MovimientoInventario> _movs = [];
  String _estadoPiezas = 'DISPONIBLE';
  final Set<String> _seleccion = {};
  String? _error;
  bool _cargando = true;

  Permisos get perm => widget.permisos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final r = await ApiService.obtenerProductos(q: _p.code, includeInactive: true, size: 10);
      final nuevo = (r['items'] as List).cast<Producto>().where((x) => x.id == _p.id).firstOrNull;
      if (nuevo != null) _p = nuevo;
      await Future.wait([
        if (_p.piecesManaged) ...[
          Api.resumenPiezas(_p.id).then((v) => _resumen = v),
          Api.piezasDeProducto(_p.id, estado: _estadoPiezas).then((v) => _piezas = v),
        ] else
          Api.ubicacionesDe(_p.id).then((v) => _ubicaciones = v),
        ApiService.obtenerMovimientos(_p.id, size: 40).then((v) => _movs = v),
      ]);
    } catch (e) {
      _error = limpiarError(e);
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarPiezas(String estado) async {
    setState(() {
      _estadoPiezas = estado;
      _seleccion.clear();
    });
    try {
      final v = await Api.piezasDeProducto(_p.id, estado: estado);
      if (mounted) setState(() => _piezas = v);
    } catch (e) {
      if (mounted) avisoError(context, e);
    }
  }

  // ------------------------------------------------------------------ acciones

  Future<void> _recepcion() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecepcionSheet(producto: _p, resumen: _resumen),
    );
    if (ok == true) _cargar();
  }

  Future<void> _conteo() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConteoSheet(producto: _p),
    );
    if (ok == true) _cargar();
  }

  Future<void> _editar() async {
    final ok = await abrirPanel<bool>(context, (_) => ProductoForm(producto: _p));
    if (ok == true) _cargar();
  }

  Future<void> _abrirPieza(String id) async {
    final cambio = await abrirPanel<bool>(context, (_) => FichaPieza(piezaId: id, permisos: perm));
    if (cambio == true) _cargar();
  }

  Future<void> _trasladarSeleccion() async {
    final porUbicacion = <String, List<String>>{};
    for (final pz in _piezas.where((x) => _seleccion.contains('${x['id']}'))) {
      porUbicacion.putIfAbsent(aTexto(pz['location']), () => []).add('${pz['id']}');
    }
    // Las piezas pueden estar en distintos espacios: el origen se valida por pieza.
    final ok = await trasladarVarios(context, items: [
      for (final e in porUbicacion.entries)
        ItemTraslado(productoId: _p.id, nombre: '${e.value.length} pieza(s) en ${e.key.isEmpty ? 'sin ubicación' : e.key}', piezas: e.value),
    ]);
    if (ok) {
      _seleccion.clear();
      _cargar();
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_p.code),
          actions: [
            if (perm.editaCatalogo) IconButton(tooltip: 'Editar producto', icon: const Icon(Icons.edit_outlined), onPressed: _editar),
          ],
          bottom: const TabBar(tabAlignment: TabAlignment.fill, tabs: [Tab(text: 'Existencias'), Tab(text: 'Movimientos')]),
        ),
        bottomNavigationBar: _barra(),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  RefreshIndicator(onRefresh: _cargar, child: _existencias()),
                  RefreshIndicator(onRefresh: _cargar, child: _movimientos()),
                ],
              ),
      ),
    );
  }

  Widget? _barra() {
    if (_seleccion.isNotEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              TextButton(onPressed: () => setState(_seleccion.clear), child: const Text('Cancelar')),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _trasladarSeleccion,
                  icon: const Icon(Icons.move_up),
                  label: Text('Trasladar ${_seleccion.length} pieza(s)'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final botones = <Widget>[
      if (perm.bodega && _p.active)
        FilledButton.icon(onPressed: _recepcion, icon: const Icon(Icons.add_box_outlined), label: const Text('Recepción de compra')),
      if (perm.ajustaInventario && !_p.piecesManaged && _p.active)
        OutlinedButton.icon(onPressed: _conteo, icon: const Icon(Icons.fact_check_outlined), label: const Text('Conteo físico')),
    ];
    if (botones.isEmpty) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: [for (final (i, b) in botones.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: b)]]),
      ),
    );
  }

  Widget _cabecera() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_p.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    [humanizar(_p.category), if (_p.supplier.isNotEmpty) _p.supplier, 'mínimo ${fmtNum(_p.minStock)}'].join(' · '),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  if (!_p.active) ...[const SizedBox(height: 8), const EstadoChip('INACTIVO', texto: 'Inactivo')],
                ],
              ),
            ),
            StockBadge(_p, grande: true),
          ],
        ),
      ),
    );
  }

  Widget _existencias() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _cabecera(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(child: ListTile(leading: const Icon(Icons.error_outline, color: AppColors.danger), title: Text(_error!))),
          ),
        if (_p.piecesManaged) ..._existenciasPorPieza() else ..._existenciasPorUnidad(),
      ],
    );
  }

  List<Widget> _existenciasPorUnidad() {
    final u = _ubicaciones;
    if (u == null) return [];
    final lugares = ((u['placements'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final sinUbicar = aNum(u['unlocatedStock']);
    return [
      const SeccionTitulo('Dónde está'),
      Card(
        child: Column(
          children: [
            if (lugares.isEmpty && sinUbicar <= 0)
              const ListTile(leading: Icon(Icons.info_outline), title: Text('Sin existencias')),
            for (final l in lugares)
              ListTile(
                leading: const Icon(Icons.shelves, color: AppColors.primaryLight),
                title: Text('${l['code']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${fmtNum(aNum(l['quantity']))} ${unidadCorta(_p.unit)}'),
                trailing: perm.bodega
                    ? TextButton.icon(
                        onPressed: () async {
                          final ok = await trasladarMaterial(context,
                              productoId: _p.id, descripcion: _p.name, cantidadMax: aNum(l['quantity']), origen: '${l['code']}', origenId: '${l['space_id']}');
                          if (ok) _cargar();
                        },
                        icon: const Icon(Icons.move_up, size: 18),
                        label: const Text('Trasladar'),
                      )
                    : null,
              ),
            if (sinUbicar > 0)
              ListTile(
                leading: const Icon(Icons.help_outline, color: AppColors.warning),
                title: const Text('Sin ubicación asignada'),
                subtitle: Text('${fmtNum(sinUbicar)} ${unidadCorta(_p.unit)}'),
                trailing: perm.bodega
                    ? TextButton.icon(
                        onPressed: () async {
                          final ok = await trasladarMaterial(context, productoId: _p.id, descripcion: _p.name, cantidadMax: sinUbicar);
                          if (ok) _cargar();
                        },
                        icon: const Icon(Icons.place_outlined, size: 18),
                        label: const Text('Ubicar'),
                      )
                    : null,
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _existenciasPorPieza() {
    final r = _resumen;
    final grupos = ((r?['breakdown'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final seleccionando = _seleccion.isNotEmpty;
    return [
      if (r != null) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _Kpi('Unidades completas', '${r['fullPieces'] ?? 0}', AppColors.success)),
            const SizedBox(width: 10),
            Expanded(child: _Kpi('Retazos', '${r['remnantPieces'] ?? 0}', AppColors.violet)),
            const SizedBox(width: 10),
            Expanded(child: _Kpi('Equivalente', fmtNum(aNum(r['calculatedStock'])), AppColors.primaryLight)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Unidad completa: ${medidas(r['fullLengthM'], r['fullWidthCm'], r['fullHeightCm'])} (${humanizar(aTexto(r['kind']))})',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
        const SeccionTitulo('Por medida y ubicación'),
        Card(
          child: Column(
            children: [
              if (grupos.isEmpty) const ListTile(title: Text('Sin piezas disponibles')),
              for (final g in grupos)
                ListTile(
                  leading: Icon(g['fullPiece'] == true ? Icons.crop_square : Icons.content_cut,
                      color: g['fullPiece'] == true ? AppColors.success : AppColors.violet),
                  title: Text(medidas(g['lengthM'], g['widthCm'], g['heightCm']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(aTexto(g['location'], 'Sin ubicación'), style: const TextStyle(color: AppColors.textMuted)),
                  trailing: Text('× ${g['quantity']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
        ),
      ],
      SeccionTitulo(
        'Piezas (${_piezas.length})',
        accion: perm.bodega && _estadoPiezas == 'DISPONIBLE' && _piezas.isNotEmpty && !seleccionando
            ? TextButton.icon(
                onPressed: () => setState(() => _seleccion.add('${_piezas.first['id']}')),
                icon: const Icon(Icons.checklist, size: 18),
                label: const Text('Seleccionar'),
              )
            : null,
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final e in _estadosPieza.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: _estadoPiezas == e.key,
                  showCheckmark: false,
                  onSelected: (_) => _cargarPiezas(e.key),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (_piezas.isEmpty)
        const Card(child: ListTile(title: Text('No hay piezas en este estado')))
      else
        Card(
          child: Column(
            children: [
              for (final pz in _piezas)
                ListTile(
                  leading: seleccionando
                      ? Checkbox(
                          value: _seleccion.contains('${pz['id']}'),
                          onChanged: (v) => setState(() => v == true ? _seleccion.add('${pz['id']}') : _seleccion.remove('${pz['id']}')),
                        )
                      : Icon(pz['fullPiece'] == true ? Icons.crop_square : Icons.content_cut),
                  title: Text(medidas(pz['lengthM'], pz['widthCm'], pz['heightCm']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${aTexto(pz['location'], 'Sin ubicación')} · ${fmtNum(aNum(pz['percentage']))} %',
                      style: const TextStyle(color: AppColors.textMuted)),
                  trailing: seleccionando ? null : const Icon(Icons.chevron_right),
                  onTap: seleccionando
                      ? () => setState(() {
                            final id = '${pz['id']}';
                            _seleccion.contains(id) ? _seleccion.remove(id) : _seleccion.add(id);
                          })
                      : () => _abrirPieza('${pz['id']}'),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _movimientos() {
    if (_movs.isEmpty) {
      return const VistaVacia(icono: Icons.history, titulo: 'Sin movimientos', mensaje: 'Las salidas por pedidos y las recepciones aparecerán aquí.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          child: Column(
            children: [
              for (final m in _movs)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (m.delta >= 0 ? AppColors.success : AppColors.danger).withValues(alpha: 0.16),
                    child: Icon(
                      m.type == 'INGRESO' ? Icons.south_west : m.type == 'SALIDA' ? Icons.north_east : Icons.tune,
                      color: m.type == 'AJUSTE' ? AppColors.violet : m.delta >= 0 ? AppColors.success : AppColors.danger,
                      size: 20,
                    ),
                  ),
                  title: Text(m.reason.isEmpty ? humanizar(m.type) : m.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [if (m.reference.isNotEmpty) m.reference, m.actorName, fmtFecha(m.occurredAt)].join(' · '),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${m.delta >= 0 ? '+' : ''}${fmtNum(m.delta)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('→ ${fmtNum(m.stockAfter)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.titulo, this.valor, this.color);
  final String titulo, valor;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(titulo, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    ),
  );
}

/// Recepción de compra: ingreso de unidades o de piezas con medida.
class _RecepcionSheet extends StatefulWidget {
  const _RecepcionSheet({required this.producto, this.resumen});
  final Producto producto;
  final Map<String, dynamic>? resumen;

  @override
  State<_RecepcionSheet> createState() => _RecepcionSheetState();
}

class _RecepcionSheetState extends State<_RecepcionSheet> {
  final _form = GlobalKey<FormState>();
  final _cantidad = TextEditingController();
  late final _medida = TextEditingController(text: widget.producto.piecesManaged ? fmtNum(_medidaCompleta()) : '');

  /// Medida de una unidad completa: ancho de la plancha o largo del perfil.
  double _medidaCompleta() {
    final r = widget.resumen ?? const <String, dynamic>{};
    return aNum(r['kind'] == 'VIDRIO' ? r['fullWidthCm'] : r['fullLengthM']);
  }
  final _referencia = TextEditingController();
  final _motivo = TextEditingController(text: 'Compra a proveedor');
  late final Future<List<Map<String, dynamic>>> _espacios = Api.espacios();
  String? _ubicacion;
  bool _enviando = false;

  bool get _vidrio => widget.resumen?['kind'] == 'VIDRIO';

  @override
  void dispose() {
    for (final c in [_cantidad, _medida, _referencia, _motivo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _enviando = true);
    final p = widget.producto;
    final n = double.parse(_cantidad.text.replaceAll(',', '.'));
    final motivo = [_motivo.text.trim(), if (_referencia.text.trim().isNotEmpty) 'Ref. ${_referencia.text.trim()}'].join(' · ');
    try {
      if (p.piecesManaged) {
        final m = double.parse(_medida.text.replaceAll(',', '.'));
        await Api.registrarPiezas(p.id,
            cantidad: n.toInt(),
            largoM: _vidrio ? null : m,
            anchoCm: _vidrio ? m : null,
            altoCm: _vidrio ? aNumONulo(widget.resumen?['fullHeightCm']) : null,
            ubicacion: _ubicacion ?? '',
            motivo: motivo);
      } else {
        await Api.movimientoInventario(p.id, tipo: 'INGRESO', cantidad: n, motivo: _motivo.text.trim(), referencia: _referencia.text.trim());
        if (_ubicacion != null) {
          await Api.trasladar(productoId: p.id, haciaEspacioId: _ubicacion!, cantidad: n, motivo: 'Ubicación de la recepción');
        }
      }
      if (!mounted) return;
      avisoOk(context, 'Recepción registrada');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        avisoError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Recepción de compra', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(p.name, style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cantidad,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(decimal: !p.piecesManaged),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(p.piecesManaged ? r'[0-9]' : r'[0-9.,]'))],
                decoration: InputDecoration(
                  labelText: p.piecesManaged ? 'Número de piezas' : 'Cantidad',
                  suffixText: p.piecesManaged ? 'piezas' : unidadCorta(p.unit),
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                  if (n == null || n <= 0) return 'Indica la cantidad';
                  if (p.piecesManaged && n > 200) return 'Máximo 200 piezas por registro';
                  return null;
                },
              ),
              if (p.piecesManaged) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _medida,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _vidrio ? 'Ancho de cada plancha (cm)' : 'Largo de cada perfil (m)',
                    helperText: _vidrio
                        ? 'Alto fijo ${fmtNum(aNum(widget.resumen?['fullHeightCm']))} cm. Unidad completa: ${fmtNum(aNum(widget.resumen?['fullWidthCm']))} cm'
                        : 'Perfil completo: ${fmtNum(aNum(widget.resumen?['fullLengthM']))} m',
                  ),
                  validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <= 0 ? 'Indica la medida' : null,
                ),
              ],
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _espacios,
                builder: (ctx, snap) => DropdownButtonFormField<String?>(
                  initialValue: _ubicacion,
                  decoration: const InputDecoration(labelText: 'Guardar en (opcional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sin ubicación')),
                    for (final e in (snap.data ?? const <Map<String, dynamic>>[]).where((e) => e['active'] != false))
                      DropdownMenuItem(value: p.piecesManaged ? '${e['code']}' : '${e['id']}', child: Text('${e['code']}')),
                  ],
                  onChanged: (v) => setState(() => _ubicacion = v),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _referencia, decoration: const InputDecoration(labelText: 'Factura o guía (opcional)')),
              const SizedBox(height: 12),
              TextFormField(
                controller: _motivo,
                decoration: const InputDecoration(labelText: 'Motivo'),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Describe el motivo' : null,
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: _enviando ? null : _guardar, child: const Text('Registrar recepción')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Conteo físico: el stock pasa a ser la cantidad contada (solo administración).
class _ConteoSheet extends StatefulWidget {
  const _ConteoSheet({required this.producto});
  final Producto producto;

  @override
  State<_ConteoSheet> createState() => _ConteoSheetState();
}

class _ConteoSheetState extends State<_ConteoSheet> {
  final _form = GlobalKey<FormState>();
  final _cantidad = TextEditingController();
  final _motivo = TextEditingController(text: 'Conteo físico');
  bool _enviando = false;

  @override
  void dispose() {
    _cantidad.dispose();
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _enviando = true);
    try {
      await Api.movimientoInventario(widget.producto.id,
          tipo: 'AJUSTE', cantidad: double.parse(_cantidad.text.replaceAll(',', '.')), motivo: _motivo.text.trim());
      if (!mounted) return;
      avisoOk(context, 'Conteo registrado');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        avisoError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    final contado = double.tryParse(_cantidad.text.replaceAll(',', '.'));
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Conteo físico', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${p.name} · sistema: ${fmtNum(p.stock)} ${unidadCorta(p.unit)}', style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cantidad,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Cantidad contada', suffixText: unidadCorta(p.unit)),
              validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1) < 0 ? 'Indica la cantidad contada' : null,
            ),
            if (contado != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Diferencia: ${contado - p.stock >= 0 ? '+' : ''}${fmtNum(contado - p.stock)} ${unidadCorta(p.unit)}',
                  style: TextStyle(color: contado - p.stock == 0 ? AppColors.textMuted : AppColors.warning, fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _motivo,
              decoration: const InputDecoration(labelText: 'Motivo'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Describe el motivo' : null,
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _enviando ? null : _guardar, child: const Text('Registrar conteo')),
          ],
        ),
      ),
    );
  }
}
