import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/chofer.dart';
import '../models/despacho.dart';
import '../models/producto.dart';
import '../models/retazo_pieza.dart';
import '../models/ruta.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

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
  // Lista de usuarios registrados en el sistema
  List<AppUser> _usuarios = [];
  AppUser? _usuarioSeleccionado;
  bool _cargandoUsuarios = true;
  String _rolActivo = 'CHOFER';

  // Configuración de GPS para simulación
  String _gpsMode = 'match'; // 'match' (<10m) o 'deviation' (>150m)
  double _velocidadKmh = 42.0;

  // Estado del flujo del Chofer en el móvil
  Ruta? _rutaActiva;
  Despacho? _paradaActiva;
  bool _enNavegacion = false;
  bool _enEpod = false;

  // Telemetría continua
  bool _streamingGps = false;
  Timer? _streamingTimer;
  int _pasoActual = 0;
  List<LatLng> _trayectoria = [];
  LatLng _posicionVehiculo = const LatLng(-0.1807, -78.4678);
  double _rumboVehiculo = 90.0;
  final MapController _miniMapCtrl = MapController();

  // Evidencia e-PoD
  bool _fotoCapturada = false;
  String _fotoTimestamp = '';
  final List<Offset?> _puntosFirma = [];
  final TextEditingController _comentariosPodCtrl = TextEditingController(text: 'Material recibido conforme y verificado en obra.');
  bool _enviandoEpod = false;

  // Datos para vista Bodeguero
  List<Producto> _stockBodega = [];
  List<ProductoRetazo> _retazosBodega = [];
  bool _cargandoBodega = false;
  int _tabBodega = 0; // 0: stock, 1: retazos, 2: cortadora

  // Datos para vista Vendedor
  List<Producto> _catalogoVentas = [];
  bool _cargandoVentas = false;
  final _metrosCotizarCtrl = TextEditingController(text: '3.0');
  Producto? _productoCotizar;



  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
  }

  @override
  void dispose() {
    _streamingTimer?.cancel();
    _comentariosPodCtrl.dispose();
    _metrosCotizarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarUsuarios() async {
    setState(() => _cargandoUsuarios = true);
    try {
      final list = await ApiService.obtenerUsuariosAdmin();
      if (!mounted) return;
      setState(() {
        _usuarios = list;
        _cargandoUsuarios = false;

        // Seleccionar por defecto un usuario con rol CHOFER si existe, o el primero
        if (list.isNotEmpty) {
          final choferUser = list.firstWhere(
            (u) => u.roles.contains('CHOFER'),
            orElse: () => list.first,
          );
          _usuarioSeleccionado = choferUser;
          _rolActivo = choferUser.roles.contains('CHOFER')
              ? 'CHOFER'
              : (choferUser.roles.isNotEmpty ? choferUser.roles.first : 'CHOFER');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoUsuarios = false);
      AppToast.error(context, 'Error al cargar usuarios: $e');
    }
  }

  Future<void> _cargarDatosBodega() async {
    if (_cargandoBodega || _stockBodega.isNotEmpty) return;
    setState(() => _cargandoBodega = true);
    try {
      final prodsRes = await ApiService.obtenerProductos(size: 50);
      final List<Producto> prods = prodsRes['items'] as List<Producto>? ?? [];
      final retazos = await ApiService.obtenerProductosRetazos();
      if (mounted) {
        setState(() {
          _stockBodega = prods;
          _retazosBodega = retazos;
          _cargandoBodega = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoBodega = false);
    }
  }

  Future<void> _cargarDatosVentas() async {
    if (_cargandoVentas || _catalogoVentas.isNotEmpty) return;
    setState(() => _cargandoVentas = true);
    try {
      final prodsRes = await ApiService.obtenerProductos(size: 50);
      final List<Producto> prods = prodsRes['items'] as List<Producto>? ?? [];
      if (mounted) {
        setState(() {
          _catalogoVentas = prods;
          if (prods.isNotEmpty) _productoCotizar = prods.first;
          _cargandoVentas = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoVentas = false);
    }
  }

  // Rutas asignadas al chofer seleccionado o fallback para pruebas
  List<Ruta> get _rutasChofer {
    if (_usuarioSeleccionado == null) return widget.rutas;

    final uName = _usuarioSeleccionado!.fullName.toLowerCase();
    final uId = _usuarioSeleccionado!.id;

    final asignadas = widget.rutas.where((r) {
      if (r.choferId != null && r.choferId == uId) return true;
      if (r.choferNombre != null && r.choferNombre!.toLowerCase().contains(uName)) return true;
      if (widget.choferes.any((c) => c.nombre.toLowerCase().contains(uName) && r.choferId == c.id)) return true;
      return false;
    }).toList();

    // Si este chofer tiene rutas asignadas, mostrar las suyas; si no, mostrar todas para que el admin pueda simular
    return asignadas.isNotEmpty ? asignadas : widget.rutas;
  }

  void _abrirRutaEnTelefono(Ruta r) {
    setState(() {
      _rutaActiva = r;
      _paradaActiva = null;
      _enNavegacion = false;
      _enEpod = false;
    });
  }

  void _iniciarNavegacionParada(Despacho p) {
    _detenerStreamingGps();

    // Generar trayectoria hacia la parada
    final destino = LatLng(p.latitud, p.longitud);
    final List<LatLng> camino = [
      const LatLng(-0.089290, -78.439607), // Inicio Bodega
      LatLng((-0.089290 + destino.latitude) * 0.7, (-78.439607 + destino.longitude) * 0.7),
      LatLng((-0.089290 + destino.latitude) * 0.4, (-78.439607 + destino.longitude) * 0.4),
      destino,
    ];

    setState(() {
      _paradaActiva = p;
      _enNavegacion = true;
      _enEpod = false;
      _trayectoria = camino;
      _pasoActual = 0;
      _posicionVehiculo = camino.first;
      _fotoCapturada = false;
      _puntosFirma.clear();
    });

    _iniciarStreamingGps();
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
      final dLon = sig.longitude - pos.longitude;
      final dLat = sig.latitude - pos.latitude;
      rumbo = (dLon / (dLat == 0 ? 0.0001 : dLat)) * 57.2957;
      if (rumbo < 0) rumbo += 360.0;
    }

    setState(() {
      _posicionVehiculo = pos;
      _rumboVehiculo = rumbo;
    });

    widget.onPosicionSimulada(pos, rumbo);

    try {
      await ApiService.enviarTelemetria(
        choferId: _usuarioSeleccionado?.id,
        despachoId: _paradaActiva?.id,
        latitud: pos.latitude,
        longitud: pos.longitude,
        velocidadKmh: _velocidadKmh,
        rumbo: rumbo,
        choferNombre: _usuarioSeleccionado?.fullName ?? 'Chofer Simulado',
      );
    } catch (_) {}
  }

  Future<void> _marcarParadaFallida(Despacho p) async {
    String motivo = 'Cliente Ausente';
    final motivos = [
      'Cliente Ausente',
      'Dirección No Encontrada',
      'Rechazo de Mercadería / Material Incorrecto',
      'Problemas de Acceso a Obra',
      'Vehículo con Desperfecto Mecánico',
      'Otro motivo',
    ];

    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: const Color(0xFF101728),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF1E293B))),
          title: const Row(
            children: [
              Icon(Icons.report_problem_rounded, color: Color(0xFFEF4444), size: 20),
              SizedBox(width: 8),
              Text('Marcar Parada como Fallida', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Parada: ${p.cliente} (${p.direccionTexto})', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              const SizedBox(height: 14),
              const Text('Seleccione el motivo del fallo en la entrega:', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('motivo_$motivo'),
                initialValue: motivo,
                dropdownColor: const Color(0xFF0F172A),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(isDense: true),
                items: motivos.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (val) => setDState(() => motivo = val ?? motivos.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8)))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar Fallida'),
            ),
          ],
        ),
      ),
    );

    if (conf == true) {
      try {
        await ApiService.cancelarDespacho(p.id, motivo);
        if (!mounted) return;
        AppToast.info(context, 'Parada marcada como no entregada (Fallida: $motivo)');
        widget.onRefresh();
        setState(() {});
      } catch (e) {
        if (!mounted) return;
        AppToast.error(context, 'Error: $e');
      }
    }
  }

  Future<void> _reintentarParada(Despacho p) async {
    try {
      await ApiService.reintentarParada(p.id);
      if (!mounted) return;
      AppToast.success(context, 'Parada reactivada para un nuevo intento de entrega.');
      widget.onRefresh();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Error al reactivar parada: $e');
    }
  }

  Future<void> _optimizarRutaChofer(Ruta r) async {
    try {
      await ApiService.optimizarRutaChofer(r.id, latitud: _posicionVehiculo.latitude, longitud: _posicionVehiculo.longitude);
      if (!mounted) return;
      AppToast.success(context, 'Paradas optimizadas por menor tiempo de viaje.');
      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Error al optimizar: $e');
    }
  }

  void _capturarFotoSimulada() {
    setState(() {
      _fotoCapturada = true;
      _fotoTimestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    });
    AppToast.success(context, 'Fotografía satelital con marca de agua capturada.');
  }

  Future<void> _finalizarEntregaEpod() async {
    if (_paradaActiva == null) return;

    if (!_fotoCapturada) {
      AppToast.error(context, 'Debe capturar la fotografía de la entrega.');
      return;
    }

    if (_puntosFirma.isEmpty) {
      AppToast.error(context, 'El cliente receptor debe firmar en el recuadro digital.');
      return;
    }

    setState(() => _enviandoEpod = true);
    _detenerStreamingGps();

    double finalLat = _paradaActiva!.latitud;
    double finalLon = _paradaActiva!.longitud;

    if (_gpsMode == 'deviation') {
      // Simular desvío geodésico (> 500m)
      finalLat = -0.2035;
      finalLon = -78.4350;
    }

    final fotoBase64 = 'data:image/jpeg;base64,AlumVid_ePoD_Watermark_${DateTime.now().millisecondsSinceEpoch}';
    final firmaBase64 = 'data:image/png;base64,AlumVid_Signature_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final res = await ApiService.cerrarEntrega(
        despachoId: _paradaActiva!.id,
        fotoPodUrl: fotoBase64,
        firmaUrl: firmaBase64,
        latitud: finalLat,
        longitud: finalLon,
        comentarios: _comentariosPodCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _enviandoEpod = false;
        _enEpod = false;
        _enNavegacion = false;
        _paradaActiva = null;
      });

      if (res.hasAlertaDesviacion) {
        AppToast.error(context, 'Entrega documentada con ALERTA: Desvío de ${res.desviacionMetros?.round() ?? 0}m detectado por PostGIS.');
      } else {
        AppToast.success(context, '¡Entrega cerrada exitosamente con prueba documental e-PoD!');
      }

      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviandoEpod = false);
      AppToast.error(context, 'Error al cerrar entrega: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF070B14),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera superior
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Simulador de Dispositivo Móvil AlumVid',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Prueba la experiencia móvil interactiva de cualquier cuenta de empleado de la empresa en tiempo real.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: const Color(0xFF38BDF8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Actualizar Datos'),
                  onPressed: () {
                    _cargarUsuarios();
                    widget.onRefresh();
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Distribución en 2 Columnas: Izquierda (Controles Administrador), Derecha (Mockup Smartphone)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ==============================
                // COLUMNA IZQUIERDA: CONTROLES DEL ENTORNO
                // ==============================
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _buildCardSelectorUsuario(),
                      const SizedBox(height: 14),
                      _buildCardControlesSimulacion(),
                      const SizedBox(height: 14),
                      _buildCardReglasNegocio(),
                    ],
                  ),
                ),
                const SizedBox(width: 24),

                // ==============================
                // COLUMNA DERECHA: SMARTPHONE MOCKUP
                // ==============================
                _buildMockupSmartphone(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Card 1: Selector de Usuario y Roles
  Widget _buildCardSelectorUsuario() {
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
          const Row(
            children: [
              Icon(Icons.person_pin_rounded, color: Color(0xFF38BDF8), size: 18),
              SizedBox(width: 8),
              Text(
                'Seleccionar Cuenta de Empleado a Simular',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Elige a cualquier colaborador de la empresa para ver y utilizar la aplicación móvil tal como aparece en su teléfono.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.3),
          ),
          const Divider(color: AppTheme.border, height: 20),

          if (_cargandoUsuarios)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else if (_usuarios.isEmpty)
            const Text('No se encontraron usuarios registrados.', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12))
          else ...[
            DropdownButtonFormField<AppUser>(
              key: ValueKey('user_sel_${_usuarioSeleccionado?.id}'),
              initialValue: _usuarioSeleccionado,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceCard,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Usuario / Colaborador Autenticado',
                isDense: true,
                prefixIcon: Icon(Icons.badge_rounded, size: 18),
              ),
              items: _usuarios.map((u) {
                final rolesStr = u.roles.join(', ');
                return DropdownMenuItem<AppUser>(
                  value: u,
                  child: Text(
                    '${u.fullName} ($rolesStr)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _usuarioSeleccionado = val;
                    _rolActivo = val.roles.contains('CHOFER')
                        ? 'CHOFER'
                        : (val.roles.isNotEmpty ? val.roles.first : 'CHOFER');
                    _rutaActiva = null;
                    _paradaActiva = null;
                    _enNavegacion = false;
                    _enEpod = false;
                    _detenerStreamingGps();
                  });
                  if (_rolActivo == 'BODEGUERO') _cargarDatosBodega();
                  if (_rolActivo == 'VENDEDOR') _cargarDatosVentas();
                }
              },
            ),
            const SizedBox(height: 12),

            // Tarjeta de perfil del empleado seleccionado
            if (_usuarioSeleccionado != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF090E1A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF1D72FE).withValues(alpha: 0.2),
                          child: Text(
                            _usuarioSeleccionado!.fullName.isNotEmpty ? _usuarioSeleccionado!.fullName[0].toUpperCase() : 'U',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _usuarioSeleccionado!.fullName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                '${_usuarioSeleccionado!.email} • Cédula: ${_usuarioSeleccionado!.identification}',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Selector de Rol Activo para Simulación
                    const Text('Cambiar modo de vista móvil según rol:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: ['CHOFER', 'BODEGUERO', 'VENDEDOR'].map((r) {
                        final esActivo = _rolActivo == r;
                        return ChoiceChip(
                          label: Text(r == 'CHOFER' ? '📱 Chofer / Rutas' : (r == 'BODEGUERO' ? '📦 Bodeguero' : '💼 Vendedor')),
                          selected: esActivo,
                          selectedColor: const Color(0xFF1D72FE),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _rolActivo = r;
                                _rutaActiva = null;
                                _paradaActiva = null;
                                _enNavegacion = false;
                                _enEpod = false;
                                _detenerStreamingGps();
                              });
                              if (r == 'BODEGUERO') _cargarDatosBodega();
                              if (r == 'VENDEDOR') _cargarDatosVentas();
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // Card 2: Controles de Simulación GPS y Auditoría
  Widget _buildCardControlesSimulacion() {
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
          const Text('Controles del Entorno de Pruebas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
          const SizedBox(height: 8),

          // Modo de Ubicación para Cierre
          DropdownButtonFormField<String>(
            key: ValueKey('gps_mode_$_gpsMode'),
            initialValue: _gpsMode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Modo de Ubicación para Cierre (CP-LOG-02)',
              isDense: true,
            ),
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

          // Velocidad del vehículo simulado
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

          // Estado del Streaming
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF090E1A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _streamingGps ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                      size: 16,
                      color: _streamingGps ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _streamingGps ? 'Transmisión GPS en vivo activa' : 'GPS en reposo (Inicia navegación para transmitir)',
                      style: TextStyle(
                        color: _streamingGps ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (_streamingGps)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _detenerStreamingGps,
                    child: const Text('Pausar GPS', style: TextStyle(fontSize: 10)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card 3: Reglas de Negocio Validadas
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
          Text('Reglas de Negocio Validadas en la App Móvil', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.statusCompletada)),
          SizedBox(height: 10),
          _ReglaItem(texto: 'El chofer selecciona la ruta y decide el orden de entrega o la optimiza.'),
          _ReglaItem(texto: 'Solo puede haber una parada en curso a la vez por unidad de transporte.'),
          _ReglaItem(texto: 'La cancelación o fallo exige registrar el motivo para reintento posterior.'),
          _ReglaItem(texto: 'El cierre exige firma digital, foto con marca de agua y auditoría PostGIS.'),
        ],
      ),
    );
  }

  // ==========================================
  // SMARTPHONE MOCKUP
  // ==========================================
  Widget _buildMockupSmartphone() {
    return Container(
      width: 360,
      height: 680,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(38),
        border: Border.all(color: const Color(0xFF334155), width: 6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            spreadRadius: 6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Column(
          children: [
            // Notch
            Container(
              height: 24,
              color: Colors.black,
              child: Center(
                child: Container(
                  width: 90,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
                  ),
                ),
              ),
            ),

            // Barra de estado del teléfono
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
                      Icon(Icons.wifi, size: 11, color: Colors.white.withValues(alpha: 0.8)),
                      const SizedBox(width: 4),
                      Icon(Icons.gps_fixed, size: 10, color: _streamingGps ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      const Text('100%', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),

            // Barra de la App Móvil
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: AppTheme.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFF1D72FE).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.blur_on_rounded, color: Color(0xFF38BDF8), size: 16),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('AlumVid Móvil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          Text(
                            _usuarioSeleccionado?.fullName ?? 'Empleado',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D72FE).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _rolActivo,
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            // Pantalla interior del teléfono
            Expanded(
              child: Container(
                color: const Color(0xFF090D16),
                child: _rolActivo == 'CHOFER'
                    ? _buildInteriorChofer()
                    : (_rolActivo == 'BODEGUERO' ? _buildInteriorBodeguero() : _buildInteriorVendedor()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CONTENIDO DEL SMARTPHONE: CHOFER
  // ==========================================
  Widget _buildInteriorChofer() {
    if (_enEpod) return _buildPhoneEpod();
    if (_enNavegacion) return _buildPhoneNavegacion();
    if (_rutaActiva != null) return _buildPhoneDetalleRuta();
    return _buildPhoneListaRutas();
  }

  // Vista 1 Chofer: Lista de Rutas Asignadas
  Widget _buildPhoneListaRutas() {
    final rutas = _rutasChofer;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('HOJAS DE RUTA ASIGNADAS', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: widget.onRefresh,
                child: const Text('Actualizar', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Expanded(
            child: rutas.isEmpty
                ? const Center(
                    child: Text(
                      'No hay rutas registradas.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    itemCount: rutas.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (ctx, idx) {
                      final r = rutas[idx];
                      final entregadas = r.paradas.where((p) => p.isEntregado).length;
                      final total = r.paradas.length;
                      final ratio = total > 0 ? (entregadas / total) : 0.0;

                      Color estadoColor = const Color(0xFFFBBF24);
                      if (r.isEnCurso) estadoColor = const Color(0xFF38BDF8);
                      if (r.isCompletada) estadoColor = const Color(0xFF10B981);
                      if (r.estado == 'CANCELADA') estadoColor = const Color(0xFFEF4444);

                      return InkWell(
                        onTap: () => _abrirRutaEnTelefono(r),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101728),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF1E293B)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    r.codigoRuta,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: estadoColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                    child: Text(
                                      r.estado,
                                      style: TextStyle(color: estadoColor, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$total Destinos de Entrega Programados',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: ratio,
                                backgroundColor: const Color(0xFF1E293B),
                                valueColor: AlwaysStoppedAnimation<Color>(estadoColor),
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$entregadas de $total entregas completadas',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 9),
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
    );
  }

  // Vista 2 Chofer: Detalle de Ruta con Paradas
  Widget _buildPhoneDetalleRuta() {
    final r = _rutaActiva!;
    final entregadas = r.paradas.where((p) => p.isEntregado).length;
    final total = r.paradas.length;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => setState(() => _rutaActiva = null),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: Color(0xFF38BDF8)),
                    SizedBox(width: 4),
                    Text('Rutas', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF38BDF8)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.auto_mode_rounded, size: 12, color: Color(0xFF38BDF8)),
                label: const Text('Optimizar', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                onPressed: () => _optimizarRutaChofer(r),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Banner de Ruta
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF101728),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.codigoRuta, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('$entregadas de $total paradas documentadas', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF1D72FE).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(r.estado, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          const Text('DESTINOS DE ENTREGA DE ESTA RUTA', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),

          Expanded(
            child: r.paradas.isEmpty
                ? const Center(child: Text('Esta ruta aún no tiene paradas agregadas.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)))
                : ListView.separated(
                    itemCount: r.paradas.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (ctx, idx) {
                      final p = r.paradas[idx];
                      final bool esEntregado = p.isEntregado;
                      final bool esFallida = p.isNoEntregado;

                      Color badgeColor = const Color(0xFFFBBF24);
                      if (esEntregado) badgeColor = const Color(0xFF10B981);
                      if (esFallida) badgeColor = const Color(0xFFEF4444);

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101728),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: esFallida ? const Color(0xFFEF4444).withValues(alpha: 0.4) : const Color(0xFF1E293B)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Parada #${idx + 1}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                  child: Text(p.estado, style: TextStyle(color: badgeColor, fontSize: 8, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(p.cliente, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            Text(p.direccionTexto, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (p.comentarios != null && p.comentarios!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(p.comentarios!, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                            const SizedBox(height: 8),

                            if (esEntregado)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF10B981)),
                                    SizedBox(width: 4),
                                    Text('Entrega Finalizada y Documentada con e-PoD', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              )
                            else if (esFallida) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFF59E0B),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(Icons.replay_rounded, size: 12),
                                      label: const Text('Reintentar Parada', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                      onPressed: () => _reintentarParada(p),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1D72FE),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(Icons.navigation_rounded, size: 12),
                                      label: const Text('Iniciar Navegación', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                      onPressed: () => _iniciarNavegacionParada(p),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    flex: 4,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Color(0xFFEF4444)),
                                        foregroundColor: const Color(0xFFEF4444),
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(Icons.close_rounded, size: 12),
                                      label: const Text('Fallida', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                      onPressed: () => _marcarParadaFallida(p),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Vista 3 Chofer: Navegación Vial y Streaming GPS
  Widget _buildPhoneNavegacion() {
    final p = _paradaActiva!;

    return Column(
      children: [
        // Cabecera Navegación
        Container(
          padding: const EdgeInsets.all(10),
          color: const Color(0xFF101728),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () {
                      _detenerStreamingGps();
                      setState(() => _enNavegacion = false);
                    },
                    child: const Row(
                      children: [
                        Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: Color(0xFF38BDF8)),
                        SizedBox(width: 4),
                        Text('Itinerario', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _streamingGps ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF64748B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sensors, size: 10, color: _streamingGps ? const Color(0xFF10B981) : const Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(_streamingGps ? 'GPS EN VIVO' : 'PAUSA', style: TextStyle(color: _streamingGps ? const Color(0xFF10B981) : const Color(0xFF64748B), fontSize: 8, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Destino: ${p.cliente}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              Text(p.direccionTexto, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),

        // Mapa de Navegación Mini
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _miniMapCtrl,
                options: MapOptions(
                  initialCenter: _posicionVehiculo,
                  initialZoom: 14.5,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.alumvid.admin',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _trayectoria,
                        color: const Color(0xFF38BDF8),
                        strokeWidth: 4.0,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      // Destino
                      Marker(
                        point: LatLng(p.latitud, p.longitud),
                        width: 28,
                        height: 28,
                        child: const Icon(Icons.location_on, color: Color(0xFFEF4444), size: 28),
                      ),
                      // Camión AlumVid en movimiento
                      Marker(
                        point: _posicionVehiculo,
                        width: 28,
                        height: 28,
                        child: Transform.rotate(
                          angle: (_rumboVehiculo * 3.14159 / 180),
                          child: Container(
                            decoration: const BoxDecoration(color: Color(0xFF1D72FE), shape: BoxShape.circle),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Botón de centrado de mapa
              Positioned(
                top: 8,
                right: 8,
                child: FloatingActionButton.small(
                  backgroundColor: const Color(0xEE101728),
                  child: const Icon(Icons.my_location, color: Color(0xFF38BDF8), size: 16),
                  onPressed: () => _miniMapCtrl.move(_posicionVehiculo, 15.0),
                ),
              ),
            ],
          ),
        ),

        // Barra inferior: Velocidad y botón e-PoD
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF101728),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Velocidad: ${_velocidadKmh.toInt()} km/h', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                  Text(
                    'Paso ${_pasoActual + 1} de ${_trayectoria.length}',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.assignment_turned_in_rounded, size: 16),
                  label: const Text('Finalizar Entrega (e-PoD)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () => setState(() => _enEpod = true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Vista 4 Chofer: Formulario e-PoD (Foto + Firma Digital)
  Widget _buildPhoneEpod() {
    final p = _paradaActiva!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => setState(() => _enEpod = false),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: Color(0xFF38BDF8)),
                    SizedBox(width: 4),
                    Text('Volver', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Text('Prueba de Entrega (e-PoD)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),

          Text('Cliente: ${p.cliente}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          Text(p.direccionTexto, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
          const Divider(color: Color(0xFF1E293B), height: 16),

          // 1. Fotografía Satelital
          const Text('1. Fotografía del Material Entregado:', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _capturarFotoSimulada,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 90,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _fotoCapturada ? const Color(0xFF064E3B).withValues(alpha: 0.3) : const Color(0xFF101728),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _fotoCapturada ? const Color(0xFF10B981) : const Color(0xFF1E293B)),
              ),
              child: _fotoCapturada
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                              SizedBox(width: 4),
                              Text('FOTO REGISTRADA CON WATERMARK', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('GPS: ${_posicionVehiculo.latitude.toStringAsFixed(4)}, ${_posicionVehiculo.longitude.toStringAsFixed(4)}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9)),
                          Text('Timestamp: $_fotoTimestamp', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 8)),
                        ],
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_rounded, color: Color(0xFF38BDF8), size: 24),
                        SizedBox(height: 4),
                        Text('Tocar para capturar foto en vivo', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // 2. Firma Digital
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('2. Firma Digital del Receptor:', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: () => setState(() => _puntosFirma.clear()),
                child: const Text('Limpiar', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 90,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
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
          const SizedBox(height: 10),

          // 3. Observaciones
          const Text('3. Observaciones:', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextField(
            controller: _comentariosPodCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 11),
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8)),
          ),
          const SizedBox(height: 14),

          // Botón Final
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: _enviandoEpod ? null : _finalizarEntregaEpod,
              child: _enviandoEpod
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirmar y Cerrar Entrega', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // CONTENIDO DEL SMARTPHONE: BODEGUERO
  // ==========================================
  Widget _buildInteriorBodeguero() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('BODEGA & INVENTARIO', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: _cargarDatosBodega,
                child: const Text('Refrescar', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Tabs Bodega
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Stock', style: TextStyle(fontSize: 10)),
                  selected: _tabBodega == 0,
                  selectedColor: const Color(0xFF1D72FE),
                  onSelected: (val) => setState(() => _tabBodega = 0),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Retazos', style: TextStyle(fontSize: 10)),
                  selected: _tabBodega == 1,
                  selectedColor: const Color(0xFF1D72FE),
                  onSelected: (val) {
                    setState(() => _tabBodega = 1);
                    _cargarDatosBodega();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Expanded(
            child: _cargandoBodega
                ? const Center(child: CircularProgressIndicator())
                : (_tabBodega == 0 ? _buildTabStockBodega() : _buildTabRetazosBodega()),
          ),
        ],
      ),
    );
  }

  Widget _buildTabStockBodega() {
    if (_stockBodega.isEmpty) {
      return Center(
        child: ElevatedButton(
          onPressed: _cargarDatosBodega,
          child: const Text('Cargar Stock de Bodega'),
        ),
      );
    }
    return ListView.separated(
      itemCount: _stockBodega.length,
      separatorBuilder: (_, index) => const SizedBox(height: 6),
      itemBuilder: (ctx, idx) {
        final p = _stockBodega[idx];
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF101728), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF1E293B))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    Text('Cat: ${p.category}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF1D72FE).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                child: Text('${p.stock} ${p.unit}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabRetazosBodega() {
    if (_retazosBodega.isEmpty) {
      return const Center(child: Text('No hay retazos registrados.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)));
    }
    return ListView.separated(
      itemCount: _retazosBodega.length,
      separatorBuilder: (_, index) => const SizedBox(height: 6),
      itemBuilder: (ctx, idx) {
        final r = _retazosBodega[idx];
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF101728), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF1E293B))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('Tipo: ${r.kind ?? "General"}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9)),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // CONTENIDO DEL SMARTPHONE: VENDEDOR
  // ==========================================
  Widget _buildInteriorVendedor() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('VENTAS & COTIZADOR MÓVIL', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: _cargarDatosVentas,
                child: const Text('Refrescar', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_cargandoVentas)
            const Center(child: CircularProgressIndicator())
          else if (_catalogoVentas.isEmpty)
            Center(child: ElevatedButton(onPressed: _cargarDatosVentas, child: const Text('Cargar Catálogo Comercial')))
          else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF101728), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF1E293B))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Simulador Rápido de Cotización', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<Producto>(
                    key: ValueKey('cotiz_prod_${_productoCotizar?.id}'),
                    initialValue: _productoCotizar,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF0F172A),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    decoration: const InputDecoration(isDense: true, labelText: 'Producto'),
                    items: _catalogoVentas.map((p) => DropdownMenuItem(value: p, child: Text(p.name, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (val) => setState(() => _productoCotizar = val),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _metrosCotizarCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                          decoration: const InputDecoration(isDense: true, labelText: 'Metros / Cant.'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Builder(
                        builder: (_) {
                          final cant = double.tryParse(_metrosCotizarCtrl.text) ?? 1.0;
                          final total = cant * 18.50; // Precio referencial AlumVid
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Total Estimado:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9)),
                              Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            const Text('CATÁLOGO DE PRODUCTOS', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.separated(
                itemCount: _catalogoVentas.length,
                separatorBuilder: (_, index) => const SizedBox(height: 6),
                itemBuilder: (ctx, idx) {
                  final p = _catalogoVentas[idx];
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFF101728), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF1E293B))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                              Text('Unidad: ${p.unit} • Stock: ${p.stock}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFF38BDF8)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
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
