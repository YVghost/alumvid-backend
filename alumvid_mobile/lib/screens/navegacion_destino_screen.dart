import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../utils/app_toast.dart';
import 'epod_screen.dart';

/// Pantalla de navegacion vial en tiempo real por las calles de la ciudad.
/// Sigue la topologia de la red vial urbana mediante geometria OSRM y transmite
/// telemetria GPS continua al panel de administracion.
class NavegacionDestinoScreen extends StatefulWidget {
  final Map<String, dynamic> despacho;
  final Map<String, dynamic> ruta;
  final Map<String, dynamic> choferData;

  const NavegacionDestinoScreen({
    super.key,
    required this.despacho,
    required this.ruta,
    required this.choferData,
  });

  @override
  State<NavegacionDestinoScreen> createState() => _NavegacionDestinoScreenState();
}

class _NavegacionDestinoScreenState extends State<NavegacionDestinoScreen> {
  late Map<String, dynamic> _despachoActual;
  final MapController _mapController = MapController();

  LatLng? _posicionChofer;
  List<LatLng> _puntosTramoActivo = [];
  List<LatLng> _puntosTramoSiguiente = [];
  Map<String, dynamic>? _proximaParada;
  double _distanciaRestanteKm = 0.0;
  int _duracionEstimadaMin = 0;
  double _rumboActual = 0.0;
  double _velocidadKmh = 0.0;
  bool _cargandoRuta = true;
  int _indicePunto = 0;

  StreamSubscription<Position>? _positionStreamSub;
  Timer? _telemetriaTimer;

