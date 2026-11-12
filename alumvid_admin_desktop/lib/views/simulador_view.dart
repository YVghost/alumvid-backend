import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/chofer.dart';
import '../models/despacho.dart';
import '../models/ruta.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class SimuladorView extends StatefulWidget {
  final List<Ruta> rutas;
  final List<Chofer> choferes;
  final Function(LatLng, double rumbo) onPosicionSimulada;
  final VoidCallback onRefresh;

  const SimuladorView({
    super.key,
    required this.rutas,
    required this.choferes,
    required this.onPosicionSimulada,
    required this.onRefresh,
  });

  @override
  State<SimuladorView> createState() => _SimuladorViewState();
}

class _SimuladorViewState extends State<SimuladorView> {
  String? _choferIdSeleccionado;
  String _gpsMode = 'match'; // 'match' (<10m) o 'deviation' (>150m)

  Chofer? get _choferSeleccionado {
    if (widget.choferes.isEmpty) return null;
    return widget.choferes.firstWhere(
      (c) => c.id == _choferIdSeleccionado,
      orElse: () => widget.choferes.first,
    );
  }

  // Despacho activo en el smartphone
  Despacho? _despachoActivo;
  bool _enDetalleDespacho = false;
  bool _mostrandoFormularioEpod = false;

  // Telemetría continua
  bool _streamingGps = false;
  Timer? _streamingTimer;
  double _velocidadKmh = 42.0;
  int _pasoActual = 0;
  List<LatLng> _trayectoria = [];

  // Evidencia e-PoD
  bool _fotoCapturada = false;
  String _fotoTimestamp = '';
  final List<Offset?> _puntosFirma = [];
  final TextEditingController _comentariosPodCtrl = TextEditingController(text: 'Vidrio recibido conforme y verificado.');
  bool _enviandoEpod = false;

