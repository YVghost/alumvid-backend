import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chofer.dart';
import '../models/despacho.dart';
import '../models/ruta.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/agregar_parada_dialog.dart';
import '../widgets/epod_dialog.dart';
import '../widgets/modificar_parada_dialog.dart';
import '../widgets/ver_ubicacion_parada_dialog.dart';

class PlanificarRutasView extends StatefulWidget {
  final List<Ruta> rutas;
  final List<Ruta> todasLasRutas;
  final List<Chofer> choferes;
  final DateTimeRange? rangoFiltro;
  final ValueChanged<DateTimeRange?> onCambiarRangoFiltro;
  final VoidCallback onRefresh;
  final void Function(Ruta? ruta)? onIrAMonitoreo;

  const PlanificarRutasView({
    super.key,
    required this.rutas,
    required this.todasLasRutas,
    required this.choferes,
    required this.rangoFiltro,
    required this.onCambiarRangoFiltro,
    required this.onRefresh,
    this.onIrAMonitoreo,
  });

  @override
  State<PlanificarRutasView> createState() => _PlanificarRutasViewState();
}

class _PlanificarRutasViewState extends State<PlanificarRutasView> {
  // Conjunto de IDs de rutas desplegadas (permite desplegar/minimizar múltiples o todas)
  final Set<String> _expandedRutaIds = {};

  // Filtro activo por tarjeta superior: null (todas), 'EN_CURSO', 'COMPLETADA', 'CANCELADA'
  String? _filtroEstadoCard;

  // Formulario Crear o Asignar Ruta
  final _codigoRutaCtrl = TextEditingController(text: 'Ruta 10');
  String? _choferCrearRutaId;
  bool _creandoRuta = false;

  // Filtro de búsqueda en la lista de rutas
  final _searchCtrl = TextEditingController();
  String _filtroTexto = '';

  @override
  void initState() {
    super.initState();
    _proponerSiguienteCodigo();
    // Desplegar por defecto la primera ruta si existe
    if (widget.rutas.isNotEmpty) {
      _expandedRutaIds.add(widget.rutas.first.id);
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

  String _formatearFechaCreacion(DateTime? fecha) {
    if (fecha == null) return '';
    // Ecuador se encuentra en UTC-5
    final ecDt = fecha.toUtc().subtract(const Duration(hours: 5));
    final nowEc = DateTime.now().toUtc().subtract(const Duration(hours: 5));

    const meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final mes = meses[ecDt.month - 1];
    final hora = ecDt.hour.toString().padLeft(2, '0');
    final min = ecDt.minute.toString().padLeft(2, '0');

    if (ecDt.year == nowEc.year) {
      return 'Creado: ${ecDt.day} $mes, $hora:$min';
    } else {
      return 'Creado: ${ecDt.day} $mes ${ecDt.year}, $hora:$min';
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
      AppToast.success(context, 'Ruta "$codigo" creada y agregada a la lista');

      _proponerSiguienteCodigo();
      widget.onRefresh();

      setState(() {
        _creandoRuta = false;
        _expandedRutaIds.add(nueva.id);
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
            _expandedRutaIds.add(ruta.id);
          });
        },
      ),
    );
  }

  void _abrirVerUbicacion(Ruta ruta, Despacho parada) {
    showDialog(
      context: context,
      builder: (_) => VerUbicacionParadaDialog(
        ruta: ruta,
        parada: parada,
        onParadaModificada: () {
          widget.onRefresh();
          setState(() {
            _expandedRutaIds.add(ruta.id);
          });
        },
      ),
    );
  }

