import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import '../models/espacio_ubicacion.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class UbicacionesView extends StatefulWidget {
  const UbicacionesView({super.key});

  @override
  State<UbicacionesView> createState() => _UbicacionesViewState();
}

class _UbicacionesViewState extends State<UbicacionesView> {
  List<EspacioUbicacion> _espacios = [];
  EspacioUbicacion? _espacioSeleccionado;
  Map<String, dynamic> _contenidoEspacio = {};
  bool _cargando = true;
  bool _cargandoContenido = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargarEspacios();
  }

  Future<void> _cargarEspacios() async {
    setState(() => _cargando = true);
    try {
      final list = await ApiService.obtenerEspaciosUbicacion(
        q: _searchCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _espacios = list;
        _cargando = false;
        if (list.isNotEmpty && _espacioSeleccionado == null) {
          _seleccionarEspacio(list.first);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cargar: $e')));
    }
  }

  Future<void> _seleccionarEspacio(EspacioUbicacion esp) async {
    setState(() {
      _espacioSeleccionado = esp;
      _cargandoContenido = true;
    });
    try {
      final cont = await ApiService.obtenerContenidoEspacio(esp.id);
      if (!mounted) return;
      setState(() {
        _contenidoEspacio = {
          ...cont,
          'items': [
            ...((cont['products'] as List?) ?? []).map((p) => {...p as Map, 'productName': p['name']}),
            ...((cont['pieces'] as List?) ?? []).map((p) => {...p as Map, 'productName': '${p['name']} (${p['state']})', 'quantity': 1}),
          ],
        };
        _cargandoContenido = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoContenido = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo consultar: $e')));
    }
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
                    'Distribución Física de Bodega & Ubicaciones',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Microservicio Ubicaciones (Puerto 8086) • Estantes compartidos, compartimentos y traslados sin afectar stock',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir gestión completa'),
                onPressed: () async {
                  final host = await ApiService.getBaseHost();
                  await launchUrl(
                    Uri.parse('$host/ubicaciones/'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Actualizar'),
                onPressed: _cargarEspacios,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Layout en 2 Paneles: Grilla de Estantes a la izquierda, Contenido a la derecha
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Columna Izquierda: Grilla de Estantes (A1, A2, B3, etc.)
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
                            const Text(
                              'Compartimentos & Estantes Físicos',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${_espacios.length} ubicaciones configuradas',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Filtrar ubicación (ej. A1, B3)...',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: AppTheme.textMuted,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                              horizontal: 10,
                            ),
                          ),
                          onSubmitted: (_) => _cargarEspacios(),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _cargando
                              ? const Center(child: CircularProgressIndicator())
                              : _espacios.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No hay estantes registrados',
                                    style: TextStyle(color: Colors.white60),
                                  ),
                                )
                              : GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                        childAspectRatio: 1.35,
                                      ),
                                  itemCount: _espacios.length,
                                  itemBuilder: (context, idx) {
                                    final esp = _espacios[idx];
                                    final isSel =
                                        _espacioSeleccionado?.id == esp.id;

                                    return InkWell(
                                      onTap: () => _seleccionarEspacio(esp),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isSel
                                              ? AppTheme.primary.withValues(
                                                  alpha: 0.2,
                                                )
                                              : const Color(0xFF0F172A),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: isSel
                                                ? AppTheme.primaryLight
                                                : const Color(0xFF1E293B),
                                            width: isSel ? 1.8 : 1.0,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  esp.code,
                                                  style: TextStyle(
                                                    color: isSel
                                                        ? AppTheme.primaryLight
                                                        : Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 18,
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.grid_view_rounded,
                                                  size: 16,
                                                  color: isSel
                                                      ? AppTheme.primaryLight
                                                      : AppTheme.textMuted,
                                                ),
                                              ],
                                            ),
                                            Text(
                                              esp.description ??
                                                  'Estante estándar',
                                              style: const TextStyle(
                                                color: AppTheme.textMuted,
                                                fontSize: 11,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
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

                // Columna Derecha: Detalle de Contenido del Estante Seleccionado
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
                        Text(
                          _espacioSeleccionado != null
                              ? 'Contenido en ${_espacioSeleccionado!.code}'
                              : 'Contenido del Compartimento',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (_espacioSeleccionado?.description != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _espacioSeleccionado!.description!,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const Divider(color: Color(0xFF1E293B), height: 20),
                        Expanded(
                          child: _cargandoContenido
                              ? const Center(child: CircularProgressIndicator())
                              : _espacioSeleccionado == null
                              ? const Center(
                                  child: Text(
                                    'Selecciona una ubicación para ver su inventario',
                                    style: TextStyle(color: Colors.white60),
                                  ),
                                )
                              : ListView(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFF1E293B),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.warehouse_rounded,
                                            color: Color(0xFF38BDF8),
                                            size: 28,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Estante ${_espacioSeleccionado!.code}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                const Text(
                                                  'Espacio físico activo y verificado en base de datos',
                                                  style: TextStyle(
                                                    color: AppTheme.textMuted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Artículos Almacenados:',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Lista de items de contenidos
                                    ...((_contenidoEspacio['items']
                                                as List<dynamic>?) ??
                                            [])
                                        .map((it) {
                                          return Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0F172A),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  it['product_name'] ??
                                                      it['productName'] ??
                                                      'Material',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                Text(
                                                  '${it['quantity'] ?? 0} unid.',
                                                  style: const TextStyle(
                                                    color:
                                                        AppTheme.primaryLight,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                    if (((_contenidoEspacio['items']
                                                as List<dynamic>?) ??
                                            [])
                                        .isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 20,
                                        ),
                                        child: Center(
                                          child: Text(
                                            'Este compartimento no tiene productos asignados actualmente.',
                                            style: TextStyle(
                                              color: AppTheme.textMuted,
                                              fontSize: 11,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
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
