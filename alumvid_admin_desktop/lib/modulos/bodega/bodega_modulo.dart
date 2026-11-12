import 'package:flutter/material.dart';

import '../../models/producto.dart';
import '../../services/api_negocio.dart';
import '../../services/api_service.dart';
import '../../shared/adaptable.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';
import '../inventario/ficha_pieza.dart';
import '../inventario/producto_detalle.dart';
import 'traslado.dart';

/// Bodega: dónde está cada material y traslados (individuales o en masa).
class BodegaModulo extends StatelessWidget {
  const BodegaModulo({super.key, required this.permisos});
  final Permisos permisos;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bodega'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Buscar material'), Tab(text: 'Espacios')],
          ),
        ),
        body: TabBarView(children: [_BuscarMaterial(permisos: permisos), _Espacios(permisos: permisos)]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buscar material y su ubicación
// ---------------------------------------------------------------------------

class _BuscarMaterial extends StatefulWidget {
  const _BuscarMaterial({required this.permisos});
  final Permisos permisos;

  @override
  State<_BuscarMaterial> createState() => _BuscarMaterialState();
}

class _BuscarMaterialState extends State<_BuscarMaterial> with AutomaticKeepAliveClientMixin {
  String _q = '';
  late Future<List<Map<String, dynamic>>> _f = Api.materiales();
  final Map<String, Future<Map<String, dynamic>>> _ubic = {};

  @override
  bool get wantKeepAlive => true;

  void _buscar() => setState(() {
    _ubic.clear();
    _f = Api.materiales(q: _q);
  });

  Future<void> _abrir(Map<String, dynamic> m) async {
    final r = await ApiService.obtenerProductos(q: '${m['code']}', includeInactive: true, size: 10);
    final p = (r['items'] as List).cast<Producto>().where((x) => x.id == '${m['id']}').firstOrNull;
    if (p == null || !mounted) return;
    await abrirPanel(context, (_) => ProductoDetalle(producto: p, permisos: widget.permisos), ancho: 640);
    _buscar();
  }

  /// Resumen "dónde está": espacios con cantidad o piezas por ubicación.
  List<String> _resumen(Map<String, dynamic> u) {
    final out = <String>[];
    for (final l in (u['placements'] as List? ?? const [])) {
      out.add('${l['code']}: ${fmtNum(aNum(l['quantity']))}');
    }
    final piezas = <String, int>{};
    for (final p in (u['pieces'] as List? ?? const [])) {
      final k = aTexto(p['location'], 'Sin ubicación');
      piezas[k] = (piezas[k] ?? 0) + 1;
    }
    for (final e in piezas.entries) {
      out.add('${e.key}: ${e.value} pieza${e.value == 1 ? '' : 's'}');
    }
    if (aNum(u['unlocatedStock']) > 0) out.add('Sin ubicar: ${fmtNum(aNum(u['unlocatedStock']))}');
    return out;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnchoLegible(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: CampoBusqueda(
              hint: '¿Qué material buscas? (nombre o código)',
              onChanged: (v) {
                _q = v;
                _buscar();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _f,
              builder: (ctx, snap) {
                if (snap.hasError) return VistaError(mensaje: limpiarError(snap.error!), onReintentar: _buscar);
                if (!snap.hasData) return const CargandoLista();
                final items = snap.data!;
                if (items.isEmpty) return const VistaVacia(icono: Icons.search_off, titulo: 'No se encontró el material');
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final m = items[i];
                    final f = _ubic.putIfAbsent('${m['id']}', () => Api.ubicacionesDe('${m['id']}'));
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _abrir(m),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                                  Text(fmtNum(aNum(m['stock'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                                ],
                              ),
                              Text('${m['code']}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              const SizedBox(height: 8),
                              FutureBuilder<Map<String, dynamic>>(
                                future: f,
                                builder: (ctx, s) {
                                  if (!s.hasData) {
                                    return const SizedBox(height: 28, child: Align(alignment: Alignment.centerLeft, child: Text('Buscando ubicación…', style: TextStyle(color: AppColors.textDim))));
                                  }
                                  final r = _resumen(s.data!);
                                  if (r.isEmpty) return const Text('Sin existencias', style: TextStyle(color: AppColors.textDim));
                                  return Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final t in r)
                                        Chip(
                                          avatar: Icon(t.startsWith('Sin') ? Icons.help_outline : Icons.shelves, size: 16),
                                          label: Text(t),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Espacios físicos
// ---------------------------------------------------------------------------

class _Espacios extends StatefulWidget {
  const _Espacios({required this.permisos});
  final Permisos permisos;

  @override
  State<_Espacios> createState() => _EspaciosState();
}

class _EspaciosState extends State<_Espacios> with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _f = Api.espacios();

  @override
  bool get wantKeepAlive => true;

  void _recargar() => setState(() => _f = Api.espacios());

  Future<void> _editar([Map<String, dynamic>? e]) async {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _EspacioForm(espacio: e));
    if (ok == true) _recargar();
  }

  Future<void> _abrir(Map<String, dynamic> e) async {
    await abrirPanel(context, (_) => EspacioDetalle(espacio: e, permisos: widget.permisos, onEditar: () => _editar(e)));
    _recargar();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: widget.permisos.esAdmin
          ? FloatingActionButton.extended(heroTag: 'nuevo-espacio', onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Espacio'))
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (ctx, snap) {
          if (snap.hasError) return VistaError(mensaje: limpiarError(snap.error!), onReintentar: _recargar);
          if (!snap.hasData) return const CargandoLista();
          final items = snap.data!;
          if (items.isEmpty) return const VistaVacia(icono: Icons.grid_view, titulo: 'Sin espacios registrados');
          return RefreshIndicator(
            onRefresh: () async => _recargar(),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.3,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final e = items[i];
                final activo = e['active'] != false;
                final ocupados = (e['occupiedItems'] as num?)?.toInt() ?? 0;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _abrir(e),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shelves, color: activo ? AppColors.primaryLight : AppColors.textDim),
                              const Spacer(),
                              if (!activo) const EstadoChip('INACTIVO', texto: 'Inactivo'),
                            ],
                          ),
                          const Spacer(),
                          Text('${e['code']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          Text(ocupados == 0 ? 'Vacío' : '$ocupados material${ocupados == 1 ? '' : 'es'}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Contenido de un espacio con selección para trasladar en masa.
class EspacioDetalle extends StatefulWidget {
  const EspacioDetalle({super.key, required this.espacio, required this.permisos, this.onEditar});
  final Map<String, dynamic> espacio;
  final Permisos permisos;
  final VoidCallback? onEditar;

  @override
  State<EspacioDetalle> createState() => _EspacioDetalleState();
}

class _EspacioDetalleState extends State<EspacioDetalle> {
  Map<String, dynamic>? _c;
  String? _error;
  final Set<String> _sel = {}; // 'p:<productId>' o 'z:<pieceId>'

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final c = await Api.contenidoEspacio('${widget.espacio['id']}');
      if (mounted) {
        setState(() {
          _c = c;
          _error = null;
          _sel.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    }
  }

  List<Map<String, dynamic>> _lista(String k) =>
      ((_c?[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _trasladar() async {
    final productos = _lista('products');
    final piezas = _lista('pieces');
    final items = <ItemTraslado>[
      for (final p in productos)
        if (_sel.contains('p:${p['product_id']}'))
          ItemTraslado(productoId: '${p['product_id']}', nombre: '${p['name']}', cantidadMax: aNum(p['quantity'])),
    ];
    final porProducto = <String, List<Map<String, dynamic>>>{};
    for (final z in piezas.where((z) => _sel.contains('z:${z['id']}'))) {
      porProducto.putIfAbsent('${z['product_id']}', () => []).add(z);
    }
    for (final e in porProducto.entries) {
      items.add(ItemTraslado(
        productoId: e.key,
        nombre: '${e.value.first['name']} (${e.value.length} pieza${e.value.length == 1 ? '' : 's'})',
        piezas: e.value.map((z) => '${z['id']}').toList(),
      ));
    }
    final ok = await trasladarVarios(context, items: items, origenCodigo: '${widget.espacio['code']}', origenId: '${widget.espacio['id']}');
    if (ok) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.espacio;
    final productos = _lista('products');
    final piezas = _lista('pieces');
    final puede = widget.permisos.bodega;
    final todas = [for (final p in productos) 'p:${p['product_id']}', for (final z in piezas) 'z:${z['id']}'];
    return Scaffold(
      appBar: AppBar(
        title: Text('${e['code']}'),
        actions: [
          if (puede && todas.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _sel.length == todas.length ? _sel.clear() : _sel.addAll(todas)),
              child: Text(_sel.length == todas.length ? 'Ninguno' : 'Todo'),
            ),
          if (widget.permisos.esAdmin && widget.onEditar != null)
            IconButton(
              tooltip: 'Editar espacio',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                Navigator.pop(context);
                widget.onEditar!();
              },
            ),
        ],
      ),
      bottomNavigationBar: _sel.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _trasladar,
                  icon: const Icon(Icons.move_up),
                  label: Text('Trasladar ${_sel.length} seleccionado(s)'),
                ),
              ),
            ),
      body: _c == null
          ? (_error != null ? VistaError(mensaje: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (aTexto(e['description']).isNotEmpty)
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(aTexto(e['description']), style: const TextStyle(color: AppColors.textMuted))),
                  if (puede && todas.isNotEmpty)
                    const Text('Marca lo que quieras mover y elige el destino una sola vez.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  if (productos.isEmpty && piezas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: Text('Este espacio está vacío', style: TextStyle(color: AppColors.textMuted))),
                    ),
                  if (productos.isNotEmpty) ...[
                    SeccionTitulo('Materiales (${productos.length})'),
                    Card(
                      child: Column(
                        children: [
                          for (final p in productos)
                            _fila(
                              id: 'p:${p['product_id']}',
                              icono: Icons.inventory_2_outlined,
                              titulo: '${p['name']}',
                              subtitulo: '${p['code']}',
                              valor: fmtNum(aNum(p['quantity'])),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (piezas.isNotEmpty) ...[
                    SeccionTitulo('Piezas (${piezas.length})'),
                    Card(
                      child: Column(
                        children: [
                          for (final z in piezas)
                            _fila(
                              id: 'z:${z['id']}',
                              icono: Icons.content_cut,
                              titulo: medidas(z['length_m'], z['width_cm'], z['height_cm']),
                              subtitulo: '${z['name']}${z['reserved'] == true ? ' · reservada' : ''}',
                              estado: aTexto(z['state']),
                              alAbrir: () => abrirPanel(context, (_) => FichaPieza(piezaId: '${z['id']}', permisos: widget.permisos)).then((_) => _cargar()),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _fila({
    required String id,
    required IconData icono,
    required String titulo,
    required String subtitulo,
    String? valor,
    String? estado,
    VoidCallback? alAbrir,
  }) {
    final puede = widget.permisos.bodega;
    final marcado = _sel.contains(id);
    return ListTile(
      leading: puede
          ? Checkbox(value: marcado, onChanged: (v) => setState(() => v == true ? _sel.add(id) : _sel.remove(id)))
          : Icon(icono),
      title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitulo, style: const TextStyle(color: AppColors.textMuted)),
      trailing: valor != null
          ? Text(valor, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))
          : (alAbrir != null ? IconButton(tooltip: 'Ver ficha', onPressed: alAbrir, icon: const Icon(Icons.info_outline)) : EstadoChip(estado ?? '')),
      onTap: puede ? () => setState(() => marcado ? _sel.remove(id) : _sel.add(id)) : alAbrir,
    );
  }
}

class _EspacioForm extends StatefulWidget {
  const _EspacioForm({this.espacio});
  final Map<String, dynamic>? espacio;

  @override
  State<_EspacioForm> createState() => _EspacioFormState();
}

class _EspacioFormState extends State<_EspacioForm> {
  late final _codigo = TextEditingController(text: aTexto(widget.espacio?['code']));
  late final _desc = TextEditingController(text: aTexto(widget.espacio?['description']));
  late bool _activo = widget.espacio?['active'] != false;
  bool _enviando = false;

  @override
  void dispose() {
    _codigo.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_codigo.text.trim().isEmpty) {
      avisoError(context, 'Indica el código del espacio');
      return;
    }
    setState(() => _enviando = true);
    try {
      await Api.guardarEspacio(widget.espacio == null ? null : '${widget.espacio!['id']}',
          codigo: _codigo.text.trim().toUpperCase(), descripcion: _desc.text.trim(), activo: _activo);
      if (!mounted) return;
      avisoOk(context, widget.espacio == null ? 'Espacio creado' : 'Espacio actualizado');
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.espacio == null ? 'Nuevo espacio' : 'Editar espacio', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(
            controller: _codigo,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Código (ej. A3, RACK-2)'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Descripción')),
          if (widget.espacio != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Espacio activo'),
              subtitle: const Text('Un espacio inactivo no recibe material'),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _enviando ? null : _guardar, child: const Text('Guardar')),
        ],
      ),
    );
  }
}