  final List<LatLng> _puntosEjemplo = const [
    LatLng(-0.089290, -78.439607), // Bodega Central Arq-AlumVid
    LatLng(-0.1830, -78.4720),
    LatLng(-0.1865, -78.4760),
    LatLng(-0.1910, -78.4800),
    LatLng(-0.1985, -78.4850),
    LatLng(-0.2050, -78.4900),
    LatLng(-0.2120, -78.4980),
    LatLng(-0.2200, -78.5140),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.choferes.isNotEmpty) {
      _choferIdSeleccionado = widget.choferes.first.id;
    }
  }

  @override
  void dispose() {
    _streamingTimer?.cancel();
    super.dispose();
  }

  // Filtrar despachos asignados al chofer seleccionado
  List<Despacho> get _despachosChofer {
    if (_choferSeleccionado == null) return [];
    final List<Despacho> list = [];
    for (final r in widget.rutas) {
      if (r.choferId == _choferSeleccionado!.id) {
        for (final p in r.paradas) {
          list.add(p);
        }
      }
    }
    return list;
  }

  void _abrirDespachoEnTelefono(Despacho d) {
    setState(() {
      _despachoActivo = d;
      _enDetalleDespacho = true;
      _mostrandoFormularioEpod = false;
      _fotoCapturada = false;
      _puntosFirma.clear();
      _prepararTrayectoria(d);
    });
  }

  void _volverAListaTelefono() {
    _detenerStreamingGps();
    setState(() {
      _enDetalleDespacho = false;
      _despachoActivo = null;
      _mostrandoFormularioEpod = false;
      _fotoCapturada = false;
      _puntosFirma.clear();
    });
  }

  void _prepararTrayectoria(Despacho d) {
    if (d.pedido != null) {
      _trayectoria = [
        const LatLng(-0.1807, -78.4678),
        LatLng(
          (-0.1807 + d.pedido!.latitudDestino) / 2,
          (-78.4678 + d.pedido!.longitudDestino) / 2,
        ),
        LatLng(d.pedido!.latitudDestino, d.pedido!.longitudDestino),
      ];
    } else {
      _trayectoria = _puntosEjemplo;
    }
    _pasoActual = 0;
  }

  Future<void> _aceptarEIniciarRuta() async {
    if (_despachoActivo == null) return;
    try {
      await ApiService.aceptarInicioRuta(_despachoActivo!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Consentimiento otorgado. Ruta iniciada y streaming GPS activado.'),
          backgroundColor: AppTheme.statusEnCurso,
        ),
      );
      _iniciarStreamingGps();
      widget.onRefresh();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar ruta: $e'), backgroundColor: AppTheme.statusAlerta),
      );
    }
  }

  Future<void> _optimizarRutaDesdeGpsChofer() async {
    final despachos = _despachosChofer;
    if (despachos.isEmpty || despachos.first.rutaId == null) return;
    final rutaId = despachos.first.rutaId!;
    final pos = _trayectoria.isNotEmpty && _pasoActual < _trayectoria.length
        ? _trayectoria[_pasoActual]
        : const LatLng(-0.1807, -78.4678);

    try {
      await ApiService.optimizarRutaChofer(rutaId, latitud: pos.latitude, longitud: pos.longitude);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paradas reordenadas según la ubicación GPS del chofer.'),
          backgroundColor: AppTheme.statusCompletada,
        ),
      );
      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al optimizar: $e'),
          backgroundColor: AppTheme.statusAlerta,
        ),
      );
    }
  }

  void _iniciarStreamingGps() {
    _streamingTimer?.cancel();
    setState(() => _streamingGps = true);

    _streamingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _emitirPasoGps();
    });
  }

  void _detenerStreamingGps() {
    _streamingTimer?.cancel();
    if (mounted) {
      setState(() => _streamingGps = false);
    }
  }

  void _emitirPasoGps() async {
    if (_trayectoria.isEmpty) return;

    if (_pasoActual >= _trayectoria.length - 1) {
      _pasoActual = 0;
    } else {
      _pasoActual++;
    }

    final pos = _trayectoria[_pasoActual];
    double rumbo = 90.0;
    if (_pasoActual < _trayectoria.length - 1) {
      final sig = _trayectoria[_pasoActual + 1];
      rumbo = _calcularRumbo(pos, sig);
    }

    widget.onPosicionSimulada(pos, rumbo);

    try {
      await ApiService.enviarTelemetria(
        choferId: _choferSeleccionado?.id,
        despachoId: _despachoActivo?.id,
        latitud: pos.latitude,
        longitud: pos.longitude,
        velocidadKmh: _velocidadKmh,
        rumbo: rumbo,
        choferNombre: _choferSeleccionado?.nombre ?? 'Chofer Simulado',
      );
    } catch (_) {}

    if (mounted) setState(() {});
  }

  double _calcularRumbo(LatLng desde, LatLng hasta) {
    final dLon = (hasta.longitude - desde.longitude);
    final y = dLon;
    final x = (hasta.latitude - desde.latitude);
    double deg = (y / (x == 0 ? 0.0001 : x)) * 57.2957795;
    if (deg < 0) deg += 360.0;
    return deg;
  }

  Future<void> _cancelarRutaVoluntaria() async {
    if (_despachoActivo == null) return;
    final motivoCtrl = TextEditingController();

    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Cancelar Despacho'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingrese el motivo de cancelación de la entrega:'),
            const SizedBox(height: 10),
            TextField(controller: motivoCtrl, decoration: const InputDecoration(labelText: 'Motivo')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusAlerta),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar Cancelación'),
          ),
        ],
      ),
    );

    if (conf == true) {
      _detenerStreamingGps();
      try {
        await ApiService.cancelarDespacho(_despachoActivo!.id, motivoCtrl.text.trim());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ruta cancelada por el chofer. Streaming GPS cortado.'),
            backgroundColor: AppTheme.statusAlerta,
          ),
        );
        widget.onRefresh();
        _volverAListaTelefono();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.statusAlerta),
        );
      }
    }
  }

  void _capturarFotoMarcaAgua() {
    setState(() {
      _fotoCapturada = true;
      _fotoTimestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fotografía capturada con marca de agua satelital.'),
        backgroundColor: AppTheme.statusCompletada,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _finalizarEntregaEpod() async {
    if (_despachoActivo == null) return;

    if (!_fotoCapturada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CP-LOG-01: Debe capturar la fotografía del material entregado.')),
      );
      return;
    }

    if (_puntosFirma.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CP-LOG-01: El receptor debe firmar en el recuadro digital.')),
      );
      return;
    }

    setState(() => _enviandoEpod = true);
    _detenerStreamingGps();

    double finalLat = _despachoActivo!.pedido?.latitudDestino ?? -0.1807;
    double finalLon = _despachoActivo!.pedido?.longitudDestino ?? -78.4678;

    if (_gpsMode == 'deviation') {
      // Simular desvío geodésico a Cumbayá (> 500m)
      finalLat = -0.2035;
      finalLon = -78.4350;
    }

    // Datos simulados de firma y foto codificadas
    final fotoBase64 = 'data:image/jpeg;base64,AlumVid_ePoD_Watermark_Photo_${DateTime.now().millisecondsSinceEpoch}';
    final firmaBase64 = 'data:image/png;base64,AlumVid_Digital_Signature_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final res = await ApiService.cerrarEntrega(
        despachoId: _despachoActivo!.id,
        fotoPodUrl: fotoBase64,
        firmaUrl: firmaBase64,
        latitud: finalLat,
        longitud: finalLon,
        comentarios: _comentariosPodCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() => _enviandoEpod = false);

      if (res.hasAlertaDesviacion) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Entrega registrada con ALERTA: Desvío de ${res.desviacionMetros?.round() ?? 0}m detectado por PostGIS.'),
            backgroundColor: AppTheme.statusAlerta,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entrega finalizada con prueba documental e-PoD válida.'),
            backgroundColor: AppTheme.statusCompletada,
          ),
        );
      }

      widget.onRefresh();
      _volverAListaTelefono();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviandoEpod = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cerrar entrega: $e'), backgroundColor: AppTheme.statusAlerta),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Columna Izquierda: Panel de Controles y Reglas
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    children: [
                      _buildCardControlesEntorno(),
                      const SizedBox(height: 14),
                      _buildCardReglasNegocio(),
                    ],
                  ),
                ),
                const SizedBox(width: 28),

                // Columna Derecha: Mockup del Smartphone del Chofer
                _buildMockupSmartphone(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardControlesEntorno() {
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
            'Controles del Entorno de Pruebas',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Este simulador permite evaluar el ciclo de vida completo de la app móvil del chofer: consentimiento, streaming GPS vía WebSocket, cancelación voluntaria y cierre documentado e-PoD.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.4),
          ),
          const Divider(color: AppTheme.border, height: 20),

          // Selector de Chofer
          DropdownButtonFormField<String>(
            key: ValueKey('chofer_select_${_choferIdSeleccionado ?? 'none'}'),
            initialValue: widget.choferes.any((c) => c.id == _choferIdSeleccionado)
                ? _choferIdSeleccionado
                : (widget.choferes.isNotEmpty ? widget.choferes.first.id : null),
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Chofer Autenticado en el Dispositivo'),
            dropdownColor: AppTheme.surfaceCard,
            items: widget.choferes.map((c) {
              return DropdownMenuItem<String>(
                value: c.id,
                child: Text(c.nombre, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _choferIdSeleccionado = val;
                _volverAListaTelefono();
              });
            },
          ),
          const SizedBox(height: 12),

          // Modo de Ubicación para Cierre
          DropdownButtonFormField<String>(
            key: ValueKey('gps_mode_$_gpsMode'),
            initialValue: _gpsMode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Modo de Ubicación para Cierre (CP-LOG-02)'),
            dropdownColor: AppTheme.surfaceCard,
            items: const [
              DropdownMenuItem(
                value: 'match',
                child: Text('Entrega en sitio acordado (Desvío < 10m)', overflow: TextOverflow.ellipsis),
              ),
              DropdownMenuItem(
                value: 'deviation',
                child: Text('Simular desvío (> 150m / Alerta Auditoría)', overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (val) => setState(() => _gpsMode = val ?? 'match'),
          ),
          const SizedBox(height: 12),

          // Slider de Velocidad
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Velocidad de Desplazamiento:', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              Text('${_velocidadKmh.toInt()} km/h', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryLight)),
            ],
          ),
          Slider(
            value: _velocidadKmh,
            min: 10,
            max: 90,
            divisions: 8,
            activeColor: AppTheme.primary,
            onChanged: (val) => setState(() => _velocidadKmh = val),
          ),
        ],
      ),
    );
  }

  Widget _buildCardReglasNegocio() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reglas de Negocio Validadas',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.statusCompletada),
          ),
          SizedBox(height: 10),
          _ReglaItem(texto: 'El chofer debe dar consentimiento expreso antes de iniciar el trayecto.'),
          _ReglaItem(texto: 'Al iniciar, se transmite telemetría continua que actualiza Google Maps en vivo.'),
          _ReglaItem(texto: 'La cancelación corta inmediatamente el envío de telemetría.'),
          _ReglaItem(texto: 'El cierre exige firma táctil, evidencia fotográfica y auditoría PostGIS.'),
        ],
      ),
    );
  }

  Widget _buildMockupSmartphone() {
    return Container(
      width: 340,
      height: 640,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: const Color(0xFF334155), width: 6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Column(
          children: [
            // Notch superior
            Container(
              height: 22,
              color: Colors.black,
              child: Center(
                child: Container(
                  width: 100,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
                  ),
                ),
              ),
            ),

            // Barra de estado del móvil
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: const Color(0xFF0B132B),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('HH:mm').format(DateTime.now()),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      Icon(Icons.gps_fixed, size: 10, color: _streamingGps ? AppTheme.statusCompletada : AppTheme.textMuted),
                      const SizedBox(width: 4),
                      const Text('GPS [ON] - 98%', style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),

            // Cabecera App Chofer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: AppTheme.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('AlumVid Chofer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('v2.0', style: TextStyle(color: AppTheme.primaryLight, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            // Cuerpo del Teléfono
            Expanded(
              child: Container(
                color: const Color(0xFF090D16),
                padding: const EdgeInsets.all(12),
                child: _enDetalleDespacho
                    ? (_mostrandoFormularioEpod ? _buildPhoneFormularioEpod() : _buildPhoneDetalleRuta())
                    : _buildPhoneListaDespachos(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Vista A del Móvil: Lista de Rutas Asignadas
  Widget _buildPhoneListaDespachos() {
    final despachos = _despachosChofer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('RUTAS ASIGNADAS HOY', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
            InkWell(
              onTap: widget.onRefresh,
              child: const Text('Actualizar', style: TextStyle(color: AppTheme.primaryLight, fontSize: 10)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (despachos.isNotEmpty && despachos.first.rutaId != null) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.primaryLight),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.near_me, size: 12, color: AppTheme.primaryLight),
              label: const Text('Optimizar Paradas (GPS Chofer)', style: TextStyle(color: AppTheme.primaryLight, fontSize: 10, fontWeight: FontWeight.bold)),
              onPressed: _optimizarRutaDesdeGpsChofer,
            ),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 2),

        Expanded(
          child: despachos.isEmpty
              ? const Center(
                  child: Text(
                    'No hay despachos asignados para este chofer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textDim, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  itemCount: despachos.length,
                  itemBuilder: (ctx, idx) {
                    final d = despachos[idx];
                    final cliente = d.pedido?.cliente ?? 'Sin cliente';
                    final dir = d.pedido?.direccionTexto ?? 'Sin dirección';

                    Color tagColor = AppTheme.statusPendiente;
                    if (d.isEnCurso) tagColor = AppTheme.statusEnCurso;
                    if (d.isEntregado) tagColor = AppTheme.statusCompletada;

                    return InkWell(
                      onTap: () => _abrirDespachoEnTelefono(d),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('PEDIDO #${d.pedidoId.length > 8 ? d.pedidoId.substring(0, 8) : d.pedidoId}', style: const TextStyle(color: AppTheme.primaryLight, fontSize: 9, fontWeight: FontWeight.bold)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(color: tagColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                  child: Text(d.estado, style: TextStyle(color: tagColor, fontSize: 8, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(cliente, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                            Text(dir, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Vista B del Móvil: Detalle y Gestión del Despacho
  Widget _buildPhoneDetalleRuta() {
    final d = _despachoActivo!;
    final cliente = d.pedido?.cliente ?? 'Sin cliente';
    final dir = d.pedido?.direccionTexto ?? 'Sin dirección';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.arrow_back, size: 12),
            label: const Text('Volver a Lista', style: TextStyle(fontSize: 10)),
            onPressed: _volverAListaTelefono,
          ),
          const SizedBox(height: 10),

          // Tarjeta de Información
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PEDIDO #${d.pedidoId.length > 8 ? d.pedidoId.substring(0, 8) : d.pedidoId}', style: const TextStyle(color: AppTheme.primaryLight, fontSize: 9, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(cliente, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(dir, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (d.isEnCurso ? AppTheme.statusEnCurso : AppTheme.statusPendiente).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(d.estado, style: TextStyle(color: d.isEnCurso ? AppTheme.statusEnCurso : AppTheme.statusPendiente, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Acción 1: Consentimiento e inicio (si está pendiente)
          if (!d.isEnCurso && !d.isEntregado) ...[
            const Text(
              'Se requiere su consentimiento expreso para dar inicio al traslado e iniciar la transmisión de ubicación satelital hacia la central.',
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusCompletada, padding: const EdgeInsets.symmetric(vertical: 10)),
                onPressed: _aceptarEIniciarRuta,
                child: const Text('Aceptar e Iniciar Ruta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          ],

          // Acción 2: En curso (Streaming activo)
          if (d.isEnCurso || _streamingGps) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sensors, color: AppTheme.primaryLight, size: 14),
                  SizedBox(width: 6),
                  Text('Streaming GPS Activo → Central Monitoreando', style: TextStyle(color: AppTheme.primaryLight, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 10)),
                    onPressed: () => setState(() => _mostrandoFormularioEpod = true),
                    child: const Text('Finalizar Entrega (e-PoD)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusAlerta, padding: const EdgeInsets.symmetric(vertical: 10)),
                    onPressed: _cancelarRutaVoluntaria,
                    child: const Text('Cancelar Ruta', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Vista C del Móvil: Formulario de Cierre e-PoD (Foto + Firma Táctil)
  Widget _buildPhoneFormularioEpod() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => setState(() => _mostrandoFormularioEpod = false),
                child: const Text('Volver', style: TextStyle(fontSize: 9)),
              ),
              const Text('Cierre de Entrega e-PoD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),

          // 1. Fotografía con Marca de Agua Técnica
          const Text('1. Fotografía de Entrega (PoD):', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          InkWell(
            onTap: _capturarFotoMarcaAgua,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _fotoCapturada ? const Color(0xFF0F2537) : AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _fotoCapturada ? AppTheme.statusCompletada : AppTheme.border, style: BorderStyle.solid),
              ),
              child: _fotoCapturada
                  ? Container(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.check_circle, color: AppTheme.statusCompletada, size: 14),
                              SizedBox(width: 4),
                              Text('EVIDENCIA FOTOGRÁFICA REGISTRADA', style: TextStyle(color: AppTheme.statusCompletada, fontSize: 8, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text('Material: Vidrio Templado 8mm AlumVid', style: TextStyle(color: Colors.white, fontSize: 8)),
                          Text('GPS: ${_trayectoria.isNotEmpty ? _trayectoria.first.latitude.toStringAsFixed(4) : "-0.1807"}, ${_trayectoria.isNotEmpty ? _trayectoria.first.longitude.toStringAsFixed(4) : "-78.4678"}', style: const TextStyle(color: AppTheme.primaryLight, fontSize: 8)),
                          Text('Fecha: $_fotoTimestamp', style: const TextStyle(color: AppTheme.textDim, fontSize: 7)),
                        ],
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, color: AppTheme.primaryLight, size: 24),
                        SizedBox(height: 4),
                        Text('Tocar para capturar foto con marca de agua', style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),

          // 2. Firma Digital Táctil
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('2. Firma Digital del Receptor:', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: () => setState(() => _puntosFirma.clear()),
                child: const Text('Limpiar', style: TextStyle(color: AppTheme.statusAlerta, fontSize: 9)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 90,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.border),
            ),
            child: GestureDetector(
              onPanUpdate: (details) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                final offset = box.globalToLocal(details.globalPosition);
                setState(() => _puntosFirma.add(offset));
              },
              onPanEnd: (_) => setState(() => _puntosFirma.add(null)),
              child: CustomPaint(
                painter: _FirmaPainter(puntos: _puntosFirma),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 3. Observaciones
          const Text('3. Observaciones:', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextField(
            controller: _comentariosPodCtrl,
            style: const TextStyle(fontSize: 10, color: Colors.white),
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8)),
          ),
          const SizedBox(height: 12),

          // Botón Confirmar y Cerrar Entrega
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusCompletada, padding: const EdgeInsets.symmetric(vertical: 10)),
              onPressed: _enviandoEpod ? null : _finalizarEntregaEpod,
              child: _enviandoEpod
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirmar y Cerrar Entrega', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReglaItem extends StatelessWidget {
  final String texto;

  const _ReglaItem({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppTheme.statusCompletada, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(texto, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

class _FirmaPainter extends CustomPainter {
  final List<Offset?> puntos;

  _FirmaPainter({required this.puntos});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF60A5FA)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;

    for (int i = 0; i < puntos.length - 1; i++) {
      if (puntos[i] != null && puntos[i + 1] != null) {
        canvas.drawLine(puntos[i]!, puntos[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FirmaPainter oldDelegate) => true;
}
