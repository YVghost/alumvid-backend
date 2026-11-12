import 'package:alumvid_admin_desktop/models/movimiento.dart';
import 'package:alumvid_admin_desktop/models/producto.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sesion.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

const _categorias = [
  'VIDRIO',
  'ALUMINIO',
  'ACCESORIOS',
  'VYNIL',
  'ACRILICO',
  'ACERO INOXIDABLE',
];
const _unidades = <String, String>{
  'UNIDAD': 'Unidad',
  'METRO': 'Metro lineal (m)',
  'METRO_CUADRADO': 'Metro cuadrado (m²)',
  'ROLLO': 'Rollo',
  'KILOGRAMO': 'Kilogramo (kg)',
  'LITRO': 'Litro (L)',
};

String _unidadCorta(String u) => switch (u) {
  'METRO' => 'm',
  'METRO_CUADRADO' => 'm²',
  'KILOGRAMO' => 'kg',
  'LITRO' => 'L',
  'ROLLO' => 'rollos',
  _ => 'unid.',
};

/// Inventario y stock. Ver: todos los roles comerciales.
/// Movimientos: ADMINISTRADOR y BODEGUERO. Catálogo: ADMINISTRADOR.
class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key, required this.sesion});
  final Sesion sesion;

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

enum _Filtro { todos, stockBajo, inactivos }

