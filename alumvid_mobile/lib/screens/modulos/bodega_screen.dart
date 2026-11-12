import 'package:alumvid_admin_desktop/models/espacio_ubicacion.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Ubicaciones físicas de bodega: racks y compartimentos con su contenido.
class BodegaScreen extends StatefulWidget {
  const BodegaScreen({super.key});

  @override
  State<BodegaScreen> createState() => _BodegaScreenState();
}

class _BodegaScreenState extends State<BodegaScreen> {
  String _q = '';
  bool _cargando = true;
  String? _error;
  List<EspacioUbicacion> _items = [];

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
      final r = await adm.ApiService.obtenerEspaciosUbicacion(q: _q, size: 100);
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bodega'),
        actions: [
          IconButton(
            tooltip: 'Abrir gestión completa en el navegador',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => abrirPortal(context, 'ubicaciones'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: CampoBusqueda(
              hint: 'Buscar espacio (ej. A3)',
              onChanged: (v) {
                _q = v;
                _cargar();
              },
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
          ? const VistaVacia(icono: Icons.grid_view, titulo: 'Sin espacios registrados')
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
              ),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final e = _items[i];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _contenido(e),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.shelves,
                                color: e.active ? AppColors.primaryLight : AppColors.textDim,
                              ),
                              const Spacer(),
                              if (!e.active) const EstadoChip('INACTIVO', texto: 'Inactivo'),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            e.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.description ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _contenido(EspacioUbicacion e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => _ContenidoEspacio(espacio: e, scroll: scroll),
      ),
    );
  }
}

class _ContenidoEspacio extends StatefulWidget {
  const _ContenidoEspacio({required this.espacio, required this.scroll});
  final EspacioUbicacion espacio;
  final ScrollController scroll;

  @override
  State<_ContenidoEspacio> createState() => _ContenidoEspacioState();
}

class _ContenidoEspacioState extends State<_ContenidoEspacio> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _productos = [];
  List<Map<String, dynamic>> _piezas = [];

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
      final c = await adm.ApiService.obtenerContenidoEspacio(widget.espacio.id);
      List<Map<String, dynamic>> lista(String k) => ((c[k] as List?) ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
      if (mounted) {
        setState(() {
          _productos = lista('products');
          _piezas = lista('pieces');
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _dim(Map<String, dynamic> p) {
    final l = double.tryParse('${p['length_m'] ?? ''}');
    final w = double.tryParse('${p['width_cm'] ?? ''}');
    final h = double.tryParse('${p['height_cm'] ?? ''}');
    if (l != null && l > 0) return '${fmtNum(l)} m';
    if (w != null && h != null) return '${fmtNum(w)} × ${fmtNum(h)} cm';
    return 'Pieza';
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.espacio;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Text(e.code, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if ((e.description ?? '').isNotEmpty)
          Text(e.description!, style: const TextStyle(color: AppColors.textMuted)),
        if (_cargando)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: AppColors.danger),
                title: Text(_error!),
                trailing: TextButton(onPressed: _cargar, child: const Text('Reintentar')),
              ),
            ),
          )
        else if (_productos.isEmpty && _piezas.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(
              child: Text('Este espacio está vacío', style: TextStyle(color: AppColors.textMuted)),
            ),
          )
        else ...[
          if (_productos.isNotEmpty) ...[
            SeccionTitulo('Productos (${_productos.length})'),
            Card(
              child: Column(
                children: [
                  for (final p in _productos)
                    ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text('${p['name'] ?? p['productName'] ?? 'Producto'}'),
                      subtitle: Text('${p['code'] ?? ''}', style: const TextStyle(color: AppColors.textMuted)),
                      trailing: Text(
                        fmtNum(double.tryParse('${p['quantity']}') ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_piezas.isNotEmpty) ...[
            SeccionTitulo('Piezas de retazo (${_piezas.length})'),
            Card(
              child: Column(
                children: [
                  for (final p in _piezas)
                    ListTile(
                      leading: const Icon(Icons.content_cut),
                      title: Text('${p['name'] ?? 'Pieza'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${_dim(p)}${p['reserved'] == true ? ' · reservada' : ''}',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      trailing: EstadoChip('${p['state'] ?? ''}'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
