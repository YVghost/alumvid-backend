import 'package:flutter/material.dart';

import '../../models/producto.dart';
import '../../services/api_service.dart';
import '../../shared/adaptable.dart';
import '../../shared/permisos.dart';
import '../../shared/tema.dart';
import '../../shared/ui.dart';
import 'producto_detalle.dart';
import 'producto_form.dart';

const categoriasProducto = ['VIDRIO', 'ALUMINIO', 'ACCESORIOS', 'VYNIL', 'ACRILICO', 'ACERO INOXIDABLE'];
const unidadesProducto = <String, String>{
  'UNIDAD': 'Unidad',
  'METRO': 'Metro lineal (m)',
  'METRO_CUADRADO': 'Metro cuadrado (m²)',
  'ROLLO': 'Rollo',
  'KILOGRAMO': 'Kilogramo (kg)',
  'LITRO': 'Litro (L)',
};

String unidadCorta(String u) => switch (u) {
  'METRO' => 'm',
  'METRO_CUADRADO' => 'm²',
  'KILOGRAMO' => 'kg',
  'LITRO' => 'L',
  'ROLLO' => 'rollos',
  _ => 'unid.',
};

enum _Filtro { todos, stockBajo, porMedida, inactivos }

/// Inventario: existencias por material, con el detalle de unidades y piezas.
class InventarioModulo extends StatefulWidget {
  const InventarioModulo({super.key, required this.permisos});
  final Permisos permisos;

  @override
  State<InventarioModulo> createState() => _InventarioModuloState();
}

class _InventarioModuloState extends State<InventarioModulo> {
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
      _cargando = _items.isEmpty;
      _error = null;
    });
    try {
      final r = await ApiService.obtenerProductos(
        q: _q,
        category: _categoria,
        lowStock: _filtro == _Filtro.stockBajo,
        includeInactive: _filtro == _Filtro.inactivos,
        size: 100,
      );
      var items = (r['items'] as List).cast<Producto>();
      if (_filtro == _Filtro.inactivos) items = items.where((p) => !p.active).toList();
      if (_filtro == _Filtro.porMedida) items = items.where((p) => p.piecesManaged).toList();
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
    await abrirPanel(context, (_) => ProductoDetalle(producto: p, permisos: widget.permisos), ancho: 640);
    _cargar();
  }

  Future<void> _nuevo() async {
    final ok = await abrirPanel<bool>(context, (_) => const ProductoForm());
    if (ok == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Categoría',
            icon: Badge(isLabelVisible: _categoria.isNotEmpty, smallSize: 8, child: const Icon(Icons.filter_list)),
            initialValue: _categoria,
            onSelected: (v) {
              setState(() => _categoria = v);
              _cargar();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('Todas las categorías')),
              for (final c in categoriasProducto) PopupMenuItem(value: c, child: Text(humanizar(c))),
            ],
          ),
        ],
      ),
      floatingActionButton: widget.permisos.editaCatalogo
          ? FloatingActionButton.extended(
              heroTag: 'nuevo-producto',
              onPressed: _nuevo,
              icon: const Icon(Icons.add),
              label: const Text('Producto'),
            )
          : null,
      body: AnchoLegible(
        child: Column(
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
                _Filtro.porMedida: 'Perfiles y vidrios',
                if (widget.permisos.editaCatalogo) _Filtro.inactivos: 'Inactivos',
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
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_items.length} de $_total productos${_categoria.isEmpty ? '' : ' · ${humanizar(_categoria)}'}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ),
              ),
            Expanded(child: _cuerpo()),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const CargandoLista();
    if (_error != null) return VistaError(mensaje: _error!, onReintentar: _cargar);
    return RefreshIndicator(
      onRefresh: _cargar,
      child: _items.isEmpty
          ? const VistaVacia(icono: Icons.inventory_2_outlined, titulo: 'Sin productos', mensaje: 'Prueba con otra búsqueda o filtro.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => ProductoCard(producto: _items[i], onTap: () => _abrir(_items[i])),
            ),
    );
  }
}

class StockBadge extends StatelessWidget {
  const StockBadge(this.p, {super.key, this.grande = false});
  final Producto p;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final color = p.isAgotado ? AppColors.danger : p.isStockBajo ? AppColors.warning : AppColors.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(fmtNum(p.stock), style: TextStyle(color: color, fontSize: grande ? 34 : 20, fontWeight: FontWeight.w800, height: 1)),
        const SizedBox(height: 2),
        Text(p.piecesManaged ? 'unid. equiv.' : unidadCorta(p.unit), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ],
    );
  }
}

class ProductoCard extends StatelessWidget {
  const ProductoCard({super.key, required this.producto, required this.onTap});
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
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.active ? AppColors.text : AppColors.textDim),
                    ),
                    const SizedBox(height: 4),
                    Text([p.code, humanizar(p.category)].join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    if (p.piecesManaged || p.isAgotado || p.isStockBajo || !p.active) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (p.piecesManaged) const EstadoChip('INFO', texto: 'Por medida', color: AppColors.info),
                          if (!p.active) const EstadoChip('INACTIVO', texto: 'Inactivo'),
                          if (p.isAgotado) const EstadoChip('AGOTADO', texto: 'Agotado'),
                          if (p.isStockBajo) EstadoChip('EN_CURSO', texto: 'Bajo mínimo (${fmtNum(p.minStock)})'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StockBadge(p),
            ],
          ),
        ),
      ),
    );
  }
}