class _InventarioScreenState extends State<InventarioScreen> {
  _Filtro _filtro = _Filtro.todos;
  String _categoria = '';
  String _q = '';
  bool _cargando = true;
  String? _error;
  List<Producto> _items = [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await adm.ApiService.obtenerProductos(
        q: _q,
        category: _categoria,
        lowStock: _filtro == _Filtro.stockBajo,
        includeInactive: _filtro == _Filtro.inactivos,
        size: 100,
      );
      var items = (r['items'] as List).cast<Producto>();
      if (_filtro == _Filtro.inactivos) {
        items = items.where((p) => !p.active).toList();
      }
      if (mounted) {
        setState(() {
          _items = items;
          _total = r['total'] as int;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrir(Producto p) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductoDetalleScreen(producto: p, sesion: widget.sesion),
      ),
    );
    if (cambio == true) _cargar();
  }

  Future<void> _nuevo() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProductoFormScreen()),
    );
    if (ok == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sesion;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Categoría',
            icon: Badge(
              isLabelVisible: _categoria.isNotEmpty,
              smallSize: 8,
              child: const Icon(Icons.filter_list),
            ),
            initialValue: _categoria,
            onSelected: (v) {
              setState(() => _categoria = v);
              _cargar();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('Todas las categorías')),
              for (final c in _categorias)
                PopupMenuItem(value: c, child: Text(humanizar(c))),
            ],
          ),
        ],
      ),
      floatingActionButton: s.puedeEditarCatalogo
          ? FloatingActionButton.extended(
              onPressed: _nuevo,
              icon: const Icon(Icons.add),
              label: const Text('Producto'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: CampoBusqueda(
              hint: 'Buscar por nombre o código',
              onChanged: (v) {
                _q = v;
                _cargar();
              },
            ),
          ),
          FiltrosChips<_Filtro>(
            opciones: {
              _Filtro.todos: 'Todos',
              _Filtro.stockBajo: 'Stock bajo',
              if (s.puedeEditarCatalogo) _Filtro.inactivos: 'Inactivos',
            },
            seleccion: _filtro,
            onSeleccion: (v) {
              setState(() => _filtro = v);
              _cargar();
            },
          ),
          if (!_cargando && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Text(
                    '${_items.length} de $_total productos'
                    '${_categoria.isEmpty ? '' : ' · ${humanizar(_categoria)}'}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const CargandoLista();
    if (_error != null) return VistaError(mensaje: _error!, onReintentar: _cargar);
    return RefreshIndicator(
      onRefresh: _cargar,
      child: _items.isEmpty
          ? const VistaVacia(
              icono: Icons.inventory_2_outlined,
              titulo: 'Sin productos',
              mensaje: 'Prueba con otra búsqueda o filtro.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ProductoCard(
                producto: _items[i],
                onTap: () => _abrir(_items[i]),
              ),
            ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge(this.p, {this.grande = false});
  final Producto p;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final color = p.isAgotado
        ? AppColors.danger
        : p.isStockBajo
        ? AppColors.warning
        : AppColors.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fmtNum(p.stock),
          style: TextStyle(
            color: color,
            fontSize: grande ? 34 : 20,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _unidadCorta(p.unit),
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _ProductoCard extends StatelessWidget {
  const _ProductoCard({required this.producto, required this.onTap});
  final Producto producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.active ? AppColors.text : AppColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [p.code, humanizar(p.category), if (p.location.isNotEmpty) p.location]
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    if (p.isAgotado || p.isStockBajo || !p.active) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (!p.active) const EstadoChip('INACTIVO', texto: 'Inactivo'),
                          if (p.isAgotado) const EstadoChip('AGOTADO', texto: 'Agotado'),
                          if (p.isStockBajo)
                            EstadoChip('EN_CURSO', texto: 'Bajo mínimo (${fmtNum(p.minStock)})'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _StockBadge(p),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detalle de producto
// ---------------------------------------------------------------------------

class ProductoDetalleScreen extends StatefulWidget {
  const ProductoDetalleScreen({super.key, required this.producto, required this.sesion});
  final Producto producto;
  final Sesion sesion;

  @override
  State<ProductoDetalleScreen> createState() => _ProductoDetalleScreenState();
}

class _ProductoDetalleScreenState extends State<ProductoDetalleScreen> {
  late Producto _p = widget.producto;
  List<MovimientoInventario> _movs = [];
  bool _cargando = true;
  String? _error;
  bool _cambio = false;

  @override
  void initState() {
    super.initState();
    _cargarMovs();
  }

  Future<void> _cargarMovs() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final m = await adm.ApiService.obtenerMovimientos(_p.id, size: 30);
      if (mounted) setState(() => _movs = m);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _refrescarProducto() async {
    try {
      final r = await adm.ApiService.obtenerProductos(q: _p.code, includeInactive: true, size: 10);
      final lista = (r['items'] as List).cast<Producto>();
      final nuevo = lista.where((x) => x.id == _p.id).firstOrNull;
      if (nuevo != null && mounted) setState(() => _p = nuevo);
    } catch (_) {}
  }

  Future<void> _movimiento() async {
    final m = await showModalBottomSheet<MovimientoInventario>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MovimientoSheet(producto: _p, permiteAjuste: widget.sesion.esAdmin),
    );
    if (m == null || !mounted) return;
    _cambio = true;
    avisoOk(context, 'Movimiento registrado. Stock: ${fmtNum(m.stockAfter)}');
    await Future.wait([_refrescarProducto(), _cargarMovs()]);
  }

  Future<void> _editar() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ProductoFormScreen(producto: _p)),
    );
    if (ok == true) {
      _cambio = true;
      await _refrescarProducto();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sesion;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _cambio);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_p.code),
          actions: [
            if (s.puedeEditarCatalogo)
              IconButton(
                tooltip: 'Editar producto',
                icon: const Icon(Icons.edit_outlined),
                onPressed: _editar,
              ),
          ],
        ),
        bottomNavigationBar: s.puedeMoverStock && _p.active
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _movimiento,
                    icon: const Icon(Icons.swap_vert),
                    label: const Text('Registrar movimiento'),
                  ),
                ),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: () => Future.wait([_refrescarProducto(), _cargarMovs()]),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _p.name,
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Stock mínimo: ${fmtNum(_p.minStock)} ${_unidadCorta(_p.unit)}',
                              style: const TextStyle(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      _StockBadge(_p, grande: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      DatoFila('Categoría', humanizar(_p.category)),
                      DatoFila('Unidad', _unidades[_p.unit] ?? _p.unit),
                      DatoFila('Ubicación', _p.location),
                      DatoFila('Proveedor', _p.supplier),
                      DatoFila('Cód. externo', _p.externalCode),
                      if (_p.description.isNotEmpty) DatoFila('Descripción', _p.description),
                      DatoFila('Estado', _p.active ? 'Activo' : 'Inactivo'),
                      DatoFila('Actualizado', fmtFecha(_p.updatedAt)),
                    ],
                  ),
                ),
              ),
              const SeccionTitulo('Últimos movimientos'),
              if (_cargando)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline, color: AppColors.danger),
                    title: Text(_error!),
                    trailing: TextButton(onPressed: _cargarMovs, child: const Text('Reintentar')),
                  ),
                )
              else if (_movs.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.history),
                    title: Text('Sin movimientos registrados'),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final m in _movs) _MovimientoTile(m),
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