  void _abrirModificarParada(Ruta ruta, Despacho parada) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ModificarParadaDialog(
        ruta: ruta,
        parada: parada,
        onParadaModificada: () {
          widget.onRefresh();
          setState(() {
            _expandedRutaIds.add(ruta.id);
          });
        },
      ),
    );
  }

  Future<void> _iniciarRuta(Ruta ruta) async {
    try {
      final act = await ApiService.iniciarRuta(ruta.id);
      if (!mounted) return;
      AppToast.success(context, 'Ruta "${act.codigoRuta}" puesta EN CURSO');
      widget.onRefresh();
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
        content: Text('¿Desea eliminar la ruta "${ruta.codigoRuta}" y todas sus paradas?', style: const TextStyle(color: Color(0xFF94A3B8))),
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
        setState(() {
          _expandedRutaIds.remove(ruta.id);
        });
        widget.onRefresh();
      } catch (e) {
        if (!mounted) return;
        AppToast.error(context, 'Error al eliminar ruta: $e');
      }
    }
  }

  Future<void> _eliminarParada(Ruta ruta, Despacho parada) async {
    try {
      await ApiService.eliminarDestinoRuta(ruta.id, parada.id);
      if (!mounted) return;
      AppToast.success(context, 'Parada eliminada de la ruta');
      widget.onRefresh();
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.all_inclusive_rounded, color: Color(0xFF38BDF8)),
                title: const Text('Todas las Rutas', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'TODAS'),
              ),
              ListTile(
                leading: const Icon(Icons.today_rounded, color: Color(0xFF38BDF8)),
                title: const Text('Hoy', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'HOY'),
              ),
              ListTile(
                leading: const Icon(Icons.history_rounded, color: Color(0xFF38BDF8)),
                title: const Text('Ayer', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'AYER'),
              ),
              ListTile(
                leading: const Icon(Icons.date_range_rounded, color: Color(0xFF38BDF8)),
                title: const Text('Últimos 7 días', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, '7DIAS'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8)),
                title: const Text('Todo el Mes', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'MES'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar_rounded, color: Color(0xFF38BDF8)),
                title: const Text('Elegir Rango Personalizado...', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'CUSTOM'),
              ),
            ],
          ),
        ),
      ),
    );

    if (opcion == null) return;

    if (opcion == 'TODAS') {
      widget.onCambiarRangoFiltro(null);
    } else if (opcion == 'HOY') {
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
        initialDateRange: widget.rangoFiltro ?? DateTimeRange(start: ahora, end: ahora),
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
    final int enCaminoCount = widget.rutas.where((r) => r.isEnCurso).length;
    final int pendientesCount = widget.rutas.where((r) => r.isPendiente).length;

    int canceladas = 0;
    for (final r in widget.rutas) {
      for (final p in r.paradas) {
        if (p.isNoEntregado) canceladas++;
      }
      if (r.estado == 'CANCELADA') canceladas++;
    }

    final bool esFiltroTotal = widget.rangoFiltro == null;
    final bool esHoy = !esFiltroTotal &&
        widget.rangoFiltro!.start.day == DateTime.now().day &&
        widget.rangoFiltro!.start.month == DateTime.now().month &&
        widget.rangoFiltro!.start.year == DateTime.now().year &&
        widget.rangoFiltro!.end.day == DateTime.now().day &&
        widget.rangoFiltro!.end.month == DateTime.now().month &&
        widget.rangoFiltro!.end.year == DateTime.now().year;

    final String diaNumero = esFiltroTotal
        ? 'Todas'
        : (esHoy
            ? widget.rangoFiltro!.start.day.toString()
            : DateFormat('dd MMM').format(widget.rangoFiltro!.start));

    final String diaTexto = esFiltroTotal
        ? 'Histórico'
        : (esHoy ? 'Hoy' : 'Periodo');

    // Filtrado de rutas por tarjeta seleccionada
    List<Ruta> rutasBase = widget.rutas;
    if (_filtroEstadoCard == 'EN_CURSO') {
      rutasBase = rutasBase.where((r) => r.isEnCurso).toList();
    } else if (_filtroEstadoCard == 'PENDIENTE') {
      rutasBase = rutasBase.where((r) => r.isPendiente).toList();
    } else if (_filtroEstadoCard == 'CANCELADA') {
      rutasBase = rutasBase.where((r) => r.estado == 'CANCELADA' || r.paradas.any((p) => p.isNoEntregado)).toList();
    }

    // Filtrado de rutas por texto de búsqueda
    final rutasFiltradas = rutasBase.where((r) {
      if (_filtroTexto.isEmpty) return true;
      final q = _filtroTexto.toLowerCase();
      final cod = r.codigoRuta.toLowerCase();
      final chofer = (r.choferNombre ?? '').toLowerCase();
      final tieneCliente = r.paradas.any((p) => p.cliente.toLowerCase().contains(q) || p.direccionTexto.toLowerCase().contains(q));
      return cod.contains(q) || chofer.contains(q) || tieneCliente;
    }).toList();

    return Container(
      color: const Color(0xFF070B14),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==========================================
            // 1. FILA DE 5 TARJETAS DE ESTADO (COMPACTAS Y FILTRABLES)
            // ==========================================
            _buildMetricCardsRow(
              diaTexto: diaTexto,
              diaNumero: diaNumero,
              rutasTotales: totalRutas,
              enCaminoCount: enCaminoCount,
              pendientesCount: pendientesCount,
              entregasCanceladas: canceladas,
            ),
            const SizedBox(height: 16),

            // ==========================================
            // 2. SECCIÓN MEDIA: 2 COLUMNAS (CREAR + CENTRO OPERATIVO DE FLOTA)
            // ==========================================
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 880;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: _buildCardCrearOAsignar()),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: _buildCardCentroOperativoFlota()),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildCardCrearOAsignar(),
                      const SizedBox(height: 16),
                      _buildCardCentroOperativoFlota(),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 16),

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
  // WIDGET: 5 TARJETAS DE MÉTRICAS COMPACTAS
  // ==========================================
  Widget _buildMetricCardsRow({
    required String diaTexto,
    required String diaNumero,
    required int rutasTotales,
    required int enCaminoCount,
    required int pendientesCount,
    required int entregasCanceladas,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1050;
        final isMedium = constraints.maxWidth >= 680;
        final crossCount = isWide ? 5 : (isMedium ? 3 : 2);

        return GridView.count(
          crossAxisCount: crossCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: isWide ? 3.3 : 2.5,
          children: [
            // Tarjeta 1: Fecha / Periodo
            _buildMetricItem(
              icon: Icons.calendar_month_rounded,
              iconColor: const Color(0xFF38BDF8),
              iconBg: const Color(0xFF1E3A8A).withValues(alpha: 0.35),
              title: diaTexto,
              value: diaNumero,
              hasDropdown: true,
              isSelected: false,
              onTap: _mostrarSelectorFecha,
            ),

            // Tarjeta 2: Rutas Totales
            _buildMetricItem(
              icon: Icons.alt_route_rounded,
              iconColor: const Color(0xFF60A5FA),
              iconBg: const Color(0xFF1D4ED8).withValues(alpha: 0.25),
              title: 'Rutas Totales',
              value: '$rutasTotales',
              isSelected: _filtroEstadoCard == null,
              onTap: () {
                setState(() => _filtroEstadoCard = null);
              },
            ),

            // Tarjeta 3: En Camino (VERDE)
            _buildMetricItem(
              icon: Icons.local_shipping_rounded,
              iconColor: const Color(0xFF10B981),
              iconBg: const Color(0xFF065F46).withValues(alpha: 0.35),
              title: 'En Camino',
              value: '$enCaminoCount',
              isSelected: _filtroEstadoCard == 'EN_CURSO',
              activeColor: const Color(0xFF10B981),
              onTap: () {
                setState(() {
                  if (_filtroEstadoCard == 'EN_CURSO') {
                    _filtroEstadoCard = null;
                  } else {
                    _filtroEstadoCard = 'EN_CURSO';
                    final enCurso = widget.rutas.where((r) => r.isEnCurso).map((r) => r.id);
                    _expandedRutaIds.addAll(enCurso);
                  }
                });
              },
            ),

            // Tarjeta 4: Pendientes (AMARILLO)
            _buildMetricItem(
              icon: Icons.hourglass_top_rounded,
              iconColor: const Color(0xFFF59E0B),
              iconBg: const Color(0xFF78350F).withValues(alpha: 0.35),
              title: 'Pendientes',
              value: '$pendientesCount',
              isSelected: _filtroEstadoCard == 'PENDIENTE',
              activeColor: const Color(0xFFF59E0B),
              onTap: () {
                setState(() {
                  if (_filtroEstadoCard == 'PENDIENTE') {
                    _filtroEstadoCard = null;
                  } else {
                    _filtroEstadoCard = 'PENDIENTE';
                    final pend = widget.rutas.where((r) => r.isPendiente).map((r) => r.id);
                    _expandedRutaIds.addAll(pend);
                  }
                });
              },
            ),

            // Tarjeta 5: Canceladas (ROJO)
            _buildMetricItem(
              icon: Icons.cancel_rounded,
              iconColor: const Color(0xFFEF4444),
              iconBg: const Color(0xFF991B1B).withValues(alpha: 0.35),
              title: 'Canceladas',
              value: '$entregasCanceladas',
              isSelected: _filtroEstadoCard == 'CANCELADA',
              activeColor: const Color(0xFFEF4444),
              onTap: () {
                setState(() {
                  if (_filtroEstadoCard == 'CANCELADA') {
                    _filtroEstadoCard = null;
                  } else {
                    _filtroEstadoCard = 'CANCELADA';
                    final canceladas = widget.rutas.where((r) => r.estado == 'CANCELADA' || r.paradas.any((p) => p.isNoEntregado)).map((r) => r.id);
                    _expandedRutaIds.addAll(canceladas);
                  }
                });
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String value,
    required VoidCallback onTap,
    bool hasDropdown = false,
    bool isSelected = false,
    Color? activeColor,
  }) {
    final borderCol = isSelected && activeColor != null
        ? activeColor.withValues(alpha: 0.8)
        : const Color(0xFF1E293B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF101728),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderCol, width: isSelected && activeColor != null ? 1.5 : 1.0),
          boxShadow: isSelected && activeColor != null
              ? [BoxShadow(color: activeColor.withValues(alpha: 0.15), blurRadius: 8, spreadRadius: 1)]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasDropdown) ...[
                        const SizedBox(width: 2),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8), size: 16),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101728),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera: Círculo con 1 + Título
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFF1D72FE),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Crear o Asignar Ruta',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),

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
                          const Text('Nombre de la Ruta', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                          const SizedBox(height: 5),
                          Container(
                            height: 40,
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Chofer Asignado', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                          const SizedBox(height: 5),
                          Container(
                            height: 40,
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
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8), size: 18),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
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
                    const Text('Nombre de la Ruta', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    const SizedBox(height: 5),
                    Container(
                      height: 40,
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
                    const Text('Chofer Asignado', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    const SizedBox(height: 5),
                    Container(
                      height: 40,
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
          const SizedBox(height: 14),

          // Botón Azul: + Crear / Asignar
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D72FE),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: _creandoRuta ? null : _crearOAsignarRuta,
              child: _creandoRuta
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('+ Crear / Asignar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // WIDGET: 2. CENTRO OPERATIVO & ESTADO DE FLOTA (REEMPLAZA PUNTO DE ENTREGA)
  // ==========================================
  Widget _buildCardCentroOperativoFlota() {
    // Buscar si hay alguna ruta activa en curso
    final rutaEnCurso = widget.rutas.where((r) => r.isEnCurso).toList();
    final choferesEnRuta = widget.choferes.where((c) => c.isEnRuta).length;
    final choferesDisponibles = widget.choferes.where((c) => c.isDisponible).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101728),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera: Icono + Título + Badge En Vivo
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.hub_rounded, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Centro Operativo & Flota',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Color(0xFF10B981), size: 7),
                    SizedBox(width: 5),
                    Text('En Vivo', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Indicadores de estado de flota
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF090E1A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildFleetBadge(
                  label: 'En Ruta',
                  value: '$choferesEnRuta',
                  subvalue: 'choferes activos',
                  color: const Color(0xFF10B981),
                ),
                Container(height: 28, width: 1, color: const Color(0xFF1E293B)),
                _buildFleetBadge(
                  label: 'Disponibles',
                  value: '$choferesDisponibles',
                  subvalue: 'listos para asignar',
                  color: const Color(0xFF38BDF8),
                ),
                Container(height: 28, width: 1, color: const Color(0xFF1E293B)),
                _buildFleetBadge(
                  label: 'Total Registrados',
                  value: '${widget.choferes.length}',
                  subvalue: 'flota de choferes',
                  color: const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Botón de Acción Directo: Ir a Monitoreo Satelital GPS
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F2B48),
                foregroundColor: const Color(0xFF38BDF8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFF0284C7)),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.satellite_alt_rounded, size: 16),
              label: Text(
                rutaEnCurso.isNotEmpty
                    ? 'Monitorear ${rutaEnCurso.first.codigoRuta} en Vivo'
                    : 'Ir a Monitoreo Satelital GPS',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              onPressed: () {
                final rTarget = rutaEnCurso.isNotEmpty ? rutaEnCurso.first : null;
                widget.onIrAMonitoreo?.call(rTarget);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFleetBadge({
    required String label,
    required String value,
    required String subvalue,
    required Color color,
  }) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
        const SizedBox(height: 1),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        Text(subvalue, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
      ],
    );
  }

  // ==========================================
  // WIDGET: 3. RUTAS CREADAS (ACORDEÓN DESPLEGABLE)
  // ==========================================
  Widget _buildCardRutasCreadas(List<Ruta> rutas) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101728),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera: Icono lista + Título + Chips de filtro + Minimizar todas + Buscador
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.format_list_bulleted_rounded, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Rutas Creadas (${rutas.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  if (_filtroEstadoCard != null) ...[
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: () => setState(() => _filtroEstadoCard = null),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Filtro: $_filtroEstadoCard',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.close_rounded, size: 12, color: Color(0xFF38BDF8)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Controles a la derecha: Minimizar Todas + Buscador
              Row(
                children: [
                  // Botón Icono para Minimizar Todas las Rutas Desplegadas (sin texto)
                  IconButton(
                    icon: const Icon(Icons.unfold_less_rounded, color: Color(0xFF94A3B8), size: 18),
                    tooltip: 'Minimizar todas las rutas',
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF090E1A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _expandedRutaIds.clear();
                      });
                    },
                  ),
                  const SizedBox(width: 8),

                  // Buscador de Rutas
                  Container(
                    width: 190,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF090E1A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      onChanged: (val) => setState(() => _filtroTexto = val.trim()),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.search, size: 15, color: Color(0xFF64748B)),
                        hintText: 'Buscar ruta o cliente...',
                        hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Lista de Rutas
          if (rutas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  _filtroTexto.isNotEmpty
                      ? 'No hay rutas que coincidan con "$_filtroTexto"'
                      : (_filtroEstadoCard != null
                          ? 'No hay rutas con estado "$_filtroEstadoCard" en este periodo.'
                          : 'No hay rutas creadas en el periodo. Cree una arriba con "+ Crear / Asignar".'),
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
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
                final bool isExpanded = _expandedRutaIds.contains(r.id);

                Color tagColor = const Color(0xFF64748B); // Neutro para otros estados
                String tagTexto = r.estado;
                if (r.isEnCurso) {
                  tagColor = const Color(0xFF10B981); // EN CURSO: VERDE
                  tagTexto = 'EN CURSO';
                } else if (r.isPendiente) {
                  tagColor = const Color(0xFFF59E0B); // PENDIENTE: AMARILLO
                  tagTexto = 'PENDIENTE';
                } else if (r.estado == 'CANCELADA' || r.estado == 'CANCELADO') {
                  tagColor = const Color(0xFFEF4444); // CANCELADA: ROJO
                  tagTexto = 'CANCELADA';
                } else if (r.isCompletada) {
                  tagColor = const Color(0xFF94A3B8); // Sin tono específico
                  tagTexto = 'COMPLETADA';
                }

                final fechaTexto = _formatearFechaCreacion(r.fechaCreacion);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090E1A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isExpanded ? const Color(0xFF1D72FE).withValues(alpha: 0.6) : const Color(0xFF1E293B),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Fila Principal de la Ruta (Click para Desplegar / Minimizar)
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (_expandedRutaIds.contains(r.id)) {
                              _expandedRutaIds.remove(r.id);
                            } else {
                              _expandedRutaIds.add(r.id);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Nombre, Chofer y Fecha de Creación
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.codigoRuta,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          r.choferNombre ?? 'Sin asignar',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                        ),
                                        if (fechaTexto.isNotEmpty) ...[
                                          const Text('  •  ', style: TextStyle(color: Color(0xFF475569), fontSize: 11)),
                                          Text(
                                            fechaTexto,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Estado Chip
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: tagColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: tagColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  tagTexto,
                                  style: TextStyle(color: tagColor, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Flecha Expandir / Colapsar
                              Icon(
                                isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                color: const Color(0xFF94A3B8),
                                size: 18,
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
                          padding: const EdgeInsets.all(14),
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
                                      const Icon(Icons.pin_drop_rounded, size: 15, color: Color(0xFF38BDF8)),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${r.paradas.length} paradas programadas',
                                        style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12, fontWeight: FontWeight.w600),
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
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          elevation: 0,
                                        ),
                                        icon: const Icon(Icons.add_location_alt_rounded, size: 14),
                                        label: const Text('+ Añadir Parada', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        onPressed: () => _abrirDialogoAgregarParada(r),
                                      ),

                                      // Iniciar Ruta (si está pendiente)
                                      if (r.isPendiente && r.paradas.isNotEmpty)
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFF10B981)),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          icon: const Icon(Icons.play_arrow_rounded, size: 15, color: Color(0xFF10B981)),
                                          label: const Text('Iniciar Ruta', style: TextStyle(color: Color(0xFF10B981), fontSize: 11)),
                                          onPressed: () => _iniciarRuta(r),
                                        ),

                                      // Eliminar Ruta
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 17),
                                        tooltip: 'Eliminar esta ruta',
                                        padding: const EdgeInsets.all(6),
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _eliminarRuta(r),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Lista de Paradas de la Ruta
                              if (r.paradas.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF101728),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF1E293B)),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.route_rounded, size: 28, color: Color(0xFF475569)),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Esta ruta no tiene paradas agregadas todavía.',
                                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                      ),
                                      const SizedBox(height: 8),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1D72FE),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        ),
                                        icon: const Icon(Icons.add, size: 14),
                                        label: const Text('Añadir la Primera Parada', style: TextStyle(fontSize: 11)),
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

                                    // Colores y Sombras según Estado para Máxima Claridad Visual
                                    late final Color borderColor;
                                    late final Color cardBg;
                                    late final List<BoxShadow> cardShadow;
                                    late final Color pTagColor;

                                    if (p.isEnCurso) {
                                      // EN CURSO: VERDE
                                      borderColor = const Color(0xFF10B981).withValues(alpha: 0.85);
                                      cardBg = const Color(0xFF0C1F1A);
                                      cardShadow = [
                                        BoxShadow(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                          blurRadius: 8,
                                          offset: const Offset(0, 1),
                                        ),
                                      ];
                                      pTagColor = const Color(0xFF10B981);
                                    } else if (p.estado == 'PENDIENTE') {
                                      // PENDIENTE: AMARILLO
                                      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.7);
                                      cardBg = const Color(0xFF1A160A);
                                      cardShadow = [
                                        BoxShadow(
                                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                          blurRadius: 6,
                                          offset: const Offset(0, 1),
                                        ),
                                      ];
                                      pTagColor = const Color(0xFFF59E0B);
                                    } else if (p.isNoEntregado) {
                                      // CANCELADA / NO ENTREGADO: ROJO
                                      borderColor = const Color(0xFFEF4444).withValues(alpha: 0.7);
                                      cardBg = const Color(0xFF221114);
                                      cardShadow = [
                                        BoxShadow(
                                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                          blurRadius: 6,
                                          offset: const Offset(0, 1),
                                        ),
                                      ];
                                      pTagColor = const Color(0xFFEF4444);
                                    } else {
                                      // ENTREGADO Y OTROS: SIN TONO ESPECÍFICO (NEUTRO GRIS SLATE)
                                      borderColor = const Color(0xFF1E293B);
                                      cardBg = const Color(0xFF0D1424);
                                      cardShadow = [];
                                      pTagColor = const Color(0xFF94A3B8);
                                    }

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: cardBg,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: borderColor, width: 1.3),
                                        boxShadow: cardShadow,
                                      ),
                                      child: Row(
                                        children: [
                                          // Número de Parada
                                          Container(
                                            width: 26,
                                            height: 26,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E293B),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '#${pIdx + 1}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF38BDF8)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),

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
                                          const SizedBox(width: 8),

                                          // Botón: Ver Ubicación Guardada en Mapa
                                          IconButton(
                                            icon: const Icon(Icons.location_on_rounded, size: 17, color: Color(0xFF38BDF8)),
                                            tooltip: 'Ver ubicación guardada en mapa',
                                            padding: const EdgeInsets.all(6),
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _abrirVerUbicacion(r, p),
                                          ),

                                          // Botón: Modificar Parada
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 17, color: Color(0xFF94A3B8)),
                                            tooltip: 'Modificar parada (datos y coordenadas)',
                                            padding: const EdgeInsets.all(6),
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _abrirModificarParada(r, p),
                                          ),

                                          // Botón: Ver e-PoD (si entregado)
                                          if (p.isEntregado)
                                            IconButton(
                                              icon: const Icon(Icons.verified_rounded, size: 17, color: Color(0xFF10B981)),
                                              tooltip: 'Ver e-PoD (Firma y Foto)',
                                              padding: const EdgeInsets.all(6),
                                              constraints: const BoxConstraints(),
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (_) => EpodDialog(despacho: p),
                                                );
                                              },
                                            ),

                                          // Botón: Eliminar Parada
                                          IconButton(
                                            icon: const Icon(Icons.close_rounded, size: 17, color: Color(0xFFEF4444)),
                                            tooltip: 'Eliminar esta parada',
                                            padding: const EdgeInsets.all(6),
                                            constraints: const BoxConstraints(),
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
