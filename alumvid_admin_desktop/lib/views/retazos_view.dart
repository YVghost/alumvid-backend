import 'package:flutter/material.dart';
import '../models/retazo_pieza.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class RetazosView extends StatefulWidget {
  const RetazosView({super.key});

  @override
  State<RetazosView> createState() => _RetazosViewState();
}

class _RetazosViewState extends State<RetazosView> {
  List<ProductoRetazo> _productos = [];
  ProductoRetazo? _productoSeleccionado;
  List<PiezaRetazo> _piezas = [];
  bool _cargando = true;
  bool _cargandoPiezas = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  Future<void> _cargarProductos() async {
    setState(() => _cargando = true);
    final list = await ApiService.obtenerProductosRetazos(q: _searchCtrl.text.trim());
    if (!mounted) return;
    setState(() {
      _productos = list;
      _cargando = false;
      if (list.isNotEmpty && _productoSeleccionado == null) {
        _seleccionarProducto(list.first);
      }
    });
  }

  Future<void> _seleccionarProducto(ProductoRetazo prod) async {
    setState(() {
      _productoSeleccionado = prod;
      _cargandoPiezas = true;
    });
    final piezas = await ApiService.obtenerPiezasRetazo(prod.id);
    if (!mounted) return;
    setState(() {
      _piezas = piezas;
      _cargandoPiezas = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bgDark,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gestión de Retazos y Piezas de Corte',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Microservicio Retazos (Puerto 8084) • Trazabilidad milimétrica de perfiles de aluminio y planchas de vidrio',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Actualizar'),
                onPressed: _cargarProductos,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Contenedor Split: Lista de Productos a la izquierda, Piezas Físicas a la derecha
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Columna Izquierda: Catálogo de Productos con Piezas
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Materiales Configurables',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Buscar material...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.textMuted),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                          ),
                          onSubmitted: (_) => _cargarProductos(),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _cargando
                              ? const Center(child: CircularProgressIndicator())
                              : _productos.isEmpty
                                  ? const Center(
                                      child: Text('No hay materiales con piezas', style: TextStyle(color: Colors.white60)),
                                    )
                                  : ListView.builder(
                                      itemCount: _productos.length,
                                      itemBuilder: (context, idx) {
                                        final prod = _productos[idx];
                                        final isSel = _productoSeleccionado?.id == prod.id;
                                        final bool isAluminio = prod.kind == 'ALUMINIO' || prod.name.toUpperCase().contains('ALUMINIO');

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          decoration: BoxDecoration(
                                            color: isSel ? AppTheme.primary.withValues(alpha: 0.18) : const Color(0xFF0F172A),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: isSel ? AppTheme.primaryLight : const Color(0xFF1E293B)),
                                          ),
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            leading: Icon(
                                              isAluminio ? Icons.view_column_rounded : Icons.crop_square_rounded,
                                              color: isAluminio ? const Color(0xFF38BDF8) : const Color(0xFF34D399),
                                              size: 24,
                                            ),
                                            title: Text(
                                              prod.name,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              'Código: ${prod.code} • Stock: ${prod.stock} ${prod.unit}',
                                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                            ),
                                            onTap: () => _seleccionarProducto(prod),
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Columna Derecha: Detalle de Piezas y Retazos Disponibles
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _productoSeleccionado != null
                                  ? 'Piezas Físicas Disponibles: ${_productoSeleccionado!.name}'
                                  : 'Piezas Físicas en Bodega',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            if (_piezas.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  '${_piezas.length} disponibles para corte',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        const Divider(color: Color(0xFF1E293B), height: 20),
                        Expanded(
                          child: _cargandoPiezas
                              ? const Center(child: CircularProgressIndicator())
                              : _piezas.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.content_cut_rounded, size: 54, color: AppTheme.textMuted.withValues(alpha: 0.4)),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'No hay retazos individuales registrados para este material',
                                            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Los retazos se generan automáticamente al realizar cortes en taller o registrar sobrantes.',
                                            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _piezas.length,
                                      itemBuilder: (context, idx) {
                                        final p = _piezas[idx];
                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F172A),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFF1E293B)),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primary.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Icon(Icons.straighten_rounded, color: AppTheme.primaryLight, size: 20),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      p.dimensionesTexto,
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Ubicación: ${p.location ?? "Sin asignar"} • Estado: ${p.state}',
                                                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.statusCompletada.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'LISTA PARA CORTE',
                                                  style: TextStyle(color: AppTheme.statusCompletada, fontWeight: FontWeight.bold, fontSize: 10),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

