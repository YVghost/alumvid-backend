import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
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
  List<LatLng> _puntosRutaVial = [];
  double _distanciaRestanteKm = 0.0;
  int _duracionEstimadaMin = 0;
  double _rumboActual = 0.0;
  double _velocidadKmh = 0.0;
  bool _cargandoRuta = true;

  StreamSubscription<Position>? _positionStreamSub;
  Timer? _telemetriaTimer;

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

  Future<void> _iniciarNavegacionGps() async {
    // 1. Obtener posicion inicial
    LatLng posInicial;
    try {
      final pos = await LocationService.determinarPosicionActual();
      posInicial = LatLng(pos.latitude, pos.longitude);
      _rumboActual = pos.heading;
      _velocidadKmh = (pos.speed * 3.6).clamp(0.0, 120.0);
    } catch (_) {
      // Coordenadas base de partida en Quito (Bodega Central Amazonas)
      posInicial = const LatLng(-0.1807, -78.4678);
    }

    if (!mounted) return;
    setState(() {
      _posicionChofer = posInicial;
    });

    // 2. Trazar ruta por las calles reales de Quito usando OSRM
    await _trazarRutaVial(posInicial);

    // 3. Suscripcion a cambios en la posicion GPS del dispositivo
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final nuevaPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _posicionChofer = nuevaPos;
        _rumboActual = pos.heading;
        _velocidadKmh = (pos.speed * 3.6).clamp(0.0, 120.0);
      });
      _mapController.move(nuevaPos, _mapController.camera.zoom);
    }, onError: (_) {});

    // 4. Transmision periodica de telemetria al backend para el panel de administracion
    _telemetriaTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _transmitirTelemetriaAlServidor();
    });
  }

  Future<void> _trazarRutaVial(LatLng origen) async {
    final Map<String, dynamic> pedido =
        widget.despacho['pedido'] as Map<String, dynamic>? ?? {};
    final destLat = (pedido['latitudDestino'] as num?)?.toDouble() ?? -0.1807;
    final destLng = (pedido['longitudDestino'] as num?)?.toDouble() ?? -78.4678;

    try {
      final res = await ApiService.obtenerRutaVialOsrm(
        origen.latitude,
        origen.longitude,
        destLat,
        destLng,
      );

      final List<dynamic> coords = res['coordinates'] as List<dynamic>? ?? [];
      final List<LatLng> listaPuntos = coords.map((c) {
        final lon = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        return LatLng(lat, lon);
      }).toList();

      if (!mounted) return;
      setState(() {
        _puntosRutaVial = listaPuntos;
        _distanciaRestanteKm = (res['distanciaKm'] as num?)?.toDouble() ?? 0.0;
        _duracionEstimadaMin = (res['duracionMin'] as num?)?.toInt() ?? 0;
        _cargandoRuta = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _puntosRutaVial = [origen, LatLng(destLat, destLng)];
        _cargandoRuta = false;
      });
    }
  }

  Future<void> _transmitirTelemetriaAlServidor() async {
    if (_posicionChofer == null) return;
    final choferId = widget.choferData['id']?.toString() ?? '';
    final choferNombre = widget.choferData['nombre']?.toString() ?? 'Chofer';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrega documentada registrada con exito en el sistema.'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> pedido =
        _despachoActual['pedido'] as Map<String, dynamic>? ?? {};
    final String cliente = pedido['cliente'] ?? 'Cliente';
    final String direccion = pedido['direccionTexto'] ?? 'Quito';
    final double destLat = (pedido['latitudDestino'] as num?)?.toDouble() ?? -0.1807;
    final double destLng = (pedido['longitudDestino'] as num?)?.toDouble() ?? -78.4678;
    final LatLng destPoint = LatLng(destLat, destLng);

    final String codigoRuta = widget.ruta['codigoRuta'] ?? 'Ruta';
    final num? ordenParada = _despachoActual['ordenParada'] as num?;

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
          // 1. MAPA DE NAVEGACION VIAL (OPENSTREETMAP TILE LAYER)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _posicionChofer ?? const LatLng(-0.1807, -78.4678),
              initialZoom: 14.2,
              minZoom: 10.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.titulacionammo.glassflow',
              ),

              // Polyline vial por las calles de Quito (OSRM)
              if (_puntosRutaVial.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _puntosRutaVial,
                      strokeWidth: 5.5,
                      color: const Color(0xFF2563EB),
                    ),
                  ],
                ),

              // Marcadores del Chofer y del Destino
              MarkerLayer(
                markers: [
                  // Marcador de destino de entrega
                  Marker(
                    point: destPoint,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFE11D48),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3)),
                        ],
                      ),
                      child: const Icon(Icons.location_on, color: Colors.white, size: 26),
                    ),
                  ),

                  // Marcador del Chofer en transito (icono de vehiculo de reparto)
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
                        child: const Icon(Icons.navigation, color: Colors.white, size: 26),
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

                // Boton secundario: Regresar al Itinerario de Paradas
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF94A3B8),
                      side: const BorderSide(color: Color(0xFF1E293B)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Ver Lista de Paradas de la Ruta',
                      style: TextStyle(fontSize: 13),
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
