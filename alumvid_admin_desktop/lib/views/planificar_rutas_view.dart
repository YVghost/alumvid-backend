import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/chofer.dart';
import '../models/despacho.dart';
import '../models/ruta.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/agregar_parada_dialog.dart';
import '../widgets/epod_dialog.dart';

class PlanificarRutasView extends StatefulWidget {
  final List<Ruta> rutas;
  final List<Ruta> todasLasRutas;
  final List<Chofer> choferes;
  final DateTimeRange rangoFiltro;
  final ValueChanged<DateTimeRange> onCambiarRangoFiltro;
  final VoidCallback onRefresh;

  const PlanificarRutasView({
    super.key,
    required this.rutas,
    required this.todasLasRutas,
    required this.choferes,
    required this.rangoFiltro,
    required this.onCambiarRangoFiltro,
    required this.onRefresh,
  });

  @override
  State<PlanificarRutasView> createState() => _PlanificarRutasViewState();
}

class _PlanificarRutasViewState extends State<PlanificarRutasView> {
  // Ruta seleccionada / expandida
  String? _expandedRutaId;
  Ruta? _rutaSeleccionada;

  // Formulario Crear o Asignar Ruta
  final _codigoRutaCtrl = TextEditingController(text: 'Ruta 10');
  String? _choferCrearRutaId;
  bool _creandoRuta = false;

  // Filtro de búsqueda en la lista de rutas
  final _searchCtrl = TextEditingController();
  String _filtroTexto = '';

  // Mini-mapa Punto de Entrega
  final MapController _miniMapController = MapController();
  LatLng _mapCenter = const LatLng(-0.1807, -78.4678); // Quito (La Carolina / Centro)
  double _mapZoom = 13.0;

  @override
  void initState() {
    super.initState();
    _proponerSiguienteCodigo();
    if (widget.rutas.isNotEmpty) {
      _expandedRutaId = widget.rutas.first.id;
      _rutaSeleccionada = widget.rutas.first;
      _actualizarCentroMapaParaRuta(_rutaSeleccionada);
    }
  }