class _MovimientoTile extends StatelessWidget {
  const _MovimientoTile(this.m);
  final MovimientoInventario m;

  @override
  Widget build(BuildContext context) {
    final positivo = m.delta >= 0;
    final color = m.type == 'AJUSTE'
        ? AppColors.violet
        : positivo
        ? AppColors.success
        : AppColors.danger;
    final icono = switch (m.type) {
      'INGRESO' => Icons.south_west,
      'SALIDA' => Icons.north_east,
      _ => Icons.tune,
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.16),
        child: Icon(icono, color: color, size: 20),
      ),
      title: Text(
        m.reason.isEmpty ? humanizar(m.type) : m.reason,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${fmtFecha(m.occurredAt)} · ${m.actorName}',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${positivo ? '+' : ''}${fmtNum(m.delta)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15),
          ),
          Text(
            '→ ${fmtNum(m.stockAfter)}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Registrar movimiento (ADMINISTRADOR / BODEGUERO)
// ---------------------------------------------------------------------------

class _MovimientoSheet extends StatefulWidget {
  const _MovimientoSheet({required this.producto, required this.permiteAjuste});
  final Producto producto;

  /// El backend solo acepta AJUSTE de un ADMINISTRADOR.
  final bool permiteAjuste;

  @override
  State<_MovimientoSheet> createState() => _MovimientoSheetState();
}

class _MovimientoSheetState extends State<_MovimientoSheet> {
  final _form = GlobalKey<FormState>();
  final _cantidad = TextEditingController();
  final _motivo = TextEditingController();
  final _referencia = TextEditingController();
  String _tipo = 'INGRESO';
  bool _enviando = false;

  @override
  void dispose() {
    _cantidad.dispose();
    _motivo.dispose();
    _referencia.dispose();
    super.dispose();
  }

  double? get _valor => double.tryParse(_cantidad.text.replaceAll(',', '.'));

  double? get _stockResultante {
    final v = _valor;
    if (v == null) return null;
    final s = widget.producto.stock;
    return switch (_tipo) {
      'INGRESO' => s + v,
      'SALIDA' => s - v,
      _ => v,
    };
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _enviando = true);
    try {
      final m = await adm.ApiService.registrarMovimiento(
        widget.producto.id,
        type: _tipo,
        quantity: _valor!,
        reason: _motivo.text.trim(),
        reference: _referencia.text.trim(),
      );
      if (mounted) Navigator.pop(context, m);
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
    final resultante = _stockResultante;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Registrar movimiento',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${p.name} · stock actual ${fmtNum(p.stock)} ${_unidadCorta(p.unit)}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'INGRESO', label: Text('Ingreso'), icon: Icon(Icons.south_west)),
                  const ButtonSegment(value: 'SALIDA', label: Text('Salida'), icon: Icon(Icons.north_east)),
                  if (widget.permiteAjuste)
                    const ButtonSegment(value: 'AJUSTE', label: Text('Ajuste'), icon: Icon(Icons.tune)),
                ],
                selected: {_tipo},
                onSelectionChanged: (v) => setState(() => _tipo = v.first),
              ),
              const SizedBox(height: 6),
              Text(
                switch (_tipo) {
                  'INGRESO' => 'Entrada por compra o recepción.',
                  'SALIDA' => 'Despacho o consumo de corte.',
                  _ => 'Conteo físico: la cantidad pasa a ser el nuevo stock.',
                },
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cantidad,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _tipo == 'AJUSTE' ? 'Nuevo stock' : 'Cantidad',
                  suffixText: _unidadCorta(p.unit),
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                  if (n == null) return 'Ingresa un número';
                  if (_tipo != 'AJUSTE' && n <= 0) return 'Debe ser mayor que 0';
                  if (_tipo == 'AJUSTE' && n < 0) return 'No puede ser negativo';
                  if (_tipo == 'SALIDA' && n > p.stock) return 'Supera el stock disponible';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _motivo,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Motivo'),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Describe el motivo' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _referencia,
                decoration: const InputDecoration(
                  labelText: 'Referencia (opcional)',
                  hintText: 'Factura, guía, pedido…',
                ),
              ),
              if (resultante != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Text('Stock resultante: '),
                      Text(
                        '${fmtNum(resultante)} ${_unidadCorta(p.unit)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: resultante < 0 ? AppColors.danger : AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _enviando ? null : _guardar,
                child: _enviando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Guardar movimiento'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alta / edición de producto (ADMINISTRADOR)
// ---------------------------------------------------------------------------

class ProductoFormScreen extends StatefulWidget {
  const ProductoFormScreen({super.key, this.producto});
  final Producto? producto;

  @override
  State<ProductoFormScreen> createState() => _ProductoFormScreenState();
}

class _ProductoFormScreenState extends State<ProductoFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.producto?.code ?? '');
  late final _name = TextEditingController(text: widget.producto?.name ?? '');
  late final _min = TextEditingController(
    text: widget.producto == null ? '5' : fmtNum(widget.producto!.minStock),
  );
  late final _loc = TextEditingController(text: widget.producto?.location ?? '');
  late final _sup = TextEditingController(text: widget.producto?.supplier ?? '');
  late final _ext = TextEditingController(text: widget.producto?.externalCode ?? '');
  late final _desc = TextEditingController(text: widget.producto?.description ?? '');
  late String _categoria = _categorias.contains(widget.producto?.category)
      ? widget.producto!.category
      : 'VIDRIO';
  late String _unidad = _unidades.containsKey(widget.producto?.unit)
      ? widget.producto!.unit
      : 'UNIDAD';
  late bool _activo = widget.producto?.active ?? true;
  bool _guardando = false;

  bool get _editando => widget.producto != null;

  @override
  void dispose() {
    for (final c in [_code, _name, _min, _loc, _sup, _ext, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final data = {
      'code': _code.text.trim().toUpperCase(),
      'name': _name.text.trim(),
      'category': _categoria,
      'unit': _unidad,
      'minStock': double.parse(_min.text.replaceAll(',', '.')),
      'location': _loc.text.trim(),
      'supplier': _sup.text.trim(),
      'externalCode': _ext.text.trim(),
      'description': _desc.text.trim(),
      'active': _activo,
    };
    try {
      if (_editando) {
        await adm.ApiService.actualizarProducto(widget.producto!.id, data);
      } else {
        await adm.ApiService.crearProducto(data);
      }
      if (!mounted) return;
      avisoOk(context, _editando ? 'Producto actualizado' : 'Producto creado');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        avisoError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar producto' : 'Nuevo producto')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(_editando ? 'Guardar cambios' : 'Crear producto'),
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _code,
              enabled: !_editando,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Código *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
            ),
            gap,
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre *'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Mínimo 3 caracteres' : null,
            ),
            gap,
            DropdownButtonFormField<String>(
              initialValue: _categoria,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                for (final c in _categorias)
                  DropdownMenuItem(value: c, child: Text(humanizar(c))),
              ],
              onChanged: (v) => setState(() => _categoria = v ?? _categoria),
            ),
            gap,
            DropdownButtonFormField<String>(
              initialValue: _unidad,
              decoration: const InputDecoration(labelText: 'Unidad de medida'),
              items: [
                for (final e in _unidades.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _unidad = v ?? _unidad),
            ),
            gap,
            TextFormField(
              controller: _min,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Stock mínimo *'),
              validator: (v) {
                final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                return n == null || n < 0 ? 'Número mayor o igual a 0' : null;
              },
            ),
            gap,
            TextFormField(controller: _loc, decoration: const InputDecoration(labelText: 'Ubicación')),
            gap,
            TextFormField(controller: _sup, decoration: const InputDecoration(labelText: 'Proveedor')),
            gap,
            TextFormField(controller: _ext, decoration: const InputDecoration(labelText: 'Código externo')),
            gap,
            TextFormField(
              controller: _desc,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
            if (_editando) ...[
              gap,
              Card(
                child: SwitchListTile(
                  title: const Text('Activo en el catálogo'),
                  subtitle: const Text('Los productos inactivos no aparecen en ventas'),
                  value: _activo,
                  onChanged: (v) => setState(() => _activo = v),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
