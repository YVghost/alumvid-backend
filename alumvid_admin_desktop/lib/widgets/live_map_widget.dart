import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/despacho.dart';
import '../models/ruta.dart';
import '../models/telemetria.dart';
import '../theme/app_theme.dart';

enum GoogleMapStyle { calles, satelite, hibrido, terreno }

class LiveMapWidget extends StatefulWidget {
  final List<Ruta> rutas;
  final Ruta? rutaSeleccionada;
  final Map<String, TelemetriaGps> telemetriaChoferes;
  final List<LatLng> puntosPolilineaRuta;
  final Function(Despacho)? onParadaTap;
  final Function(Ruta)? onRutaFocus;

  const LiveMapWidget({
    super.key,
    required this.rutas,
    this.rutaSeleccionada,
    required this.telemetriaChoferes,
    required this.puntosPolilineaRuta,
    this.onParadaTap,
    this.onRutaFocus,
  });

  @override
  State<LiveMapWidget> createState() => LiveMapWidgetState();
}

class LiveMapWidgetState extends State<LiveMapWidget> {
  final MapController _mapController = MapController();
  GoogleMapStyle _mapStyle = GoogleMapStyle.calles;

  // Bodega Central Arq-AlumVid en Quito
  static const LatLng _bodegaCentral = LatLng(-0.089290, -78.439607);

