import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'epod_screen.dart';

class DetalleRutaScreen extends StatefulWidget {
  final Map<String, dynamic> despacho;

  const DetalleRutaScreen({super.key, required this.despacho});

  @override
  State<DetalleRutaScreen> createState() => _DetalleRutaScreenState();
}

class _DetalleRutaScreenState extends State<DetalleRutaScreen> {
  late Map<String, dynamic> _despachoActual;
  bool _procesando = false;

  // Mapa y Telemetria en tiempo real estilo Uber
  MapController? _mapController;
  LatLng? _posicionChofer;
  StreamSubscription<Position>? _positionStreamSub;
  double _distanciaRestanteKm = 0.0;
  bool _cargandoGps = true;

  @override
  void initState() {
    super.initState();
    _despachoActual = widget.despacho;
    _mapController = MapController();
    _iniciarSeguimientoGps();
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _iniciarSeguimientoGps() async {
    try {
      final pos = await LocationService.determinarPosicionActual();
      if (mounted) {
        setState(() {
          _posicionChofer = LatLng(pos.latitude, pos.longitude);
          _cargandoGps = false;
          _calcularDistanciaRestante();
        });
      }
    } catch (_) {
      // Coordenadas base en Quito para entorno de emulador o navegador
      if (mounted) {
        setState(() {
          _posicionChofer = const LatLng(-0.1807, -78.4678);
          _cargandoGps = false;
          _calcularDistanciaRestante();
        });
      }
    }

    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() {
        _posicionChofer = LatLng(pos.latitude, pos.longitude);
        _calcularDistanciaRestante();
      });
    }, onError: (_) {});
  }

  void _calcularDistanciaRestante() {
    if (_posicionChofer == null) return;
    final destLat = (_despachoActual['pedido']?['latitudDestino'] as num?)?.toDouble() ?? -0.1807;
    final destLng = (_despachoActual['pedido']?['longitudDestino'] as num?)?.toDouble() ?? -78.4678;

    final distMetros = Geolocator.distanceBetween(
      _posicionChofer!.latitude,
      _posicionChofer!.longitude,
      destLat,
      destLng,
    );
    _distanciaRestanteKm = distMetros / 1000.0;
  }

  Future<void> _aceptarEIniciar() async {
    setState(() => _procesando = true);
    try {
      final res = await ApiService.aceptarEIniciarRuta(_despachoActual['id']);
      setState(() {
        _despachoActual = res;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Consentimiento registrado. Monitoreo satelital activo hacia la central.'),
          backgroundColor: Color(0xFF059669),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFFE11D48),
        ),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _cancelarRuta() async {
    final motivoController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Cancelar Hoja de Ruta', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La transmision de ubicacion satelital sera cortada de inmediato y la ruta pasara a estado CANCELADA.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Motivo de cancelacion',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: Color(0xFF0A0E17),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar Cancelacion', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _procesando = true);
    try {
      final res = await ApiService.cancelarRuta(
        _despachoActual['id'],
        motivoController.text.trim().isEmpty ? 'Cancelada por el chofer' : motivoController.text.trim(),
      );
      setState(() {
        _despachoActual = res;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ruta cancelada. Transmision satelital finalizada.'),
          backgroundColor: Color(0xFFE11D48),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFFE11D48),
        ),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Widget _construirRecuadroMapaUber(Map<String, dynamic> pedido) {
    final destLat = (pedido['latitudDestino'] as num?)?.toDouble() ?? -0.1807;
    final destLng = (pedido['longitudDestino'] as num?)?.toDouble() ?? -78.4678;
    final posDestino = LatLng(destLat, destLng);
    final posActual = _posicionChofer ?? posDestino;

    return Container(
      height: 360,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          children: [
            // 1. Capa Cartografica Interactiva
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: posActual,
                initialZoom: 14.5,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.titulacionammo.glassflow',
                ),
                // Linea Polyline de ruta
                if (_posicionChofer != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [_posicionChofer!, posDestino],
                        strokeWidth: 4.5,
                        color: const Color(0xFF2563EB),
                      ),
                    ],
                  ),
                // Marcadores
                MarkerLayer(
                  markers: [
                    // Destino
                    Marker(
                      point: posDestino,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.location_on,
                        color: Color(0xFFE11D48),
                        size: 40,
                      ),
                    ),
                    // Vehiculo del Chofer
                    if (_posicionChofer != null)
                      Marker(
                        point: _posicionChofer!,
                        width: 52,
                        height: 52,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF3B82F6).withValues(alpha: 0.25),
                              ),
                            ),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF1E3A8A),
                                border: Border.all(color: const Color(0xFF60A5FA), width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.navigation,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // 2. Tarjeta Superior Flotante Estilo Navegacion Uber
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF00A0E17),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.near_me, color: Color(0xFF60A5FA), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'EN TRAYECTO',
                                style: TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_distanciaRestanteKm.toStringAsFixed(1)} km restantes',
                                style: const TextStyle(
                                  color: Color(0xFF34D399),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pedido['cliente'] ?? 'Cliente Destino',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Boton Flotante para Recentrar el Mapa
            Positioned(
              bottom: 12,
              right: 12,
              child: FloatingActionButton.small(
                heroTag: 'btn-recentrar-mapa',
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: const Color(0xFF60A5FA),
                onPressed: () {
                  if (_posicionChofer != null && _mapController != null) {
                    _mapController!.move(_posicionChofer!, 15.0);
                  }
                },
                child: const Icon(Icons.my_location, size: 20),
              ),
            ),

            // 4. Indicador de carga inicial
            if (_cargandoGps)
              Positioned(
                bottom: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0F172A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Sincronizando satelites GPS...',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = _despachoActual['estado'] ?? 'PENDIENTE';
    final pedido = _despachoActual['pedido'] ?? {};

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Text(
          'Despacho #${_despachoActual['id'].toString().substring(0, 8)}',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // TARJETA DE DATOS DEL CLIENTE
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Datos del Cliente',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          estado,
                          style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    pedido['cliente'] ?? '-',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Direccion: ${pedido['direccionTexto'] ?? '-'}',
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Coordenadas: ${pedido['latitudDestino'] ?? '-'}, ${pedido['longitudDestino'] ?? '-'}',
                    style: const TextStyle(fontFamily: 'monospace', color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ESTADO: PENDIENTE
            if (estado == 'PENDIENTE') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x22FBBF24),
                  border: Border.all(color: const Color(0x66FBBF24)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Consentimiento Obligatorio: Al presionar "Aceptar e Iniciar Ruta", usted autoriza expresamente la transmision periodica de su posicion GPS satelital hacia la central administrativa de GlassFlow.',
                  style: TextStyle(color: Color(0xFFFBBF24), fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _procesando ? null : _aceptarEIniciar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _procesando
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Aceptar e Iniciar Ruta',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
              ),
            ]
            // ESTADO: EN CURSO -> RECUADRO DE NAVEGACION ESTILO UBER
            else if (estado == 'EN_CURSO') ...[
              _construirRecuadroMapaUber(pedido),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x222563EB),
                  border: Border.all(color: const Color(0x662563EB)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.satellite_alt, color: Color(0xFF60A5FA), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Telemetria en tiempo real activa. Sus coordenadas satelitales se transmiten en vivo.',
                        style: TextStyle(color: Color(0xFF93C5FD), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final exito = await nav.push<bool>(
                    MaterialPageRoute(
                      builder: (_) => EpodScreen(despacho: _despachoActual),
                    ),
                  );
                  if (exito == true && mounted) {
                    nav.pop(true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text(
                  'Completar Entrega Documentada (e-PoD)',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: _procesando ? null : _cancelarRuta,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE11D48)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text(
                  'Cancelar Ruta Voluntariamente',
                  style: TextStyle(color: Color(0xFFFB7185), fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ]
            // ESTADO: ENTREGADO
            else if (estado == 'ENTREGADO') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x22059669),
                  border: Border.all(color: const Color(0x66059669)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Entrega documentada y finalizada con exito. Evidencias e-PoD archivadas legalmente en la base de datos.',
                  style: TextStyle(color: Color(0xFF34D399), fontSize: 13),
                ),
              ),
            ]
            // ESTADO: CANCELADA
            else if (estado == 'CANCELADA') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x22E11D48),
                  border: Border.all(color: const Color(0x66E11D48)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Ruta cancelada. Observacion: ${_despachoActual['comentarios'] ?? 'Cancelada'}',
                  style: const TextStyle(color: Color(0xFFFB7185), fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
