import 'dart:async';
import 'dart:math' as math;

import 'package:alumvid_admin_desktop/models/ruta.dart';
import 'package:alumvid_admin_desktop/models/telemetria.dart';
import 'package:alumvid_admin_desktop/services/api_service.dart' as adm;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'rutas_admin_screen.dart';

/// Monitoreo en tiempo real de choferes (solo ADMINISTRADOR).
class MonitoreoScreen extends StatefulWidget {
  const MonitoreoScreen({super.key});

  @override
  State<MonitoreoScreen> createState() => _MonitoreoScreenState();
}

class _MonitoreoScreenState extends State<MonitoreoScreen> {
  static const _quito = LatLng(-0.1807, -78.4678);
  final _map = MapController();
  Timer? _timer;
  List<TelemetriaGps> _gps = [];
  List<Ruta> _enCurso = [];
  String? _error;
  DateTime? _actualizado;
  bool _primeraCarga = true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _cargar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final res = await Future.wait([
        adm.ApiService.obtenerTelemetriaActiva(),
        adm.ApiService.obtenerRutas(),
      ]);
      if (!mounted) return;
      setState(() {
        _gps = res[0] as List<TelemetriaGps>;
        _enCurso = (res[1] as List<Ruta>).where((r) => r.isEnCurso).toList();
        _error = null;
        _actualizado = DateTime.now();
      });
      if (_primeraCarga) {
        _primeraCarga = false;
        _encuadrar();
      }
    } catch (e) {
      if (mounted) setState(() => _error = limpiarError(e));
    }
  }

  void _encuadrar() {
    final pts = [for (final t in _gps) LatLng(t.latitud, t.longitud)];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _map.move(pts.first, 15);
    } else {
      _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(60)));
    }
  }

  String _hace(int ts) {
    final ms = ts > 1e12 ? ts : ts * 1000;
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inSeconds < 60) return 'hace ${math.max(0, d.inSeconds)} s';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    return 'hace ${d.inHours} h';
  }

  Ruta? _rutaDe(TelemetriaGps t) =>
      _enCurso.where((r) => r.choferId != null && r.choferId == t.choferId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: const MapOptions(initialCenter: _quito, initialZoom: 12),
            children: [
              TileLayer(urlTemplate: tileUrl, userAgentPackageName: tileAgent),
              MarkerLayer(
                markers: [
                  for (final t in _gps)
                    Marker(
                      point: LatLng(t.latitud, t.longitud),
                      width: 46,
                      height: 46,
                      child: GestureDetector(
                        onTap: () => _detalleChofer(t),
                        child: Transform.rotate(
                          angle: t.rumbo * math.pi / 180,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                            ),
                            child: const Icon(Icons.navigation, color: Colors.white, size: 22),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: _pastillaEstado()),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: 'encuadrar',
                    tooltip: 'Ver todos los choferes',
                    onPressed: _encuadrar,
                    child: const Icon(Icons.fit_screen),
                  ),
                ],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.28,
            minChildSize: 0.12,
            maxChildSize: 0.75,
            snap: true,
            builder: (ctx, scroll) => Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 16)],
              ),
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_gps.length} choferes transmitiendo · ${_enCurso.length} rutas en curso',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  if (_gps.isEmpty)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.gps_off),
                      title: Text('Sin señal GPS activa'),
                      subtitle: Text('Los choferes aparecen al iniciar una ruta en la app.'),
                    ),
                  for (final t in _gps)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: AvatarIniciales(t.choferNombre ?? 'Chofer'),
                      title: Text(t.choferNombre ?? 'Chofer'),
                      subtitle: Text(
                        '${t.velocidadKmh.round()} km/h · ${_hace(t.timestamp)}'
                        '${_rutaDe(t) != null ? ' · ${_rutaDe(t)!.paradasEntregadas}/${_rutaDe(t)!.totalParadas} paradas' : ''}',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      trailing: const Icon(Icons.my_location),
                      onTap: () => _map.move(LatLng(t.latitud, t.longitud), 16),
                    ),
                  if (_enCurso.isNotEmpty) ...[
                    const SeccionTitulo('Rutas en curso'),
                    for (final r in _enCurso)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RutaCard(
                          ruta: r,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RutaDetalleScreen(rutaId: r.id, inicial: r),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pastillaEstado() {
    final enVivo = _error == null && _actualizado != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: enVivo ? AppColors.success : AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error != null
                  ? 'Sin conexión · reintentando'
                  : _actualizado == null
                  ? 'Conectando…'
                  : 'En vivo · actualizado ${TimeOfDay.fromDateTime(_actualizado!).format(context)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _detalleChofer(TelemetriaGps t) {
    final ruta = _rutaDe(t);
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.choferNombre ?? 'Chofer',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              DatoFila('Velocidad', '${t.velocidadKmh.round()} km/h', icono: Icons.speed),
              DatoFila('Última señal', _hace(t.timestamp), icono: Icons.access_time),
              DatoFila(
                'Posición',
                '${t.latitud.toStringAsFixed(5)}, ${t.longitud.toStringAsFixed(5)}',
                icono: Icons.place_outlined,
              ),
              if (ruta != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RutaDetalleScreen(rutaId: ruta.id, inicial: ruta),
                      ),
                    );
                  },
                  icon: const Icon(Icons.alt_route),
                  label: const Text('Ver su ruta'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
