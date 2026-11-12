import 'package:alumvid_admin_desktop/models/retazo_pieza.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Retazos y cortes: piezas de aluminio y vidrio reutilizables.
class RetazosScreen extends StatefulWidget {
  const RetazosScreen({super.key});

  @override
  State<RetazosScreen> createState() => _RetazosScreenState();
}

class _RetazosScreenState extends State<RetazosScreen> {
  String _q = '';
  String _tipo = '';
  bool _cargando = true;
  String? _error;
  List<ProductoRetazo> _items = [];

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
      final r = await adm.ApiService.obtenerProductosRetazos(q: _q, size: 100);
      // El servicio lista todo el catálogo; solo los productos con formato
      // (perfiles y vidrios) tienen piezas consultables.
      if (mounted) setState(() => _items = r.where((p) => p.piecesManaged).toList());
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<ProductoRetazo> get _filtrados => _tipo.isEmpty
      ? _items
      : _items.where((p) => (p.kind ?? '').toUpperCase() == _tipo).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retazos'),
        actions: [
          IconButton(
            tooltip: 'Abrir gestión completa en el navegador',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => abrirPortal(context, 'retazos'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: CampoBusqueda(
              hint: 'Buscar perfil o vidrio',
              onChanged: (v) {
                _q = v;
                _cargar();
              },
            ),
          ),
          FiltrosChips<String>(
            opciones: const {'': 'Todos', 'ALUMINIO': 'Aluminio', 'VIDRIO': 'Vidrio'},
            seleccion: _tipo,
            onSeleccion: (v) => setState(() => _tipo = v),
          ),
          const SizedBox(height: 8),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const CargandoLista();
    if (_error != null) return VistaError(mensaje: _error!, onReintentar: _cargar);
    final items = _filtrados;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: items.isEmpty
          ? const VistaVacia(
              icono: Icons.content_cut,
              titulo: 'Sin productos con retazos',
              mensaje: 'Solo aparecen productos que gestionan piezas.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final p = items[i];
                final vidrio = (p.kind ?? '').toUpperCase() == 'VIDRIO';
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: (vidrio ? AppColors.info : AppColors.textMuted)
                          .withValues(alpha: 0.16),
                      child: Icon(
                        vidrio ? Icons.window_outlined : Icons.straighten,
                        color: vidrio ? AppColors.info : AppColors.text,
                      ),
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${p.code} · stock ${fmtNum(p.stock)}',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => _PiezasScreen(producto: p)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PiezasScreen extends StatefulWidget {
  const _PiezasScreen({required this.producto});
  final ProductoRetazo producto;

  @override
  State<_PiezasScreen> createState() => _PiezasScreenState();
}

class _PiezasScreenState extends State<_PiezasScreen> {
  static const _estados = {
    'DISPONIBLE': 'Disponibles',
    'PREPARADO': 'Preparadas',
    'TRANSFORMADO': 'Transformadas',
    'ENTREGADO': 'Entregadas',
    'CONSUMIDO': 'Consumidas',
    'DESCARTADO': 'Descartadas',
  };
  String _estado = 'DISPONIBLE';
  bool _cargando = true;
  String? _error;
  List<PiezaRetazo> _piezas = [];

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
      final r = await adm.ApiService.obtenerPiezasRetazo(widget.producto.id, state: _estado);
      if (mounted) setState(() => _piezas = r);
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.producto.name)),
      body: Column(
        children: [
          FiltrosChips<String>(
            opciones: _estados,
            seleccion: _estado,
            onSeleccion: (v) {
              setState(() => _estado = v);
              _cargar();
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _cargando
                ? const CargandoLista()
                : _error != null
                ? VistaError(mensaje: _error!, onReintentar: _cargar)
                : RefreshIndicator(
                    onRefresh: _cargar,
                    child: _piezas.isEmpty
                        ? VistaVacia(
                            icono: Icons.content_cut,
                            titulo: 'Sin piezas ${_estados[_estado]!.toLowerCase()}',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _piezas.length + 1,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              if (i == 0) {
                                return Text(
                                  '${_piezas.length} piezas',
                                  style: const TextStyle(color: AppColors.textMuted),
                                );
                              }
                              final pz = _piezas[i - 1];
                              return Card(
                                child: ListTile(
                                  leading: const Icon(Icons.crop_free),
                                  title: Text(
                                    pz.dimensionesTexto,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    [
                                      if ((pz.code ?? '').isNotEmpty) pz.code!,
                                      if ((pz.location ?? '').isNotEmpty) 'Ubicación ${pz.location}',
                                    ].join(' · '),
                                    style: const TextStyle(color: AppColors.textMuted),
                                  ),
                                  trailing: EstadoChip(pz.state),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
