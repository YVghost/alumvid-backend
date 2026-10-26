import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/chofer.dart';
import '../models/despacho.dart';
import '../models/producto.dart';
import '../models/ruta.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/epod_dialog.dart';
import '../widgets/map_picker_dialog.dart';
import '../widgets/parada_card_widget.dart';

class PlanificarRutasView extends StatefulWidget {
  final List<Ruta> rutas;
  final List<Chofer> choferes;
  final VoidCallback onRefresh;

  const PlanificarRutasView({
    super.key,
    required this.rutas,
    required this.choferes,
    required this.onRefresh,
  });

  @override
  State<PlanificarRutasView> createState() => _PlanificarRutasViewState();
}

class _PlanificarRutasViewState extends State<PlanificarRutasView> {
  Ruta? _rutaSeleccionada;

  // Formulario Crear Ruta
  final _codigoRutaCtrl = TextEditingController(text: 'Ruta 1');
  final _observacionesRutaCtrl = TextEditingController();
  String? _choferCrearRutaId;
  bool _creandoRuta = false;

  // Formulario Reasignar Chofer
  String? _choferReasignarId;
  bool _guardandoChofer = false;

  // Formulario Agregar Parada
  final _paradaClienteCtrl = TextEditingController();
  final _paradaDireccionCtrl = TextEditingController();
  final _paradaCantidadCtrl = TextEditingController(text: '1');
  final _paradaDetalleCtrl = TextEditingController();
  double _paradaLat = -0.1807;
  double _paradaLon = -78.4678;
  String _direccionResuelta = '';
  bool _ubicacionConfirmada = false;
  bool _guardandoParada = false;

  // Catálogo de Inventario para "Qué se va a entregar"
  List<Producto> _productosInventario = [];
  Producto? _productoSeleccionado;
  bool _cargandoProductos = true;

  @override
  void initState() {
    super.initState();
    if (widget.rutas.isNotEmpty) {
      _rutaSeleccionada = widget.rutas.first;
      _choferReasignarId = _rutaSeleccionada?.choferId;
      _proponerSiguienteCodigo();
    }
    _cargarProductosInventario();
  }