  @override
  void didUpdateWidget(covariant PlanificarRutasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_expandedRutaId != null) {
      final act = widget.rutas.where((r) => r.id == _expandedRutaId).toList();
      if (act.isNotEmpty) {
        _rutaSeleccionada = act.first;
      }
    }
  }

  @override
  void dispose() {
    _codigoRutaCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _proponerSiguienteCodigo() {
    int maxNum = 0;
    for (final r in widget.todasLasRutas) {
      final match = RegExp(r'\d+').firstMatch(r.codigoRuta);
      if (match != null) {
        final val = int.tryParse(match.group(0)!) ?? 0;
        if (val > maxNum) maxNum = val;
      }
    }
    _codigoRutaCtrl.text = 'Ruta ${maxNum + 1}';
  }

  void _actualizarCentroMapaParaRuta(Ruta? ruta) {
    if (ruta != null && ruta.paradas.isNotEmpty) {
      final p = ruta.paradas.first;
      _mapCenter = LatLng(p.latitud, p.longitud);
      _mapZoom = 14.0;
      try {
        _miniMapController.move(_mapCenter, _mapZoom);
      } catch (_) {}
    }
  }

  Future<void> _crearOAsignarRuta() async {
    final codigo = _codigoRutaCtrl.text.trim();
    if (codigo.isEmpty) {
      AppToast.warning(context, 'Ingrese el nombre de la ruta');
      return;
    }

    setState(() => _creandoRuta = true);
    try {
      final nueva = await ApiService.crearRutaSimple(
        codigoRuta: codigo,
        choferId: _choferCrearRutaId,
      );

      if (!mounted) return;
      AppToast.success(context, 'Ruta "$codigo" creada y disponible en la lista.');

      _proponerSiguienteCodigo();
      widget.onRefresh();

      setState(() {
        _creandoRuta = false;
        _expandedRutaId = nueva.id;
        _rutaSeleccionada = nueva;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _creandoRuta = false);
      AppToast.error(context, 'Error al crear ruta: $e');
    }
  }

  void _abrirDialogoAgregarParada(Ruta ruta) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AgregarParadaDialog(
        ruta: ruta,
        onParadaAgregada: () {
          widget.onRefresh();
          setState(() {
            _expandedRutaId = ruta.id;
          });
        },
      ),
    );
  }

  Future<void> _iniciarRuta(Ruta ruta) async {
    try {
      final act = await ApiService.iniciarRuta(ruta.id);
      if (!mounted) return;
      AppToast.success(context, 'Ruta "${act.codigoRuta}" puesta EN CURSO.');
      widget.onRefresh();
      setState(() {
        _rutaSeleccionada = act;
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Error al iniciar ruta: $e');
    }
  }

  Future<void> _eliminarRuta(Ruta ruta) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        title: const Text('Eliminar Ruta', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('¿Desea eliminar la ruta "${ruta.codigoRuta}" y sus paradas?', style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (conf == true) {
      try {
        await ApiService.eliminarRuta(ruta.id);
        if (!mounted) return;
        AppToast.success(context, 'Ruta eliminada.');
        if (_expandedRutaId == ruta.id) {
          setState(() {
            _expandedRutaId = null;
            _rutaSeleccionada = null;
          });
        }
        widget.onRefresh();
      } catch (e) {
        if (!mounted) return;
        AppToast.error(context, 'Error al eliminar ruta: $e');
      }
    }
  }

  Future<void> _eliminarParada(Ruta ruta, Despacho parada) async {
    try {
      final act = await ApiService.eliminarDestinoRuta(ruta.id, parada.id);
      if (!mounted) return;
      AppToast.success(context, 'Parada eliminada de la ruta.');
      widget.onRefresh();
      setState(() => _rutaSeleccionada = act);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Error al eliminar parada: $e');
    }
  }

  Future<void> _mostrarSelectorFecha() async {
    final ahora = DateTime.now();
    final opcion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Filtrar Rutas por Fecha', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              const Divider(color: Color(0xFF1E293B)),
              ListTile(
                leading: const Icon(Icons.today, color: Color(0xFF38BDF8)),
                title: const Text('Hoy', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'HOY'),
              ),
              ListTile(
                leading: const Icon(Icons.history, color: Color(0xFF38BDF8)),
                title: const Text('Ayer', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'AYER'),
              ),
              ListTile(
                leading: const Icon(Icons.date_range, color: Color(0xFF38BDF8)),
                title: const Text('Últimos 7 días', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, '7DIAS'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month, color: Color(0xFF38BDF8)),
                title: const Text('Todo el Mes', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'MES'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar, color: Color(0xFF38BDF8)),
                title: const Text('Elegir Rango Personalizado...', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'CUSTOM'),
              ),
            ],
          ),
        ),
      ),
    );

    if (opcion == null) return;

    if (opcion == 'HOY') {
      widget.onCambiarRangoFiltro(DateTimeRange(start: ahora, end: ahora));
    } else if (opcion == 'AYER') {
      final ayer = ahora.subtract(const Duration(days: 1));
      widget.onCambiarRangoFiltro(DateTimeRange(start: ayer, end: ayer));
    } else if (opcion == '7DIAS') {
      widget.onCambiarRangoFiltro(DateTimeRange(start: ahora.subtract(const Duration(days: 7)), end: ahora));
    } else if (opcion == 'MES') {
      final inicioMes = DateTime(ahora.year, ahora.month, 1);
      widget.onCambiarRangoFiltro(DateTimeRange(start: inicioMes, end: ahora));
    } else if (opcion == 'CUSTOM') {
      if (!mounted) return;
      final picked = await showDateRangePicker(
        context: context,
        initialDateRange: widget.rangoFiltro,
        firstDate: DateTime(2025, 1, 1),
        lastDate: DateTime.now().add(const Duration(days: 30)),
        builder: (ctx, child) {
          return Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: AppTheme.primary,
                onPrimary: Colors.white,
                surface: Color(0xFF131B2E),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        widget.onCambiarRangoFiltro(picked);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cálculo de métricas
    final int totalRutas = widget.rutas.length;
    int exitosas = 0;
    int canceladas = 0;
    for (final r in widget.rutas) {
      for (final p in r.paradas) {
        if (p.isEntregado) exitosas++;
        if (p.isNoEntregado) canceladas++;
      }
      if (r.estado == 'CANCELADA') canceladas++;
    }

    final bool esHoy = widget.rangoFiltro.start.day == DateTime.now().day &&
        widget.rangoFiltro.start.month == DateTime.now().month &&
        widget.rangoFiltro.start.year == DateTime.now().year &&
        widget.rangoFiltro.end.day == DateTime.now().day &&
        widget.rangoFiltro.end.month == DateTime.now().month &&
        widget.rangoFiltro.end.year == DateTime.now().year;

    final String diaNumero = esHoy
        ? widget.rangoFiltro.start.day.toString()
        : DateFormat('dd MMM').format(widget.rangoFiltro.start);

    // Filtrado de rutas por texto de búsqueda
    final rutasFiltradas = widget.rutas.where((r) {
      if (_filtroTexto.isEmpty) return true;
      final q = _filtroTexto.toLowerCase();
      final cod = r.codigoRuta.toLowerCase();
      final chofer = (r.choferNombre ?? '').toLowerCase();
      return cod.contains(q) || chofer.contains(q);
    }).toList();

    return Container(
      color: const Color(0xFF070B14),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==========================================
            // 1. FILA DE 4 TARJETAS DE ESTADO SUPERIORES
            // ==========================================
            _buildMetricCardsRow(
              diaTexto: esHoy ? 'Hoy' : 'Periodo',
              diaNumero: diaNumero,
              rutasTotales: totalRutas,
              entregasExitosas: exitosas,
              entregasCanceladas: canceladas,
            ),
            const SizedBox(height: 18),

            // ==========================================
            // 2. SECCIÓN MEDIA: 2 COLUMNAS (CREAR + MAPA)
            // ==========================================
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 850;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: _buildCardCrearOAsignar()),
                      const SizedBox(width: 18),
                      Expanded(flex: 4, child: _buildCardPuntoEntrega()),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildCardCrearOAsignar(),
                      const SizedBox(height: 16),
                      _buildCardPuntoEntrega(),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 18),

            // ==========================================
            // 3. SECCIÓN INFERIOR: RUTAS CREADAS (ACORDEÓN)
            // ==========================================
            _buildCardRutasCreadas(rutasFiltradas),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // WIDGET: FILA DE 4 TARJETAS DE ESTADO (MOCKUP)
  // ==========================================
  Widget _buildMetricCardsRow({
    required String diaTexto,
    required String diaNumero,
    required int rutasTotales,
    required int entregasExitosas,
    required int entregasCanceladas,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return GridView.count(
          crossAxisCount: isWide ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: isWide ? 2.5 : 2.2,
          children: [
            // Tarjeta 1: Fecha / Hoy
            InkWell(
              onTap: _mostrarSelectorFecha,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF101728),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A8A).withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(diaTexto, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                diaNumero,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8), size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Tarjeta 2: Rutas Totales
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF101728),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D4ED8).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.alt_route_rounded, color: Color(0xFF60A5FA), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Rutas Totales', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                        const SizedBox(height: 2),
                        Text(
                          '$rutasTotales',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tarjeta 3: Entregas Exitosas
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF101728),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF065F46).withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Entregas Exitosas', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                        const SizedBox(height: 2),
                        Text(
                          '$entregasExitosas',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tarjeta 4: Entregas Canceladas
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF101728),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF991B1B).withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Entregas Canceladas', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                        const SizedBox(height: 2),
                        Text(
                          '$entregasCanceladas',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // WIDGET: 1. CREAR O ASIGNAR RUTA
  // ==========================================
  Widget _buildCardCrearOAsignar() {
    final Set<String> idsVistos = {};
    final choferesUnicos = widget.choferes.where((c) => idsVistos.add(c.id)).toList();
    final bool choferCrearValido = _choferCrearRutaId == null || choferesUnicos.any((c) => c.id == _choferCrearRutaId);
    final String? valorChofer = choferCrearValido ? _choferCrearRutaId : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101728),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera: Círculo con 1 + Título
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Color(0xFF1D72FE),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Crear o Asignar Ruta',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Campos: Nombre de la Ruta + Chofer Asignado
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 420;
              if (isWide) {
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Nombre de la Ruta', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                          const SizedBox(height: 6),
                          Container(
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF090E1A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF1E293B)),
                            ),
                            child: TextField(
                              controller: _codigoRutaCtrl,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: InputBorder.none,
                                hintText: 'Ej. Ruta 10',
                                hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Chofer Asignado', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                          const SizedBox(height: 6),
                          Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF090E1A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF1E293B)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true,
                                value: valorChofer,
                                dropdownColor: const Color(0xFF101728),
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8)),
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('-- Sin asignar --', style: TextStyle(color: Color(0xFF94A3B8))),
                                  ),
                                  ...choferesUnicos.map((c) => DropdownMenuItem<String?>(
                                    value: c.id,
                                    child: Text(
                                      '${c.nombre} (${c.estadoDisponibilidad})',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  )),
                                ],
                                onChanged: (val) => setState(() => _choferCrearRutaId = val),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nombre de la Ruta', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    const SizedBox(height: 6),
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF090E1A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: TextField(
                        controller: _codigoRutaCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: InputBorder.none,
                          hintText: 'Ej. Ruta 10',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Chofer Asignado', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    const SizedBox(height: 6),
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF090E1A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          value: valorChofer,
                          dropdownColor: const Color(0xFF101728),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('-- Sin asignar --')),
                            ...choferesUnicos.map((c) => DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text('${c.nombre} (${c.estadoDisponibilidad})'),
                            )),
                          ],
                          onChanged: (val) => setState(() => _choferCrearRutaId = val),
                        ),
                      ),
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 16),

          // Botón Azul: + Crear / Asignar
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D72FE),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: _creandoRuta ? null : _crearOAsignarRuta,
              child: _creandoRuta
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('+ Crear / Asignar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // WIDGET: PUNTO DE ENTREGA (MINI MAPA)
  // ==========================================
  Widget _buildCardPuntoEntrega() {
    // Marcadores del mini-mapa
    final List<Marker> marcadores = [];

    if (_rutaSeleccionada != null && _rutaSeleccionada!.paradas.isNotEmpty) {
      for (final p in _rutaSeleccionada!.paradas) {
        marcadores.add(
          Marker(
            point: LatLng(p.latitud, p.longitud),
            width: 38,
            height: 38,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1D72FE),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: const Icon(Icons.location_on, color: Colors.white, size: 22),
            ),
          ),
        );
      }
    } else {
      marcadores.add(
        Marker(
          point: _mapCenter,
          width: 36,
          height: 36,
          child: const Icon(Icons.location_on, color: Color(0xFF1D72FE), size: 36),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101728),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text('Punto de Entrega', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF94A3B8)),
                tooltip: 'Centrar en mapa general',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  _miniMapController.move(_mapCenter, 14.0);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: FlutterMap(
                mapController: _miniMapController,
                options: MapOptions(
                  initialCenter: _mapCenter,
                  initialZoom: _mapZoom,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                  ),
                  MarkerLayer(markers: marcadores),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // WIDGET: 3. RUTAS CREADAS (ACORDEÓN DESPLEGABLE)
  // ==========================================
  Widget _buildCardRutasCreadas(List<Ruta> rutas) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101728),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera: Icono lista + Título + Buscador
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.format_list_bulleted_rounded, color: Color(0xFF38BDF8), size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Rutas Creadas (${rutas.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                  ),
                ],
              ),
              // Input Buscador
              Container(
                width: 200,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF090E1A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  onChanged: (val) => setState(() => _filtroTexto = val.trim()),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.search, size: 16, color: Color(0xFF64748B)),
                    hintText: 'Buscar ruta...',
                    hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Lista de Rutas
          if (rutas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  _filtroTexto.isNotEmpty
                      ? 'No hay rutas que coincidan con "$_filtroTexto"'
                      : 'No hay rutas creadas en el periodo. Cree una arriba con "+ Crear / Asignar".',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rutas.length,
              itemBuilder: (ctx, idx) {
                final r = rutas[idx];
                final bool isExpanded = _expandedRutaId == r.id;

                Color tagColor = const Color(0xFF10B981); // PENDIENTE verde
                String tagTexto = 'PENDIENTE';
                if (r.isEnCurso) {
                  tagColor = const Color(0xFF38BDF8); // EN CURSO azul
                  tagTexto = 'EN CURSO';
                } else if (r.isCompletada) {
                  tagColor = const Color(0xFF059669);
                  tagTexto = 'COMPLETADA';
                } else if (r.estado == 'CANCELADA') {
                  tagColor = const Color(0xFFEF4444);
                  tagTexto = 'CANCELADA';
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090E1A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isExpanded ? const Color(0xFF1D72FE).withValues(alpha: 0.6) : const Color(0xFF1E293B),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Fila Principal de la Ruta (Click para Desplegar)
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (_expandedRutaId == r.id) {
                              _expandedRutaId = null;
                            } else {
                              _expandedRutaId = r.id;
                              _rutaSeleccionada = r;
                              _actualizarCentroMapaParaRuta(r);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Nombre y Chofer
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.codigoRuta,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      r.choferNombre ?? 'Sin asignar',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                    ),
                                  ],
                                ),
                              ),

                              // Estado Chip
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: tagColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: tagColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  tagTexto,
                                  style: TextStyle(color: tagColor, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Flecha Expandir / Colapsar
                              Icon(
                                isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                color: const Color(0xFF94A3B8),
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ==========================================
                      // CONTENIDO DESPLEGABLE: GESTIÓN DE PARADAS
                      // ==========================================
                      if (isExpanded) ...[
                        const Divider(color: Color(0xFF1E293B), height: 1),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0D1424),
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Barra de Herramientas de la Ruta Desplegada
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.pin_drop_rounded, size: 16, color: Color(0xFF38BDF8)),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${r.paradas.length} paradas programadas',
                                        style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      // Botón Primario: + Añadir Parada
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1D72FE),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          elevation: 0,
                                        ),
                                        icon: const Icon(Icons.add_location_alt_rounded, size: 15),
                                        label: const Text('+ Añadir Parada', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        onPressed: () => _abrirDialogoAgregarParada(r),
                                      ),

                                      // Iniciar Ruta (si está pendiente)
                                      if (r.isPendiente && r.paradas.isNotEmpty)
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFF10B981)),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Color(0xFF10B981)),
                                          label: const Text('Iniciar Ruta', style: TextStyle(color: Color(0xFF10B981), fontSize: 12)),
                                          onPressed: () => _iniciarRuta(r),
                                        ),

                                      // Eliminar Ruta
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                        tooltip: 'Eliminar esta ruta',
                                        onPressed: () => _eliminarRuta(r),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Lista de Paradas de la Ruta
                              if (r.paradas.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF101728),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF1E293B)),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.route_rounded, size: 30, color: Color(0xFF475569)),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Esta ruta no tiene paradas agregadas todavía.',
                                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                      ),
                                      const SizedBox(height: 10),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1D72FE),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        ),
                                        icon: const Icon(Icons.add, size: 16),
                                        label: const Text('Añadir la Primera Parada', style: TextStyle(fontSize: 12)),
                                        onPressed: () => _abrirDialogoAgregarParada(r),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: r.paradas.length,
                                  itemBuilder: (pCtx, pIdx) {
                                    final p = r.paradas[pIdx];

                                    Color pTagColor = const Color(0xFF10B981);
                                    if (p.isEnCurso) pTagColor = const Color(0xFF38BDF8);
                                    if (p.isEntregado) pTagColor = const Color(0xFF059669);
                                    if (p.isNoEntregado) pTagColor = const Color(0xFFEF4444);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF101728),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF1E293B)),
                                      ),
                                      child: Row(
                                        children: [
                                          // Número de Parada
                                          Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E293B),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '#${pIdx + 1}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF38BDF8)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),

                                          // Datos Parada (Cliente y Dirección)
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  p.cliente,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  p.direccionTexto,
                                                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                if (p.comentarios != null && p.comentarios!.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Material: ${p.comentarios}',
                                                    style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8)),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),

                                          // Badge Estado
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: pTagColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: pTagColor.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(
                                              p.estado,
                                              style: TextStyle(color: pTagColor, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(width: 10),

                                          // Botón: Centrar en Mini Mapa
                                          IconButton(
                                            icon: const Icon(Icons.my_location_rounded, size: 16, color: Color(0xFF38BDF8)),
                                            tooltip: 'Ver en Punto de Entrega',
                                            onPressed: () {
                                              setState(() {
                                                _mapCenter = LatLng(p.latitud, p.longitud);
                                                _mapZoom = 15.0;
                                              });
                                              try {
                                                _miniMapController.move(_mapCenter, 15.0);
                                              } catch (_) {}
                                            },
                                          ),

                                          // Botón: Ver e-PoD (si entregado)
                                          if (p.isEntregado)
                                            IconButton(
                                              icon: const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF10B981)),
                                              tooltip: 'Ver e-PoD (Firma y Foto)',
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (_) => EpodDialog(despacho: p),
                                                );
                                              },
                                            ),

                                          // Botón: Eliminar Parada
                                          IconButton(
                                            icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFEF4444)),
                                            tooltip: 'Eliminar esta parada',
                                            onPressed: () => _eliminarParada(r, p),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