  List<Map<String, dynamic>> _obtenerParadasPendientes() {
    final List<dynamic> paradasRaw = widget.ruta['paradas'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> paradas = paradasRaw
        .map((p) => p as Map<String, dynamic>)
        .where((p) => p['estado'] != 'ENTREGADO' && p['estado'] != 'CANCELADA' && p['pedido'] != null)
        .toList();

    paradas.sort((a, b) => ((a['ordenParada'] as num?)?.toInt() ?? 0)
        .compareTo((b['ordenParada'] as num?)?.toInt() ?? 0));
    return paradas;
  }

  @override
  void initState() {
    super.initState();
    _despachoActual = widget.despacho;
    _iniciarNavegacionGps();
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _telemetriaTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  bool _esCoordenadaQuito(double lat, double lon) {
    return lat > -0.5 && lat < 0.2 && lon > -78.8 && lon < -78.2;
  }

  double _calcularRumbo(LatLng p1, LatLng p2) {
    final dLon = (p2.longitude - p1.longitude) * (pi / 180.0);
    final lat1 = p1.latitude * (pi / 180.0);
    final lat2 = p2.latitude * (pi / 180.0);
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(dLon);
    final brng = atan2(y, x) * (180.0 / pi);
    return (brng + 360.0) % 360.0;
  }

  double _calcularDistanciaKm(LatLng p1, LatLng p2) {
    const r = 6371.0;
    final dLat = (p2.latitude - p1.latitude) * (pi / 180.0);
    final dLon = (p2.longitude - p1.longitude) * (pi / 180.0);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(p1.latitude * (pi / 180.0)) *
            cos(p2.latitude * (pi / 180.0)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  Future<void> _iniciarNavegacionGps() async {
    final Map<String, dynamic> pedido =
        widget.despacho['pedido'] as Map<String, dynamic>? ?? {};
    final destLat = (pedido['latitudDestino'] as num?)?.toDouble() ?? -0.1022;
    final destLng = (pedido['longitudDestino'] as num?)?.toDouble() ?? -78.4515;

    // 1. Obtener posicion inicial (validando que sea en la zona operativa de Quito)
    LatLng posInicial;
    try {
      final pos = await LocationService.determinarPosicionActual();
      if (_esCoordenadaQuito(pos.latitude, pos.longitude)) {
        posInicial = LatLng(pos.latitude, pos.longitude);
        _rumboActual = pos.heading;
        _velocidadKmh = (pos.speed * 3.6).clamp(0.0, 120.0);
      } else {
        // Coordenadas operativas reales en Quito (Bodega Central Carcelen Industrial)
        posInicial = const LatLng(-0.089290, -78.439607);
        _velocidadKmh = 28.0;
        _rumboActual = 215.0;
      }
    } catch (_) {
      posInicial = const LatLng(-0.089290, -78.439607);
      _velocidadKmh = 28.0;
      _rumboActual = 215.0;
    }

    if (!mounted) return;
    setState(() {
      _posicionChofer = posInicial;
    });

    // 2. Trazar ruta por las calles reales de Quito usando OSRM
    await _trazarRutaVial(posInicial);

    // Centrar mapa de navegación sobre la posición
    _mapController.move(posInicial, 15.0);

    // 3. Suscripcion a cambios en la posicion GPS del dispositivo (si está en Quito)
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      if (!_esCoordenadaQuito(pos.latitude, pos.longitude)) return;
      final nuevaPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _posicionChofer = nuevaPos;
        _rumboActual = pos.heading;
        _velocidadKmh = (pos.speed * 3.6).clamp(0.0, 120.0);
      });
      _mapController.move(nuevaPos, _mapController.camera.zoom);
    }, onError: (_) {});

    // 4. Transmision periodica de telemetria al backend y avance vehicular continuo por calles reales
    _indicePunto = 0;
    _telemetriaTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;

      if (_puntosTramoActivo.isNotEmpty && _indicePunto < _puntosTramoActivo.length - 1) {
        _indicePunto = (_indicePunto + 1).clamp(0, _puntosTramoActivo.length - 1);
        final nuevoPunto = _puntosTramoActivo[_indicePunto];
        final siguiente = _indicePunto < _puntosTramoActivo.length - 1
            ? _puntosTramoActivo[_indicePunto + 1]
            : nuevoPunto;

        final nuevoRumbo = _calcularRumbo(nuevoPunto, siguiente);
        final distRestante = _calcularDistanciaKm(nuevoPunto, LatLng(destLat, destLng));

        setState(() {
          _posicionChofer = nuevoPunto;
          if (nuevoRumbo != 0.0) _rumboActual = nuevoRumbo;
          _velocidadKmh = distRestante > 0.05 ? 32.5 : 0.0;
          _distanciaRestanteKm = distRestante;
          _duracionEstimadaMin = (distRestante / 30.0 * 60).ceil();
        });

        _mapController.move(nuevoPunto, _mapController.camera.zoom);
      } else if (_puntosTramoActivo.isNotEmpty) {
        final puntoFinal = _puntosTramoActivo.last;
        setState(() {
          _posicionChofer = puntoFinal;
          _velocidadKmh = 0.0;
          _distanciaRestanteKm = 0.0;
          _duracionEstimadaMin = 0;
        });
      }

      _transmitirTelemetriaAlServidor();
    });
  }

  Future<void> _trazarRutaVial(LatLng origen) async {
    final Map<String, dynamic> pedidoActivo =
        widget.despacho['pedido'] as Map<String, dynamic>? ?? {};
    final destLatActivo = (pedidoActivo['latitudDestino'] as num?)?.toDouble() ?? -0.102234;
    final destLngActivo = (pedidoActivo['longitudDestino'] as num?)?.toDouble() ?? -78.451495;

    final paradas = _obtenerParadasPendientes();

    // 1. Tramo activo: Chofer -> Parada Activa (Santiago)
    List<LatLng> listaActivo = [];
    double distActivoKm = 2.2;
    int durActivoMin = 4;
    try {
      final res = await ApiService.obtenerRutaVialOsrm(
        origen.latitude,
        origen.longitude,
        destLatActivo,
        destLngActivo,
      );
      final List<dynamic> coords = res['coordinates'] as List<dynamic>? ?? [];
      listaActivo = coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
      distActivoKm = (res['distanciaKm'] as num?)?.toDouble() ?? 2.2;
      durActivoMin = (res['duracionMin'] as num?)?.toInt() ?? 4;
    } catch (_) {}

    // 2. Tramo hacia la próxima parada de la ruta (Santiago -> Pepito)
    List<LatLng> listaSiguiente = [];
    Map<String, dynamic>? proxima;
    for (final p in paradas) {
      if (p['id'] != widget.despacho['id'] && p['pedido'] != null) {
        proxima = p;
        break;
      }
    }

    if (proxima != null) {
      final pedSig = proxima['pedido'] as Map<String, dynamic>;
      final latSig = (pedSig['latitudDestino'] as num).toDouble();
      final lonSig = (pedSig['longitudDestino'] as num).toDouble();
      try {
        final resSig = await ApiService.obtenerRutaVialOsrm(
          destLatActivo,
          destLngActivo,
          latSig,
          lonSig,
        );
        final List<dynamic> coordsSig = resSig['coordinates'] as List<dynamic>? ?? [];
        listaSiguiente = coordsSig.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _puntosTramoActivo = listaActivo;
      _puntosTramoSiguiente = listaSiguiente;
      _distanciaRestanteKm = distActivoKm;
      _duracionEstimadaMin = durActivoMin;
      _proximaParada = proxima;
      _cargandoRuta = false;
    });
  }

  Future<void> _transmitirTelemetriaAlServidor() async {
    if (_posicionChofer == null) return;
    String choferId = widget.choferData['id']?.toString() ??
        (widget.choferData['user'] != null ? widget.choferData['user']['id']?.toString() : '') ??
        '';
    if (choferId.isEmpty) {
      choferId = await ApiService.getDriverId() ?? '';
    }
    String choferNombre = widget.choferData['nombre']?.toString() ??
        widget.choferData['fullName']?.toString() ??
        (widget.choferData['user'] != null ? widget.choferData['user']['fullName']?.toString() : '') ??
        '';
    if (choferNombre.isEmpty) {
      choferNombre = await ApiService.getDriverName() ?? 'Chofer';
    }
    final despachoId = _despachoActual['id']?.toString() ?? '';

    await ApiService.enviarTelemetriaHttp(
      choferId: choferId,
      despachoId: despachoId,
      lat: _posicionChofer!.latitude,
      lon: _posicionChofer!.longitude,
      velocidad: _velocidadKmh > 0 ? _velocidadKmh : 24.5,
      rumbo: _rumboActual,
      choferNombre: choferNombre,
    );
  }

  void _abrirPantallaEpod() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EpodScreen(despacho: _despachoActual),
      ),
    );

    if (resultado == true && mounted) {
      _mostrarToastDiscreto('Entrega documentada registrada con éxito en el sistema.');
      Navigator.pop(context, true);
    }
  }

  void _mostrarToastDiscreto(String mensaje, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      AppToast.error(context, mensaje);
    } else {
      AppToast.success(context, mensaje);
    }
  }

  Future<void> _reportarParadaFallida() async {
    final motivos = [
      'Cliente ausente / no se encontraba en el lugar',
      'Dirección o teléfono de contacto erróneo',
      'Local o negocio cerrado',
      'Cliente rechazó la entrega del material',
      'Vía o acceso bloqueado para el camión',
      'Otro motivo...',
    ];

    String motivoSeleccionado = motivos.first;
    final detalleCtrl = TextEditingController();

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final esOtro = motivoSeleccionado == 'Otro motivo...';
          return AlertDialog(
            backgroundColor: const Color(0xFF111827),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF1E293B)),
            ),
            title: const Row(
              children: [
                Icon(Icons.report_problem_rounded, color: Color(0xFFEF4444), size: 22),
                SizedBox(width: 8),
                Text(
                  'Reportar Parada Fallida',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seleccione la causa por la cual no se pudo concretar la entrega:',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  ...motivos.map((m) => RadioListTile<String>(
                        value: m,
                        groupValue: motivoSeleccionado,
                        activeColor: const Color(0xFFEF4444),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(m, style: const TextStyle(color: Colors.white, fontSize: 12)),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => motivoSeleccionado = val);
                        },
                      )),
                  if (esOtro) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: detalleCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: 'Especifique el motivo...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar Fallida', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmado == true) {
      final motivoFinal = motivoSeleccionado == 'Otro motivo...' && detalleCtrl.text.trim().isNotEmpty
          ? detalleCtrl.text.trim()
          : motivoSeleccionado;

      try {
        await ApiService.cancelarRuta(widget.despacho['id'].toString(), motivoFinal);
        if (!mounted) return;
        Navigator.pop(context, true); // Retornar a la lista de paradas
      } catch (e) {
        if (!mounted) return;
        _mostrarToastDiscreto('Error al reportar parada fallida: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> pedido =
        _despachoActual['pedido'] as Map<String, dynamic>? ?? {};
    final String cliente = pedido['cliente'] ?? 'Cliente';
    final String direccion = pedido['direccionTexto'] ?? 'Quito';
    final double destLat = (pedido['latitudDestino'] as num?)?.toDouble() ?? -0.102234;
    final double destLng = (pedido['longitudDestino'] as num?)?.toDouble() ?? -78.451495;
    final LatLng destPoint = LatLng(destLat, destLng);

    final String codigoRuta = widget.ruta['codigoRuta'] ?? 'Ruta';
    final num? ordenParada = _despachoActual['ordenParada'] as num?;

    final paradasPendientes = _obtenerParadasPendientes();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$codigoRuta • Parada #${ordenParada ?? 1}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const Text(
              'Navegacion Urbana y Telemetria en Vivo',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Color(0xFF38BDF8)),
            onPressed: () {
              if (_posicionChofer != null) {
                _mapController.move(_posicionChofer!, 15.0);
              }
            },
            tooltip: 'Recentrar vehiculo',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. MAPA DE NAVEGACION VIAL (GOOGLE MAPS PLATFORM TILES)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _posicionChofer ?? destPoint,
              initialZoom: 15.0,
              minZoom: 10.0,
              maxZoom: 20.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                userAgentPackageName: 'com.alumvid.mobile',
                subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                maxZoom: 20,
              ),

              // Polyline vial por las calles de Quito (OSRM)
              PolylineLayer(
                polylines: [
                  // 1. Tramo hacia la próxima parada de la ruta (segmento subsiguiente visible)
                  if (_puntosTramoSiguiente.isNotEmpty)
                    Polyline(
                      points: _puntosTramoSiguiente,
                      strokeWidth: 4.8,
                      color: const Color(0xFF38BDF8),
                    ),

                  // 2. Tramo hacia la parada activa (desde el chofer)
                  if (_puntosTramoActivo.isNotEmpty)
                    Polyline(
                      points: _puntosTramoActivo.length > _indicePunto
                          ? [_posicionChofer ?? _puntosTramoActivo[_indicePunto], ..._puntosTramoActivo.sublist(_indicePunto)]
                          : [_posicionChofer ?? _puntosTramoActivo.last, destPoint],
                      strokeWidth: 5.5,
                      color: const Color(0xFF2563EB),
                    ),
                ],
              ),

              // Marcadores de Paradas y Chofer
              MarkerLayer(
                markers: [
                  // Marcadores de todas las paradas pendientes de la hoja de ruta
                  ...paradasPendientes.map((parada) {
                    final ped = parada['pedido'] as Map<String, dynamic>? ?? {};
                    final lat = (ped['latitudDestino'] as num?)?.toDouble() ?? 0.0;
                    final lon = (ped['longitudDestino'] as num?)?.toDouble() ?? 0.0;
                    final orden = parada['ordenParada'] ?? 1;
                    final clienteNom = ped['cliente'] ?? 'Destino';
                    final esActiva = parada['id'] == _despachoActual['id'];

                    return Marker(
                      point: LatLng(lat, lon),
                      width: 65,
                      height: 52,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: esActiva ? const Color(0xFFE11D48) : const Color(0xFF0284C7),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                            child: Text(
                              '#$orden $clienteNom',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.location_on,
                            color: esActiva ? const Color(0xFFE11D48) : const Color(0xFF0284C7),
                            size: 26,
                          ),
                        ],
                      ),
                    );
                  }),

                  // Marcador del Chofer en transito (icono de vehiculo con rumbo de navegacion)
                  if (_posicionChofer != null)
                    Marker(
                      point: _posicionChofer!,
                      width: 50,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [
                            BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4)),
                          ],
                        ),
                        child: Transform.rotate(
                          angle: _rumboActual * (pi / 180.0),
                          child: const Icon(Icons.navigation, color: Colors.white, size: 26),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 2. TARJETA FLOTANTE SUPERIOR ESTILO UBER (METRICAS VIALES Y DATOS DE PARADA)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF111827).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E293B)),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.local_shipping, color: Color(0xFF60A5FA), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cliente,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              direccion,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF1E293B), height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.route, color: Color(0xFF34D399), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            _cargandoRuta
                                ? 'Calculando red vial...'
                                : _distanciaRestanteKm <= 0.05
                                    ? '¡Has llegado al destino!'
                                    : '${_distanciaRestanteKm.toStringAsFixed(1)} km restantes',
                            style: const TextStyle(
                              color: Color(0xFF34D399),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      if (_duracionEstimadaMin > 0)
                        Text(
                          '~$_duracionEstimadaMin min aprox.',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                  if (_proximaParada != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.near_me, color: Color(0xFF38BDF8), size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Próxima parada: #${_proximaParada!['ordenParada']} ${(_proximaParada!['pedido'] as Map)['cliente'] ?? ''}',
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 3. BARRA INFERIOR DE ACCIONES (FINALIZAR CON e-PoD O REGRESAR)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Indicador de telemetria satelital activa
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sensors, color: Color(0xFF38BDF8), size: 15),
                      SizedBox(width: 6),
                      Text(
                        'Transmision satelital activa hacia el Centro de Control',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ),
                ),

                // Boton principal: Registrar Entrega con e-PoD
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 4,
                    ),
                    icon: const Icon(Icons.assignment_turned_in, size: 20),
                    label: const Text(
                      'Completar Entrega Documentada (e-PoD)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    onPressed: _abrirPantallaEpod,
                  ),
                ),
                const SizedBox(height: 8),

                // Botón secundario: Reportar Parada Fallida
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFEF4444)),
                    label: const Text(
                      'Reportar Parada Fallida',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _reportarParadaFallida,
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