  String _getGoogleTileUrl() {
    // URL directa a los servidores de tiles de Google Maps con capas de alta resolucion
    switch (_mapStyle) {
      case GoogleMapStyle.satelite:
        return 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
      case GoogleMapStyle.hibrido:
        return 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
      case GoogleMapStyle.terreno:
        return 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}';
      case GoogleMapStyle.calles:
        return 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
    }
  }

  void recentrarEnBodega() {
    _mapController.move(_bodegaCentral, 13.5);
  }

  void enfocarCoordenada(LatLng pos, [double zoom = 15.0]) {
    _mapController.move(pos, zoom);
  }

  @override
  Widget build(BuildContext context) {
    // Recopilar paradas a mostrar
    final List<Despacho> paradasAMostrar = [];
    if (widget.rutaSeleccionada != null) {
      paradasAMostrar.addAll(widget.rutaSeleccionada!.paradas);
    } else {
      // Mostrar paradas de todas las rutas activas
      for (final r in widget.rutas.where((r) => r.isEnCurso)) {
        paradasAMostrar.addAll(r.paradas);
      }
    }

    return Stack(
      children: [
        // 1. MAPA INTERACTIVO GOOGLE MAPS TILES
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: _bodegaCentral,
            initialZoom: 13.2,
            minZoom: 6.0,
            maxZoom: 20.0,
          ),
          children: [
            // Capa Cartográfica Google Maps
            TileLayer(
              urlTemplate: _getGoogleTileUrl(),
              userAgentPackageName: 'com.alumvid.admin',
              subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
              maxZoom: 20,
            ),

            // Geocercas circulares de tolerancia (150m PostGIS) alrededor de las paradas
            CircleLayer(
              circles: paradasAMostrar
                  .where((p) => p.pedido != null)
                  .map(
                    (p) => CircleMarker(
                      point: LatLng(p.pedido!.latitudDestino, p.pedido!.longitudDestino),
                      radius: 35, // Representación de tolerancia espacial
                      useRadiusInMeter: false,
                      color: p.isEntregado
                          ? AppTheme.statusCompletada.withValues(alpha: 0.15)
                          : p.hasAlertaDesviacion
                              ? AppTheme.statusAlerta.withValues(alpha: 0.25)
                              : AppTheme.primaryLight.withValues(alpha: 0.15),
                      borderColor: p.isEntregado
                          ? AppTheme.statusCompletada.withValues(alpha: 0.6)
                          : p.hasAlertaDesviacion
                              ? AppTheme.statusAlerta
                              : AppTheme.primaryLight.withValues(alpha: 0.6),
                      borderStrokeWidth: 1.5,
                    ),
                  )
                  .toList(),
            ),

            // Trazo vial de la ruta seleccionada (OSRM)
            if (widget.puntosPolilineaRuta.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.puntosPolilineaRuta,
                    strokeWidth: 4.5,
                    color: AppTheme.primaryLight,
                  ),
                ],
              ),

            // Capa de Marcadores (Bodega, Paradas y Vehículos)
            MarkerLayer(
              markers: [
                // Marcador de Bodega Central AlumVid
                Marker(
                  point: _bodegaCentral,
                  width: 50,
                  height: 50,
                  child: Tooltip(
                    message: 'Bodega Central AlumVid (Quito)',
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF38BDF8), width: 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 3)),
                        ],
                      ),
                      child: const Icon(Icons.warehouse, color: Color(0xFF38BDF8), size: 26),
                    ),
                  ),
                ),

                // Marcadores de Paradas / Destinos
                ...paradasAMostrar.where((p) => p.pedido != null).map((parada) {
                  final ped = parada.pedido!;
                  final pos = LatLng(ped.latitudDestino, ped.longitudDestino);

                  Color badgeColor = AppTheme.statusPendiente;
                  IconData iconData = Icons.location_on;
                  if (parada.isEntregado) {
                    badgeColor = AppTheme.statusCompletada;
                    iconData = Icons.check_circle;
                  } else if (parada.isEnCurso) {
                    badgeColor = AppTheme.statusEnCurso;
                    iconData = Icons.near_me;
                  } else if (parada.hasAlertaDesviacion) {
                    badgeColor = AppTheme.statusAlerta;
                    iconData = Icons.warning_amber;
                  }

                  return Marker(
                    point: pos,
                    width: 44,
                    height: 54,
                    child: GestureDetector(
                      onTap: () {
                        widget.onParadaTap?.call(parada);
                      },
                      child: Tooltip(
                        message: 'Parada #${parada.ordenParada}: ${ped.cliente} (${parada.estado})',
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '#${parada.ordenParada}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(iconData, color: Colors.white, size: 12),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, color: badgeColor, size: 18),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                // Marcadores de Choferes en tiempo real
                ...widget.telemetriaChoferes.values.map((tel) {
                  final pos = LatLng(tel.latitud, tel.longitud);
                  return Marker(
                    point: pos,
                    width: 70,
                    height: 60,
                    child: Tooltip(
                      message: '${tel.choferNombre ?? "Chofer"} • ${tel.velocidadKmh.toStringAsFixed(0)} km/h',
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.statusEnCurso),
                            ),
                            child: Text(
                              tel.choferNombre ?? 'Chofer',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Transform.rotate(
                            angle: tel.rumbo * (3.141592653589793 / 180.0),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: AppTheme.statusEnCurso,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 2)),
                                ],
                              ),
                              child: const Icon(Icons.navigation, color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),

        // 2. SELECTOR DE CAPAS GOOGLE MAPS (Calles / Satélite / Híbrido)
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMapStyleButton('Calles', GoogleMapStyle.calles),
                const SizedBox(width: 4),
                _buildMapStyleButton('Satélite', GoogleMapStyle.satelite),
                const SizedBox(width: 4),
                _buildMapStyleButton('Híbrido', GoogleMapStyle.hibrido),
              ],
            ),
          ),
        ),

        // 3. CONTROLES FLOTANTES DE ZOOM Y RECENTRADO
        Positioned(
          bottom: 24,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFloatingBtn(
                icon: Icons.add,
                tooltip: 'Acercar zoom',
                onPressed: () {
                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
                },
              ),
              const SizedBox(height: 8),
              _buildFloatingBtn(
                icon: Icons.remove,
                tooltip: 'Alejar zoom',
                onPressed: () {
                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
                },
              ),
              const SizedBox(height: 8),
              _buildFloatingBtn(
                icon: Icons.warehouse,
                tooltip: 'Centrar en Bodega Central',
                onPressed: recentrarEnBodega,
                iconColor: AppTheme.primaryLight,
              ),
            ],
          ),
        ),

        // 4. BANNER SUPERIOR INFORMATIVO SI HAY RUTA SELECCIONADA
        if (widget.rutaSeleccionada != null)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5)),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: widget.rutaSeleccionada!.isEnCurso ? AppTheme.statusEnCurso : AppTheme.statusPendiente,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Visualizando: ${widget.rutaSeleccionada!.codigoRuta} (${widget.rutaSeleccionada!.estado})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '• Chofer: ${widget.rutaSeleccionada!.choferNombre ?? "Sin asignar"}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMapStyleButton(String label, GoogleMapStyle style) {
    final bool activo = _mapStyle == style;
    return InkWell(
      onTap: () {
        setState(() {
          _mapStyle = style;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: activo ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: activo ? Colors.white : AppTheme.textMuted,
            fontSize: 12,
            fontWeight: activo ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color iconColor = Colors.white,
  }) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
