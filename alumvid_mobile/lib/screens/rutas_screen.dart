import 'package:alumvid_admin_desktop/shared/tema.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/websocket_mobile_service.dart';
import 'detalle_ruta_screen.dart';
import 'login_screen.dart';

/// Pantalla principal de la aplicacion movil del Chofer.
/// Presenta las Hojas de Ruta asignadas por el Administrador (ej. Ruta 1, Ruta 2).
/// Al seleccionar una ruta, se despliega el itinerario de paradas para su ejecucion.
class RutasScreen extends StatefulWidget {
  final Map<String, dynamic> choferData;

  const RutasScreen({super.key, required this.choferData});

  @override
  State<RutasScreen> createState() => _RutasScreenState();
}

class _RutasScreenState extends State<RutasScreen> {
  List<dynamic> _rutas = [];
  bool _cargando = true;
  String? _error;
  WebSocketMobileService? _wsMobileService;
  Timer? _sesionCheckTimer;
  bool _expulsando = false;

  @override
  void initState() {
    super.initState();
    _iniciarMonitoreoSesion();
    _cargarRutasAsignadas();
  }

  @override
  void dispose() {
    _sesionCheckTimer?.cancel();
    _wsMobileService?.dispose();
    super.dispose();
  }

  void _iniciarMonitoreoSesion() {
    final choferId = widget.choferData['id']?.toString() ?? '';
    _wsMobileService = WebSocketMobileService(
      choferId: choferId,
      onSesionRevocada: _expulsarPorSesionRevocada,
    );
    _wsMobileService?.connect();

    // Verificación periódica HTTP como salvaguarda complementaria cada 8 segundos
    _sesionCheckTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _verificarSesionHttp();
      if (mounted && !_expulsando) _cargarRutasAsignadas();
    });
  }

  void _verificarSesionHttp() async {
    if (_expulsando) return;
    final activa = await ApiService.verificarSesionActiva();
    if (!activa && mounted && !_expulsando) {
      _expulsarPorSesionRevocada();
    }
  }

  void _expulsarPorSesionRevocada() async {
    if (_expulsando) return;
    _expulsando = true;
    _sesionCheckTimer?.cancel();
    _wsMobileService?.dispose();
    await ApiService.logout();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFB7185)),
            SizedBox(width: 8),
            Text(
              'Sesión Finalizada',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Su sesión ha sido revocada por el administrador o la contraseña fue restablecida.\n\nPor favor inicie sesión nuevamente.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Iniciar Sesión'),
          ),
        ],
      ),
    );
  }

  Future<void> _cargarRutasAsignadas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final choferId = widget.choferData['id']?.toString() ?? '';
      final List<dynamic> res = await ApiService.obtenerRutasChofer(choferId);
      if (mounted) {
        setState(() {
          _rutas = res;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  void _cerrarSesion() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Color _obtenerColorEstado(String estado) {
    switch (estado) {
      case 'PENDIENTE':
        return const Color(0xFFFBBF24);
      case 'EN_CURSO':
        return const Color(0xFF60A5FA);
      case 'ENTREGADO':
      case 'COMPLETADA':
        return const Color(0xFF34D399);
      case 'CANCELADA':
        return const Color(0xFFFB7185);
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild semantic colors when the appearance changes.

    final String nombreChofer = widget.choferData['nombre'] ?? 'Chofer';
    final String emailChofer = widget.choferData['email'] ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nombreChofer,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            Text(
              emailChofer.isNotEmpty ? emailChofer : 'Chofer de Reparto',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.textMuted),
            onPressed: _cargarRutasAsignadas,
            tooltip: 'Sincronizar rutas',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFFB7185)),
            onPressed: _cerrarSesion,
            tooltip: 'Cerrar Sesion',
          ),
        ],
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFB7185)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _cargarRutasAsignadas,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: Text(
                        'Reintentar',
                        style: TextStyle(color: AppColors.text),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _rutas.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(30.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.alt_route, size: 48, color: AppColors.border),
                    const SizedBox(height: 16),
                    Text(
                      'No posee Hojas de Ruta asignadas actualmente.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'El administrador asignara rutas desde el panel web de control logistico.',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _cargarRutasAsignadas,
                      icon: const Icon(
                        Icons.refresh,
                        size: 16,
                        color: Color(0xFF60A5FA),
                      ),
                      label: const Text(
                        'Comprobar Nuevas Asignaciones',
                        style: TextStyle(color: Color(0xFF60A5FA)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.card),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargarRutasAsignadas,
              color: AppColors.primary,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _rutas.length,
                itemBuilder: (context, index) {
                  final r = _rutas[index];
                  final String codigo = r['codigoRuta'] ?? 'Ruta';
                  final String estado = r['estado'] ?? 'PENDIENTE';
                  final List<dynamic> paradas =
                      (r['paradas'] as List<dynamic>?) ?? [];
                  final int totalParadas = paradas.length;
                  final int entregadas = paradas
                      .where((p) => p['estado'] == 'ENTREGADO')
                      .length;
                  final Color colorEstado = _obtenerColorEstado(estado);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.card),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DetalleRutaScreen(
                                ruta: r,
                                choferData: widget.choferData,
                              ),
                            ),
                          );
                          _cargarRutasAsignadas();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.alt_route,
                                          color: Color(0xFF60A5FA),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        codigo,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorEstado.withValues(
                                        alpha: 0.15,
                                      ),
                                      border: Border.all(
                                        color: colorEstado.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      estado,
                                      style: TextStyle(
                                        color: colorEstado,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(
                                    Icons.pin_drop,
                                    size: 16,
                                    color: AppColors.primaryLight,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$totalParadas destinos de entrega programados',
                                    style: const TextStyle(
                                      color: Color(0xFFCBD5E1),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Progreso: $entregadas de $totalParadas completados',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              if (r['comentarios'] != null &&
                                  r['comentarios'].toString().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Nota: ${r['comentarios']}',
                                  style: TextStyle(
                                    color: AppColors.textDim,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    'Abrir Hoja de Ruta',
                                    style: TextStyle(
                                      color: const Color(0xFF60A5FA),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 12,
                                    color: Color(0xFF60A5FA),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