  @override
  void didUpdateWidget(covariant PlanificarRutasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_rutaSeleccionada != null) {
      final act = widget.rutas.where((r) => r.id == _rutaSeleccionada!.id).toList();
      if (act.isNotEmpty) {
        _rutaSeleccionada = act.first;
      }
    }
  }

  @override
  void dispose() {
    _codigoRutaCtrl.dispose();
    _observacionesRutaCtrl.dispose();
    _paradaClienteCtrl.dispose();
    _paradaDireccionCtrl.dispose();
    _paradaCantidadCtrl.dispose();
    _paradaDetalleCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarProductosInventario() async {
    try {
      final res = await ApiService.obtenerProductos(size: 100);
      final List<Producto> prods = res['items'] as List<Producto>? ?? [];
      if (mounted) {
        setState(() {
          _productosInventario = prods;
          if (prods.isNotEmpty) {
            _productoSeleccionado = prods.first;
          }
          _cargandoProductos = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando inventario en rutas: $e');
      if (mounted) setState(() => _cargandoProductos = false);
    }
  }

  void _proponerSiguienteCodigo() {
    int maxNum = 0;
    for (final r in widget.rutas) {
      final match = RegExp(r'\d+').firstMatch(r.codigoRuta);
      if (match != null) {
        final val = int.tryParse(match.group(0)!) ?? 0;
        if (val > maxNum) maxNum = val;
      }
    }
    _codigoRutaCtrl.text = 'Ruta ${maxNum + 1}';
  }

  Future<void> _crearRuta() async {
    final codigo = _codigoRutaCtrl.text.trim();
    if (codigo.isEmpty) {
      AppToast.warning(context, 'Ingrese el nombre o código de la ruta');
      return;
    }

    setState(() => _creandoRuta = true);
    try {
      final nueva = await ApiService.crearRutaSimple(
        codigoRuta: codigo,
        choferId: _choferCrearRutaId,
        comentarios: _observacionesRutaCtrl.text.trim().isEmpty ? null : _observacionesRutaCtrl.text.trim(),
      );

      if (!mounted) return;
      AppToast.success(context, 'Hoja de ruta "${nueva.codigoRuta}" creada exitosamente.');

      _observacionesRutaCtrl.clear();
      _proponerSiguienteCodigo();
      widget.onRefresh();

      setState(() {
        _rutaSeleccionada = nueva;
        _choferReasignarId = nueva.choferId;
        _creandoRuta = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _creandoRuta = false);
      AppToast.error(context, 'Error al crear ruta: $e');
    }
  }

  Future<void> _actualizarChoferRuta() async {
    if (_rutaSeleccionada == null) return;

    setState(() => _guardandoChofer = true);
    try {
      final act = await ApiService.asignarChoferRuta(_rutaSeleccionada!.id, _choferReasignarId);
      if (!mounted) return;
      AppToast.success(context, 'Chofer responsable actualizado para la hoja de ruta.');
      widget.onRefresh();
      setState(() {
        _rutaSeleccionada = act;
        _guardandoChofer = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardandoChofer = false);
      AppToast.error(context, 'Error al asignar chofer: $e');
    }
  }

  Future<void> _abrirMapPicker() async {
    final MapPickerResult? picked = await showDialog<MapPickerResult>(
      context: context,
      builder: (_) => MapPickerDialog(
        initialLocation: LatLng(_paradaLat, _paradaLon),
        title: 'Elegir Ubicación de Parada en Google Maps',
      ),
    );

    if (picked != null) {
      setState(() {
        _paradaLat = picked.location.latitude;
        _paradaLon = picked.location.longitude;
        _direccionResuelta = picked.address;
        _ubicacionConfirmada = true;
        if (_paradaDireccionCtrl.text.trim().isEmpty) {
          _paradaDireccionCtrl.text = picked.address;
        }
      });
      if (mounted) {
        AppToast.success(context, 'Ubicación seleccionada en el mapa');
      }
    }
  }

  Future<void> _agregarParada() async {
    if (_rutaSeleccionada == null) {
      AppToast.warning(context, 'Seleccione primero una hoja de ruta para asociar paradas.');
      return;
    }

    final cliente = _paradaClienteCtrl.text.trim();
    final direccion = _paradaDireccionCtrl.text.trim();

    if (cliente.isEmpty || direccion.isEmpty) {
      AppToast.warning(context, 'Complete el cliente y la dirección de entrega');
      return;
    }

    // Qué se va a entregar: estructurado desde catálogo
    String queSeEntrega = '';
    if (_productoSeleccionado != null) {
      final cant = _paradaCantidadCtrl.text.trim().isNotEmpty ? _paradaCantidadCtrl.text.trim() : '1';
      queSeEntrega = '${_productoSeleccionado!.name} ($cant ${_productoSeleccionado!.unit})';
      if (_paradaDetalleCtrl.text.trim().isNotEmpty) {
        queSeEntrega += ' - ${_paradaDetalleCtrl.text.trim()}';
      }
    } else if (_paradaDetalleCtrl.text.trim().isNotEmpty) {
      queSeEntrega = _paradaDetalleCtrl.text.trim();
    } else {
      queSeEntrega = 'Material de Vidriería / Perfilería';
    }

    setState(() => _guardandoParada = true);
    try {
      final act = await ApiService.agregarDestinoRuta(
        rutaId: _rutaSeleccionada!.id,
        cliente: cliente,
        direccionTexto: direccion,
        latitud: _paradaLat,
        longitud: _paradaLon,
        comentarios: queSeEntrega,
      );

      if (!mounted) return;
      AppToast.success(context, 'Parada "$cliente" agregada exitosamente a la ruta.');

      _paradaClienteCtrl.clear();
      _paradaDireccionCtrl.clear();
      _paradaDetalleCtrl.clear();
      _paradaCantidadCtrl.text = '1';
      setState(() => _ubicacionConfirmada = false);
      widget.onRefresh();

      setState(() {
        _rutaSeleccionada = act;
        _guardandoParada = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardandoParada = false);
      AppToast.error(context, 'Error al agregar parada: $e');
    }
  }


  Future<void> _eliminarRuta() async {
    if (_rutaSeleccionada == null) return;

    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar Hoja de Ruta'),
        content: Text('¿Confirma que desea eliminar la ruta "${_rutaSeleccionada!.codigoRuta}" y todas sus paradas asociadas?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusAlerta),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar Definitivamente'),
          ),
        ],
      ),
    );

    if (conf == true) {
      try {
        if (_rutaSeleccionada!.isEnCurso) {
          try {
            await ApiService.cancelarRuta(_rutaSeleccionada!.id, 'Cancelación previa a eliminación');
          } catch (_) {}
        }
        await ApiService.eliminarRuta(_rutaSeleccionada!.id);
        if (!mounted) return;
        AppToast.success(context, 'Hoja de ruta eliminada exitosamente.');
        widget.onRefresh();
        setState(() {
          _rutaSeleccionada = null;
        });
      } catch (e) {
        if (!mounted) return;
        AppToast.error(context, 'Error al eliminar ruta: $e');
      }
    }
  }

  Future<void> _iniciarRuta() async {
    if (_rutaSeleccionada == null) return;
    try {
      final act = await ApiService.iniciarRuta(_rutaSeleccionada!.id);
      if (!mounted) return;
      AppToast.warning(context, 'Ruta "${act.codigoRuta}" iniciada en despacho activo.');
      widget.onRefresh();
      setState(() => _rutaSeleccionada = act);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Error al iniciar ruta: $e');
    }
  }

  Future<void> _eliminarParada(Despacho parada) async {
    if (_rutaSeleccionada == null) return;
    try {
      final act = await ApiService.eliminarDestinoRuta(_rutaSeleccionada!.id, parada.id);
      if (!mounted) return;
      AppToast.success(context, 'Parada eliminada de la ruta.');
      widget.onRefresh();
      setState(() => _rutaSeleccionada = act);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Error al eliminar parada: $e');
    }
  }

  void _abrirEpod(Despacho d) {
    showDialog(
      context: context,
      builder: (_) => EpodDialog(despacho: d),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de Cabecera
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestión y Asignación Integral de Hojas de Ruta',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Flujo operativo: 1. Crear Ruta → 2. Agregar Paradas con Mapa → 3. Asignar Chofer Responsable',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppTheme.primaryLight),
                  tooltip: 'Actualizar Rutas',
                  onPressed: widget.onRefresh,
                ),
              ],
            ),
          ),

          // Contenido 2 Columnas
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 950;
                return isDesktop ? _buildDesktopColumns() : _buildMobileList();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopColumns() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double leftColWidth = constraints.maxWidth < 1100 ? 295 : 335;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Columna Izquierda: Formulario Crear Ruta + Lista Rutas Creadas
            SizedBox(
              width: leftColWidth,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildCardCrearRuta(),
                    const SizedBox(height: 14),
                    _buildCardListaRutas(),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Columna Derecha: Panel de la Ruta Seleccionada (Flex 1)
            Expanded(
              child: _rutaSeleccionada == null
                  ? _buildPanelVacio()
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildHeaderRutaActiva(),
                          const SizedBox(height: 14),
                          _buildCardAgregarParada(),
                          const SizedBox(height: 14),
                          _buildCardListaParadas(),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobileList() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildCardCrearRuta(),
          const SizedBox(height: 14),
          _buildCardListaRutas(),
          const SizedBox(height: 14),
          if (_rutaSeleccionada != null) ...[
            _buildHeaderRutaActiva(),
            const SizedBox(height: 14),
            _buildCardAgregarParada(),
            const SizedBox(height: 14),
            _buildCardListaParadas(),
          ],
        ],
      ),
    );
  }

  Widget _buildCardCrearRuta() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '1. Crear Nueva Hoja de Ruta',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryLight),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codigoRutaCtrl,
            decoration: const InputDecoration(labelText: 'Nombre / Código de la Ruta', hintText: 'Ej. Ruta 1, Ruta Norte Express'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _choferCrearRutaId,
            decoration: const InputDecoration(labelText: 'Chofer Asignado (Opcional)'),
            dropdownColor: AppTheme.surfaceCard,
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('-- Sin asignar (asignar después) --', overflow: TextOverflow.ellipsis),
              ),
              ...widget.choferes.map((c) => DropdownMenuItem(
                value: c.id,
                child: Text(c.nombre, overflow: TextOverflow.ellipsis),
              )),
            ],
            onChanged: (val) => setState(() => _choferCrearRutaId = val),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _observacionesRutaCtrl,
            decoration: const InputDecoration(labelText: 'Observaciones / Comentarios', hintText: 'Ej. Vidrios templados 8mm...'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 12)),
              icon: _creandoRuta ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add, size: 16),
              label: const Text('+ Crear Hoja de Ruta', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _creandoRuta ? null : _crearRuta,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardListaRutas() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rutas Creadas (${widget.rutas.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.rutas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No hay rutas creadas para la fecha. Cree una arriba.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.rutas.length,
              itemBuilder: (ctx, idx) {
                final r = widget.rutas[idx];
                final isSel = _rutaSeleccionada?.id == r.id;
                Color tagColor = AppTheme.statusPendiente;
                if (r.isEnCurso) tagColor = AppTheme.statusEnCurso;
                if (r.isCompletada) tagColor = AppTheme.statusCompletada;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _rutaSeleccionada = r;
                      _choferReasignarId = r.choferId;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSel ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isSel ? AppTheme.primaryLight : AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.codigoRuta, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text(
                              r.choferNombre != null ? 'Chofer: ${r.choferNombre}' : 'Sin chofer asignado',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: tagColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: tagColor),
                              ),
                              child: Text(r.estado, style: TextStyle(color: tagColor, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 4),
                            Text('${r.paradas.length} paradas', style: const TextStyle(fontSize: 10, color: AppTheme.textDim)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPanelVacio() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alt_route, size: 48, color: AppTheme.textDim),
            SizedBox(height: 12),
            Text('Ninguna Ruta Seleccionada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            SizedBox(height: 6),
            Text(
              'Seleccione una ruta de la lista lateral o cree una nueva para comenzar a agregar paradas mediante el mapa interactivo y asignar al chofer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRutaActiva() {
    final r = _rutaSeleccionada!;
    Color tagColor = AppTheme.statusPendiente;
    if (r.isEnCurso) tagColor = AppTheme.statusEnCurso;
    if (r.isCompletada) tagColor = AppTheme.statusCompletada;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(r.codigoRuta, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tagColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: tagColor),
                    ),
                    child: Text(r.estado, style: TextStyle(color: tagColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              Row(
                children: [
                  if (!r.isEnCurso && !r.isCompletada)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusEnCurso, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Iniciar Ruta', style: TextStyle(fontSize: 11)),
                      onPressed: _iniciarRuta,
                    ),
                  const SizedBox(width: 8),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, color: AppTheme.statusAlerta, size: 20),
                    tooltip: 'Eliminar Ruta',
                    onPressed: _eliminarRuta,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            r.choferNombre != null ? 'Chofer asignado: ${r.choferNombre}' : 'Chofer asignado: Sin asignar',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const Divider(color: AppTheme.border, height: 20),

          // Paso 3: Asignar / Cambiar Chofer Responsable
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF131D2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _choferReasignarId,
                    decoration: const InputDecoration(
                      labelText: '3. Asignar / Cambiar Chofer Responsable',
                      isDense: true,
                    ),
                    dropdownColor: AppTheme.surfaceCard,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('-- Seleccionar chofer --')),
                      ...widget.choferes.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.nombre} (${c.estadoDisponibilidad})'))),
                    ],
                    onChanged: (val) => setState(() => _choferReasignarId = val),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onPressed: _guardandoChofer ? null : _actualizarChoferRuta,
                  child: _guardandoChofer
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Actualizar Chofer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardAgregarParada() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.add_location_alt, color: AppTheme.statusCompletada, size: 18),
                  SizedBox(width: 8),
                  Text(
                    '2. Agregar Parada a esta Ruta',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.statusCompletada),
                  ),
                ],
              ),
              if (_ubicacionConfirmada)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.statusCompletada.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.statusCompletada.withValues(alpha: 0.8)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, size: 12, color: AppTheme.statusCompletada),
                      SizedBox(width: 5),
                      Text(
                        'Punto fijado en mapa',
                        style: TextStyle(color: AppTheme.statusCompletada, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Layout Responsivo: Si el contenedor mide >= 740px se despliega en 2 columnas; si es menor, se apilan verticalmente
          LayoutBuilder(
            builder: (context, cardConstraints) {
              final isWide = cardConstraints.maxWidth >= 740;

              final formColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fila 1: Cliente y Dirección (se adapta si el ancho es estrecho)
                  LayoutBuilder(
                    builder: (ctx, fConstraints) {
                      final stackFields = fConstraints.maxWidth < 480;
                      if (stackFields) {
                        return Column(
                          children: [
                            TextField(
                              controller: _paradaClienteCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Cliente o Razón Social *',
                                hintText: 'Ej. Constructora Los Andes / Arq. Juan Pérez',
                                prefixIcon: Icon(Icons.business, size: 18),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _paradaDireccionCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Dirección de Entrega *',
                                hintText: 'Ej. Av. 6 de Diciembre y Orellana, Quito',
                                prefixIcon: Icon(Icons.home, size: 18),
                              ),
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _paradaClienteCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Cliente o Razón Social *',
                                hintText: 'Ej. Constructora Los Andes / Arq. Juan Pérez',
                                prefixIcon: Icon(Icons.business, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _paradaDireccionCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Dirección de Entrega *',
                                hintText: 'Ej. Av. 6 de Diciembre y Orellana, Quito',
                                prefixIcon: Icon(Icons.home, size: 18),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Fila 2: Qué se va a entregar (Selector de Inventario y Bodega)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131D2E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.inventory_2, color: AppTheme.primaryLight, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Qué se va a entregar (Catálogo de Inventario y Bodega)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryLight),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Selector de Producto a Ancho Completo (Para evitar textos apretados y elipsis)
                        _cargandoProductos
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Cargando catálogo de inventario...', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                              )
                            : DropdownButtonFormField<Producto>(
                                initialValue: _productoSeleccionado,
                                isExpanded: true,
                                dropdownColor: AppTheme.surfaceCard,
                                decoration: const InputDecoration(
                                  labelText: 'Producto a entregar *',
                                  isDense: true,
                                  prefixIcon: Icon(Icons.category, size: 18),
                                ),
                                items: _productosInventario.map((p) {
                                  return DropdownMenuItem(
                                    value: p,
                                    child: Text(
                                      '[${p.code}] ${p.name}  —  (Stock: ${p.stock.toStringAsFixed(0)} ${p.unit})',
                                      style: const TextStyle(fontSize: 12, color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) => setState(() => _productoSeleccionado = val),
                              ),
                        const SizedBox(height: 10),

                        // Cantidad y Observación/Detalles en su propia fila espaciosa
                        Row(
                          children: [
                            SizedBox(
                              width: 140,
                              child: TextField(
                                controller: _paradaCantidadCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Cantidad *',
                                  suffixText: _productoSeleccionado?.unit ?? 'Unid',
                                  isDense: true,
                                  prefixIcon: const Icon(Icons.numbers, size: 16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _paradaDetalleCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Detalles / Observación',
                                  hintText: 'Ej. Templado 10mm / Medidas especiales',
                                  isDense: true,
                                  prefixIcon: Icon(Icons.edit_note, size: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Botón para agregar parada
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.statusCompletada,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        icon: _guardandoParada
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.add_location_alt, size: 18),
                        label: const Text('+ Agregar Parada a la Ruta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: _guardandoParada ? null : _agregarParada,
                      ),
                      if (_direccionResuelta.isNotEmpty)
                        Text(
                          'Punto: $_direccionResuelta',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ],
              );

              final mapPreviewColumn = SizedBox(
                width: isWide ? 280 : double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.location_on, size: 15, color: AppTheme.primaryLight),
                            SizedBox(width: 5),
                            Text(
                              'Punto de Entrega',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryLight),
                            ),
                          ],
                        ),
                        if (_paradaLat != 0.0)
                          Text(
                            '${_paradaLat.toStringAsFixed(4)}, ${_paradaLon.toStringAsFixed(4)}',
                            style: const TextStyle(color: AppTheme.textDim, fontSize: 10, fontFamily: 'monospace'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Tarjeta de Previsualización del Mapa (Google Maps Roadmap limpio, sin marca de agua)
                    InkWell(
                      onTap: _abrirMapPicker,
                      borderRadius: BorderRadius.circular(10),
                      child: Tooltip(
                        message: 'Haga clic para abrir el mapa interactivo y buscar el punto de entrega',
                        child: Container(
                          height: isWide ? 210 : 180,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _ubicacionConfirmada
                                  ? AppTheme.statusCompletada.withValues(alpha: 0.85)
                                  : AppTheme.border,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Stack(
                              children: [
                                IgnorePointer(
                                  ignoring: true,
                                  child: FlutterMap(
                                    key: ValueKey('preview-$_paradaLat-$_paradaLon'),
                                    options: MapOptions(
                                      initialCenter: LatLng(_paradaLat, _paradaLon),
                                      initialZoom: 15.0,
                                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                                    ),
                                    children: [
                                      TileLayer(
                                        urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                                        userAgentPackageName: 'com.alumvid.admin',
                                      ),
                                    ],
                                  ),
                                ),

                                // Pin Rojo Centrado con Sombra
                                Center(
                                  child: FractionalTranslation(
                                    translation: const Offset(0.0, -0.42),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color: AppTheme.statusAlerta,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppTheme.statusAlerta.withValues(alpha: 0.7),
                                                blurRadius: 8,
                                                spreadRadius: 2,
                                              ),
                                              const BoxShadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2)),
                                            ],
                                          ),
                                          child: const Icon(Icons.location_pin, color: Colors.white, size: 22),
                                        ),
                                        Container(
                                          width: 4,
                                          height: 4,
                                          margin: const EdgeInsets.only(top: 1),
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: formColumn),
                    const SizedBox(width: 16),
                    mapPreviewColumn,
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    formColumn,
                    const SizedBox(height: 14),
                    mapPreviewColumn,
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCardListaParadas() {
    final r = _rutaSeleccionada!;
    final paradas = r.paradas;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Paradas en la Ruta (${paradas.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
              if (paradas.isNotEmpty)
                const Text(
                  'Toque la vista previa para ver en Google Maps externo',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (paradas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'No hay paradas agregadas a esta ruta. Utilice el formulario superior para añadir paradas.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: paradas.length,
              itemBuilder: (ctx, idx) {
                final p = paradas[idx];
                return ParadaCardWidget(
                  parada: p,
                  orden: idx + 1,
                  onVerEpod: p.isEntregado ? () => _abrirEpod(p) : null,
                  onEliminar: () => _eliminarParada(p),
                );
              },
            ),
        ],
      ),
    );
  }
}
