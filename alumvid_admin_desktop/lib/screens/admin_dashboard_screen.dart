import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/chofer.dart';
import '../models/despacho.dart';
import '../models/ruta.dart';
import '../models/telemetria.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../theme/app_theme.dart';
import '../views/inventario_view.dart';
import '../views/kanban_view.dart';
import '../views/planificar_rutas_view.dart';
import '../views/simulador_view.dart';
import '../views/usuarios_view.dart';
import '../widgets/agregar_parada_dialog.dart';
import '../widgets/epod_dialog.dart';
import '../widgets/live_map_widget.dart';
import '../widgets/paradas_list_widget.dart';
import '../widgets/ruta_card.dart';
import '../widgets/auditoria_historico_dialog.dart';
import '../utils/app_toast.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final AppUser user;

  const AdminDashboardScreen({super.key, required this.user});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final WebSocketService _wsService = WebSocketService();
  final GlobalKey<LiveMapWidgetState> _mapWidgetKey = GlobalKey<LiveMapWidgetState>();

  int _selectedTabIndex = 0; // 0 = GPS, 1 = Kanban, 2 = Planificar Rutas, 3 = Inventario, 4 = Usuarios, 5 = Simulador
  int _mobileMapSubIndex = 0; // Para vista 0 en móvil: 0 = Mapa, 1 = Rutas

  List<Ruta> _rutas = [];
  List<Chofer> _choferes = [];
  Ruta? _rutaSeleccionada;
  final Map<String, TelemetriaGps> _telemetriaChoferes = {};
  List<LatLng> _puntosPolilinea = [];

  int _totalProductosBodega = 0;
  String _filtroEstado = 'EN_CURSO';
  bool _cargando = true;
  bool _isSidebarHovered = false;
  DateTimeRange _rangoFiltro = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now(),
  );

  bool _estaEnRango(DateTime? dt, DateTimeRange range) {
    if (dt == null) return false;
    final start = DateTime(range.start.year, range.start.month, range.start.day, 0, 0, 0);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    return dt.isAfter(start.subtract(const Duration(seconds: 1))) &&
        dt.isBefore(end.add(const Duration(seconds: 1)));
  }

  List<Ruta> get _rutasDelPeriodo {
    return _rutas.where((r) => _estaEnRango(r.fechaCreacion, _rangoFiltro)).toList();
  }

  List<Ruta> get _rutasDelDia => _rutasDelPeriodo;

  void _abrirAuditoriaHistorico() {
    showDialog(
      context: context,
      builder: (_) => AuditoriaHistoricoDialog(
        todasLasRutas: _rutas,
        rangoInicial: _rangoFiltro,
        onRangoCambiado: (nuevoRango) {
          setState(() {
            _rangoFiltro = nuevoRango;
            if (_rutaSeleccionada != null && !_estaEnRango(_rutaSeleccionada!.fechaCreacion, nuevoRango)) {
              _rutaSeleccionada = null;
              _puntosPolilinea = [];
            }
          });
        },
        onVerEnMapa: (ruta) {
          setState(() {
            _selectedTabIndex = 0;
            _seleccionarRuta(ruta);
          });
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _inicializarDatos();
    _iniciarSuscripcionWebSocket();
  }

  @override
  void dispose() {
    _wsService.dispose();
    super.dispose();
  }

  void _iniciarSuscripcionWebSocket() {
    _wsService.addTelemetriaListener((telemetria) {
      if (!mounted) return;
      setState(() {
        final key = telemetria.choferId ?? telemetria.choferNombre ?? 'chofer';
        _telemetriaChoferes[key] = telemetria;
      });
    });

    _wsService.addTableroListener(() {
      _recargarDatosSilencioso();
    });

    _wsService.connect();
  }

  Future<void> _inicializarDatos() async {
    setState(() => _cargando = true);
    await Future.wait([
      _cargarRutas(),
      _cargarChoferes(),
      _cargarEstadisticasInventario(),
    ]);
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarRutas() async {
    try {
      final list = await ApiService.obtenerRutas();
      if (!mounted) return;
      setState(() {
        _rutas = list;
        if (_rutaSeleccionada != null) {
          final index = list.indexWhere((r) => r.id == _rutaSeleccionada!.id);
          if (index != -1) {
            _rutaSeleccionada = list[index];
          } else {
            _rutaSeleccionada = null;
            _puntosPolilinea = [];
            final activas = list.where((r) => r.isEnCurso).toList();
            if (activas.isNotEmpty) {
              _seleccionarRuta(activas.first);
            }
          }
        } else {
          final activas = list.where((r) => r.isEnCurso).toList();
          if (activas.isNotEmpty) {
            _seleccionarRuta(activas.first);
          }
        }
      });
    } catch (e) {
      debugPrint('Error cargando rutas: $e');
    }
  }

  Future<void> _cargarChoferes() async {
    try {
      final ch = await ApiService.obtenerChoferes();
      if (!mounted) return;
      setState(() => _choferes = ch);
    } catch (_) {}
  }

  Future<void> _cargarEstadisticasInventario() async {
    try {
      final res = await ApiService.obtenerProductos(page: 0, size: 1);
      if (!mounted) return;
      setState(() {
        _totalProductosBodega = res['total'] as int? ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _recargarDatosSilencioso() async {
    try {
      final list = await ApiService.obtenerRutas();
      if (!mounted) return;
      setState(() {
        _rutas = list;
        if (_rutaSeleccionada != null) {
          final index = list.indexWhere((r) => r.id == _rutaSeleccionada!.id);
          if (index != -1) {
            _rutaSeleccionada = list[index];
          } else {
            _rutaSeleccionada = null;
            _puntosPolilinea = [];
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _seleccionarRuta(Ruta ruta) async {
    setState(() {
      _rutaSeleccionada = ruta;
      _puntosPolilinea = [];
    });

    if (ruta.paradas.isNotEmpty) {
      List<LatLng> coordsRuta = [];
      double origLat = -0.089290;
      double origLon = -78.439607;

      for (final p in ruta.paradas) {
        if (p.pedido != null) {
          final destLat = p.pedido!.latitudDestino;
          final destLon = p.pedido!.longitudDestino;
          final tramo = await ApiService.trazarRutaVial(origLat, origLon, destLat, destLon);
          for (final c in tramo) {
            coordsRuta.add(LatLng(c[0], c[1]));
          }
          origLat = destLat;
          origLon = destLon;
        }
      }

      if (mounted) {
        setState(() => _puntosPolilinea = coordsRuta);
      }
    }
  }

  List<Ruta> get _rutasFiltradas {
    final delDia = _rutasDelDia;
    if (_filtroEstado == 'TODAS') return delDia;
    return delDia.where((r) => r.estado == _filtroEstado).toList();
  }



  void _abrirAgregarParadaDialog(Ruta ruta) {
    showDialog(
      context: context,
      builder: (_) => AgregarParadaDialog(
        ruta: ruta,
        onParadaAgregada: () async {
          await _cargarRutas();
          if (_rutaSeleccionada != null && _rutaSeleccionada!.id == ruta.id) {
            _seleccionarRuta(_rutaSeleccionada!);
          }
        },
      ),
    );
  }

  Future<void> _reoptimizarRutaDesdeDashboard(Ruta ruta) async {
    try {
      double lat = -0.089290;
      double lon = -78.439607;
      if (ruta.choferId != null && _telemetriaChoferes.containsKey(ruta.choferId)) {
        final tel = _telemetriaChoferes[ruta.choferId]!;
        lat = tel.latitud;
        lon = tel.longitud;
      }

      final res = await ApiService.optimizarRutaChofer(ruta.id, latitud: lat, longitud: lon);
      await _cargarRutas();
      _seleccionarRuta(res);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ruta re-optimizada exitosamente con Google Routes API (menor tiempo de viaje).'),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al re-optimizar ruta: $e'),
            backgroundColor: const Color(0xFFE11D48),
          ),
        );
      }
    }
  }

  void _abrirEpodDialog(Despacho despacho) {
    showDialog(
      context: context,
      builder: (_) => EpodDialog(despacho: despacho),
    );
  }


  Future<void> _reasignarChoferDialog(Ruta ruta) async {
    String? choferIdSel = ruta.choferId;
    final nuevoChofer = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Reasignar Chofer — ${ruta.codigoRuta}'),
          content: DropdownButtonFormField<String>(
            initialValue: choferIdSel,
            decoration: const InputDecoration(labelText: 'Nuevo Chofer'),
            dropdownColor: AppTheme.surfaceCard,
            items: _choferes.map((c) {
              return DropdownMenuItem(
                value: c.id,
                child: Text('${c.nombre} (${c.estadoDisponibilidad})'),
              );
            }).toList(),
            onChanged: (val) {
              setDState(() => choferIdSel = val);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, choferIdSel),
              child: const Text('Asignar Chofer'),
            ),
          ],
        ),
      ),
    );

    if (nuevoChofer != null && nuevoChofer != ruta.choferId) {
      try {
        final actualizada = await ApiService.asignarChoferRuta(ruta.id, nuevoChofer);
        if (!mounted) return;
        AppToast.success(context, 'Chofer reasignado exitosamente.');
        await _cargarRutas();
        _seleccionarRuta(actualizada);
      } catch (e) {
        if (!mounted) return;
        AppToast.error(context, 'Error al asignar chofer: $e');
      }
    }
  }

  Future<void> _iniciarRuta(Ruta ruta) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Iniciar Hoja de Ruta'),
        content: Text('¿Desea marcar la ruta ${ruta.codigoRuta} como activa y en curso de despacho?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusEnCurso),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Iniciar Ruta Ahora'),
          ),
        ],
      ),
    );

    if (conf == true) {
      try {
        final iniciada = await ApiService.iniciarRuta(ruta.id);
        if (!mounted) return;
        AppToast.warning(context, 'Ruta ${iniciada.codigoRuta} en curso.');
        await _cargarRutas();
        _seleccionarRuta(iniciada);
      } catch (e) {
        if (!mounted) return;
        AppToast.error(context, 'Error al iniciar ruta: $e');
      }
    }
  }

  Future<void> _cancelarRuta(Ruta ruta) async {
    final motivoCtrl = TextEditingController();
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Cancelar Ruta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('¿Seguro que desea cancelar la ruta ${ruta.codigoRuta}?'),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(labelText: 'Motivo de cancelación'),
            ),
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
      try {
        await ApiService.cancelarRuta(ruta.id, motivoCtrl.text.trim());
        if (!mounted) return;
        AppToast.success(context, 'Ruta cancelada exitosamente.');
        await _cargarRutas();
        setState(() => _rutaSeleccionada = null);
      } catch (e) {
        if (!mounted) return;
        AppToast.error(context, 'Error al cancelar: $e');
      }
    }
  }

  Future<void> _eliminarParada(Despacho parada) async {
    if (_rutaSeleccionada == null) return;
    try {
      final act = await ApiService.eliminarDestinoRuta(_rutaSeleccionada!.id, parada.id);
      if (!mounted) return;
      AppToast.success(context, 'Parada eliminada.');
      await _cargarRutas();
      _seleccionarRuta(act);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Error al eliminar: $e');
    }
  }

  void _cerrarSesion() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  // Métricas para la barra de estadísticas (filtradas por el día seleccionado)
  int get _totalRutasHoy => _rutasDelDia.length;

  int get _totalDespachosContador {
    int sum = 0;
    for (final r in _rutasDelDia) {
      sum += r.paradas.length;
    }
    return sum;
  }

  int get _totalEnCursoContador {
    int sum = 0;
    for (final r in _rutasDelDia) {
      for (final p in r.paradas) {
        if (p.isEnCurso) sum++;
      }
    }
    return sum;
  }

  int get _totalEntregadosContador {
    int sum = 0;
    for (final r in _rutasDelDia) {
      for (final p in r.paradas) {
        if (p.isEntregado) sum++;
      }
    }
    return sum;
  }

  int get _totalCanceladasContador {
    int sum = 0;
    for (final r in _rutasDelDia) {
      if (r.estado == 'CANCELADA' || r.estado == 'CANCELADO') {
        sum += r.paradas.length;
      } else {
        for (final p in r.paradas) {
          if (p.estado == 'CANCELADA' || p.estado == 'CANCELADO') sum++;
        }
      }
    }
    return sum;
  }

  int get _totalAlertasContador {
    int sum = 0;
    for (final r in _rutasDelDia) {
      for (final p in r.paradas) {
        if (p.alertaDesviacion == true) sum++;
      }
    }
    return sum;
  }

  Map<String, String> get _titulosPestana {
    switch (_selectedTabIndex) {
      case 0:
        return {
          'title': 'Monitoreo Cartográfico en Tiempo Real',
          'subtitle': 'Supervisión satelital de rutas de distribución y telemetría GPS activa',
        };
      case 1:
        return {
          'title': 'Tablero Despachos',
          'subtitle': 'Control y seguimiento operativo de rutas por estado de avance',
        };
      case 2:
        return {
          'title': 'Gestión y Asignación Integral de Hojas de Ruta',
          'subtitle': 'Flujo operativo: 1. Crear Ruta → 2. Agregar Paradas con Mapa → 3. Asignar Chofer Responsable',
        };
      case 3:
        return {
          'title': 'Gestión de Inventario, Existencias y Retazos',
          'subtitle': 'Control de existencias de perfiles de aluminio y láminas de vidrio templado',
        };
      case 4:
        return {
          'title': 'Gestión de Usuarios, Cédulas y Seguridad RBAC',
          'subtitle': 'Control de acceso basado en roles y registro civil ecuatoriano',
        };
      case 5:
        return {
          'title': 'Simulador Móvil de Chofer y Telemetría',
          'subtitle': 'Emulación de smartphone chofer para pruebas de streaming y e-PoD',
        };
      default:
        return {'title': 'AlumVid Logistics', 'subtitle': 'Sistema de Control Logístico'};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 960;
          return isDesktop ? _buildDesktopFullLayout() : _buildMobileFullLayout();
        },
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 960
          ? BottomNavigationBar(
              currentIndex: _selectedTabIndex,
              backgroundColor: AppTheme.surface,
              selectedItemColor: AppTheme.primaryLight,
              unselectedItemColor: AppTheme.textMuted,
              type: BottomNavigationBarType.fixed,
              onTap: (idx) => setState(() => _selectedTabIndex = idx),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.gps_fixed), label: 'GPS'),
                BottomNavigationBarItem(icon: Icon(Icons.view_kanban), label: 'Despachos'),
                BottomNavigationBarItem(icon: Icon(Icons.alt_route), label: 'Rutas'),
                BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Inventario'),
                BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Usuarios'),
                BottomNavigationBarItem(icon: Icon(Icons.phone_android), label: 'Simulador'),
              ],
            )
          : null,
    );
  }

  Widget _buildDesktopFullLayout() {
    return Stack(
      children: [
        // 1. Contenedor Principal (con 68px de margen izquierdo para reservar el espacio del sidebar colapsado)
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(left: 68),
            child: Column(
              children: [
                // Cabecera Superior con Título, Sesión y Acciones
                _buildTopBar(),

                // Barra de Métricas de Rutas: ÚNICA Y EXCLUSIVAMENTE EN PESTAÑA 2 (Planificar Rutas)
                if (_selectedTabIndex == 2) _buildMetricsBar(),

                // Vista Activa
                Expanded(
                  child: _buildContenidoPestanaActiva(),
                ),
              ],
            ),
          ),
        ),

        // 2. Barra Lateral Flotante que se expande elegantemente sobre el contenido al pasar el mouse
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: _buildSidebar(),
        ),
      ],
    );
  }

  Widget _buildMobileFullLayout() {
    return Column(
      children: [
        _buildTopBar(),
        if (_selectedTabIndex == 2) _buildMetricsBar(),
        Expanded(
          child: _buildContenidoPestanaActiva(),
        ),
      ],
    );
  }

  // BARRA LATERAL (SIDEBAR) - Diseño formal, elegante, colapsable por hover
  Widget _buildSidebar() {
    final bool expanded = _isSidebarHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isSidebarHovered = true),
      onExit: (_) => setState(() => _isSidebarHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: expanded ? 240 : 68,
        decoration: BoxDecoration(
          color: const Color(0xFF0D1424),
          border: const Border(right: BorderSide(color: Color(0xFF1E293B), width: 1.2)),
          boxShadow: expanded
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(4, 0),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            // Marca AlumVid
            Container(
              height: 64,
              padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: expanded
                  ? Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppTheme.primary, AppTheme.primaryLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text('AV', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AlumVid',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white, letterSpacing: 0.3),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Logística & Operaciones',
                                style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primaryLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('AV', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16)),
                        ),
                      ),
                    ),
            ),

            // Menú de Navegación (6 Módulos elegantes sin corchetes feos)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                children: [
                  _buildNavItem(0, 'Monitoreo en Vivo', Icons.radar_rounded, expanded),
                  _buildNavItem(1, 'Tablero Despachos', Icons.view_kanban_rounded, expanded),
                  _buildNavItem(2, 'Planificar Rutas', Icons.alt_route_rounded, expanded),
                  _buildNavItem(3, 'Inventario & Bodega', Icons.inventory_2_rounded, expanded),
                  _buildNavItem(4, 'Usuarios & Cédulas', Icons.people_alt_rounded, expanded),
                  _buildNavItem(5, 'Simulador Chofer', Icons.phone_android_rounded, expanded),
                ],
              ),
            ),

            // Footer con Estado de Microservicios
            Container(
              padding: EdgeInsets.all(expanded ? 12 : 8),
              decoration: const BoxDecoration(
                color: Color(0xFF090E1A),
                border: Border(top: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: expanded
                  ? const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.hub_rounded, size: 12, color: AppTheme.statusCompletada),
                            SizedBox(width: 6),
                            Text(
                              'SERVICIOS ACTIVOS',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        _SysTag(label: 'Gateway: 8080'),
                        SizedBox(height: 3),
                        _SysTag(label: 'Usuarios: 8081'),
                        SizedBox(height: 3),
                        _SysTag(label: 'Inventario: 8082'),
                        SizedBox(height: 3),
                        _SysTag(label: 'Logística: 8083'),
                        SizedBox(height: 3),
                        _SysTag(label: 'PostGIS 3.4 Activo'),
                      ],
                    )
                  : Tooltip(
                      message: 'Plataforma Conectada:\n• Gateway: 8080\n• Usuarios: 8081\n• Inventario: 8082\n• Logística: 8083\n• PostGIS 3.4 Activo',
                      preferBelow: false,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131D2E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.statusCompletada.withValues(alpha: 0.4)),
                          ),
                          child: const Icon(Icons.dns_rounded, size: 18, color: AppTheme.statusCompletada),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String label, IconData icon, bool expanded) {
    final bool active = _selectedTabIndex == index;

    final navItemContent = Material(
      color: active ? AppTheme.primary.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: active ? AppTheme.primaryLight.withValues(alpha: 0.5) : Colors.transparent,
              width: 1,
            ),
          ),
          child: expanded
              ? Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: active ? AppTheme.primaryLight : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: active ? FontWeight.bold : FontWeight.w500,
                          color: active ? Colors.white : const Color(0xFF94A3B8),
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (active)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryLight,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                )
              : Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: active ? AppTheme.primaryLight : const Color(0xFF94A3B8),
                      ),
                      if (active)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryLight,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: expanded
          ? navItemContent
          : Tooltip(
              message: label,
              preferBelow: false,
              verticalOffset: 0,
              margin: const EdgeInsets.only(left: 10),
              child: navItemContent,
            ),
    );
  }

  // CABECERA SUPERIOR
  Widget _buildTopBar() {
    final titles = _titulosPestana;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Título y Subtítulo dinámico
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles['title']!,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  titles['subtitle']!,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Acciones y Sesión
          Row(
            children: [
              // Badge Sesión
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF131D2E),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    const Text('Sesión: ', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    Text(
                      widget.user.email,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    const Text('[ADMIN]', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryLight)),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Badge WebSocket
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _wsService.isConnected ? AppTheme.statusCompletada.withValues(alpha: 0.15) : AppTheme.statusAlerta.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _wsService.isConnected ? AppTheme.statusCompletada : AppTheme.statusAlerta),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _wsService.isConnected ? AppTheme.statusCompletada : AppTheme.statusAlerta,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _wsService.isConnected ? 'Streaming Activo' : 'Sincronización Polling',
                      style: TextStyle(
                        color: _wsService.isConnected ? AppTheme.statusCompletada : AppTheme.statusAlerta,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Botón Actualizar Global
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.primaryLight),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.refresh, size: 14, color: AppTheme.primaryLight),
                label: const Text('Actualizar', style: TextStyle(color: AppTheme.primaryLight, fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _inicializarDatos,
              ),
              const SizedBox(width: 8),

              // Botón Cerrar Sesión
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.statusAlerta,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.logout, size: 14),
                label: const Text('Cerrar Sesión', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _cerrarSesion,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // BARRA DE MÉTRICAS GLOBALES (Hoy vs Histórico con Rango de Fechas y Auditoría)
  Widget _buildMetricsBar() {
    final bool esHoy = _rangoFiltro.start.year == DateTime.now().year &&
        _rangoFiltro.start.month == DateTime.now().month &&
        _rangoFiltro.start.day == DateTime.now().day &&
        _rangoFiltro.end.year == DateTime.now().year &&
        _rangoFiltro.end.month == DateTime.now().month &&
        _rangoFiltro.end.day == DateTime.now().day;

    final String fechaTexto;
    if (esHoy) {
      fechaTexto = 'Hoy (${DateFormat('dd MMM').format(DateTime.now())})';
    } else if (_rangoFiltro.start.year == _rangoFiltro.end.year &&
        _rangoFiltro.start.month == _rangoFiltro.end.month &&
        _rangoFiltro.start.day == _rangoFiltro.end.day) {
      fechaTexto = DateFormat('dd MMM yyyy').format(_rangoFiltro.start);
    } else {
      fechaTexto = '${DateFormat('dd MMM').format(_rangoFiltro.start)} - ${DateFormat('dd MMM yyyy').format(_rangoFiltro.end)}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Control de Fecha e Histórico (Calendario con selector de rango y auditoría)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: esHoy ? AppTheme.surfaceCard : AppTheme.primary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: esHoy ? AppTheme.border : AppTheme.primaryLight),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.calendar_month, color: esHoy ? AppTheme.primaryLight : Colors.white, size: 20),
                    tooltip: 'Cambiar Rango de Fechas (ej. 10 al 22 de Octubre)',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        initialDateRange: _rangoFiltro,
                        firstDate: DateTime(2025, 1, 1),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                        builder: (ctx, child) {
                          return Theme(
                            data: Theme.of(ctx).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: AppTheme.primary,
                                onPrimary: Colors.white,
                                surface: AppTheme.surface,
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          _rangoFiltro = picked;
                          if (_rutaSeleccionada != null && !_estaEnRango(_rutaSeleccionada!.fechaCreacion, picked)) {
                            _rutaSeleccionada = null;
                            _puntosPolilinea = [];
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _abrirAuditoriaHistorico,
                    borderRadius: BorderRadius.circular(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              esHoy ? 'Métricas de Hoy' : 'Histórico Periodo',
                              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.open_in_new, size: 10, color: AppTheme.primaryLight),
                          ],
                        ),
                        Text(
                          fechaTexto,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: esHoy ? Colors.white : AppTheme.primaryLight),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Abrir auditoría cronológica de rutas, choferes y paradas del periodo',
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.6)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.history_edu, size: 13, color: AppTheme.primaryLight),
                      label: const Text('Auditoría', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      onPressed: _abrirAuditoriaHistorico,
                    ),
                  ),
                  if (!esHoy) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _rangoFiltro = DateTimeRange(start: DateTime.now(), end: DateTime.now());
                          if (_rutaSeleccionada != null && !_estaEnRango(_rutaSeleccionada!.fechaCreacion, _rangoFiltro)) {
                            _rutaSeleccionada = null;
                            _puntosPolilinea = [];
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.statusCompletada.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.statusCompletada),
                        ),
                        child: const Text('Ver Hoy', style: TextStyle(color: AppTheme.statusCompletada, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),

            _buildStatCard('Rutas Totales', '$_totalRutasHoy', AppTheme.primaryLight),
            const SizedBox(width: 10),
            _buildStatCard('Total Paradas / Pedidos', '$_totalDespachosContador', const Color(0xFF3B82F6)),
            const SizedBox(width: 10),
            _buildStatCard('Entregas Exitosas', '$_totalEntregadosContador', AppTheme.statusCompletada),
            const SizedBox(width: 10),
            _buildStatCard('Entregas Canceladas', '$_totalCanceladasContador', AppTheme.statusAlerta),
            const SizedBox(width: 10),
            _buildStatCard('En Curso (Streaming)', '$_totalEnCursoContador', const Color(0xFFF59E0B)),
            const SizedBox(width: 10),
            _buildStatCard('Productos en Bodega', '$_totalProductosBodega', const Color(0xFF06B6D4)),
            const SizedBox(width: 10),
            _buildStatCard('Alertas Stock / Desvío', '$_totalAlertasContador', const Color(0xFFF43F5E)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  // VISTA ACTIVA
  Widget _buildContenidoPestanaActiva() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildVistaMonitoreoGps();
      case 1:
        return KanbanView(
          rutas: _rutasDelPeriodo,
          onRefresh: _inicializarDatos,
          onVerEnMapa: (r) {
            setState(() {
              _selectedTabIndex = 0;
              _seleccionarRuta(r);
            });
          },
        );
      case 2:
        return PlanificarRutasView(
          rutas: _rutasDelDia,
          choferes: _choferes,
          onRefresh: _inicializarDatos,
        );
      case 3:
        return const InventarioView();
      case 4:
        return UsuariosView(currentUser: widget.user);
      case 5:
        return SimuladorView(
          rutas: _rutas,
          choferes: _choferes,
          onPosicionSimulada: (pos, rumbo) {
            _mapWidgetKey.currentState?.enfocarCoordenada(pos, 15.0);
          },
          onRefresh: _inicializarDatos,
        );
      default:
        return const SizedBox();
    }
  }

  // PESTAÑA 0: MONITOREO EN VIVO (SPLIT MAPA + PANEL DE RUTAS)
  Widget _buildVistaMonitoreoGps() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return isDesktop ? _buildDesktopMonitoreo() : _buildMobileMonitoreo();
      },
    );
  }

  Widget _buildDesktopMonitoreo() {
    return Row(
      children: [
        // Mapa Google Maps Platform (65%)
        Expanded(
          flex: 65,
          child: LiveMapWidget(
            key: _mapWidgetKey,
            rutas: _rutas,
            rutaSeleccionada: _rutaSeleccionada,
            telemetriaChoferes: _telemetriaChoferes,
            puntosPolilineaRuta: _puntosPolilinea,
            onParadaTap: (parada) {
              if (parada.isEntregado) {
                _abrirEpodDialog(parada);
              }
            },
            onRutaFocus: (r) => _seleccionarRuta(r),
          ),
        ),

        const VerticalDivider(width: 1, color: AppTheme.border),

        // Panel Lateral de Rutas y Paradas (35%)
        Expanded(
          flex: 35,
          child: Container(
            color: AppTheme.surface,
            child: _buildPanelControl(),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileMonitoreo() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _mobileMapSubIndex = 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _mobileMapSubIndex == 0 ? AppTheme.primary : AppTheme.surface,
                  ),
                  child: const Text('Mapa Google Maps', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _mobileMapSubIndex = 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _mobileMapSubIndex == 1 ? AppTheme.primary : AppTheme.surface,
                  ),
                  child: const Text('Rutas y Paradas', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: _mobileMapSubIndex == 0
              ? LiveMapWidget(
                  key: _mapWidgetKey,
                  rutas: _rutas,
                  rutaSeleccionada: _rutaSeleccionada,
                  telemetriaChoferes: _telemetriaChoferes,
                  puntosPolilineaRuta: _puntosPolilinea,
                  onParadaTap: (parada) {
                    if (parada.isEntregado) {
                      _abrirEpodDialog(parada);
                    }
                  },
                  onRutaFocus: (r) => _seleccionarRuta(r),
                )
              : Container(
                  color: AppTheme.surface,
                  child: _buildPanelControl(),
                ),
        ),
      ],
    );
  }

  Widget _buildPanelControl() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryLight));
    }

    return Column(
      children: [
        // Barra Superior del Panel: Botón Nueva Ruta y Filtros
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFF161F30),
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Rutas y Despachos',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  Tooltip(
                    message: _rutaSeleccionada != null
                        ? 'Agregar nueva parada a la ruta ${_rutaSeleccionada!.codigoRuta}'
                        : 'Seleccione primero una ruta de la lista para agregarle paradas',
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _rutaSeleccionada != null ? AppTheme.primary : AppTheme.surfaceCard,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.add_location_alt, size: 16),
                      label: const Text('+ Agregar Parada', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _rutaSeleccionada != null
                          ? () => _abrirAgregarParadaDialog(_rutaSeleccionada!)
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('En Curso', 'EN_CURSO', AppTheme.statusEnCurso),
                    const SizedBox(width: 6),
                    _buildFilterChip('Pendientes', 'PENDIENTE', AppTheme.statusPendiente),
                    const SizedBox(width: 6),
                    _buildFilterChip('Completadas', 'COMPLETADA', AppTheme.statusCompletada),
                    const SizedBox(width: 6),
                    _buildFilterChip('Todas', 'TODAS', AppTheme.accent),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Cuerpo: Lista de Rutas O Detalle de Paradas si hay una seleccionada
        Expanded(
          child: _rutaSeleccionada != null
              ? _buildVistaDetalleRutaSeleccionada()
              : _buildListaRutas(),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, Color color) {
    final bool activo = _filtroEstado == value;
    final int count = value == 'TODAS'
        ? _rutasDelDia.length
        : _rutasDelDia.where((r) => r.estado == value).length;

    return InkWell(
      onTap: () {
        setState(() {
          _filtroEstado = value;
          _rutaSeleccionada = null;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: activo ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: activo ? color : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: activo ? color : AppTheme.textMuted,
                fontSize: 11,
                fontWeight: activo ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: activo ? color : AppTheme.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaRutas() {
    final rutas = _rutasFiltradas;
    if (rutas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 40, color: AppTheme.textDim),
            const SizedBox(height: 8),
            Text(
              'No hay rutas en estado "$_filtroEstado"',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rutas.length,
      itemBuilder: (context, index) {
        final r = rutas[index];
        return RutaCard(
          ruta: r,
          isSelected: _rutaSeleccionada?.id == r.id,
          onSelect: () => _seleccionarRuta(r),
          onAgregarParada: () => _abrirAgregarParadaDialog(r),
          onReasignarChofer: () => _reasignarChoferDialog(r),
          onIniciar: () => _iniciarRuta(r),
          onCancelar: () => _cancelarRuta(r),
        );
      },
    );
  }

  Widget _buildVistaDetalleRutaSeleccionada() {
    final ruta = _rutaSeleccionada!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            icon: const Icon(Icons.arrow_back, size: 16, color: AppTheme.primaryLight),
            label: const Text('Volver a Todas las Rutas', style: TextStyle(color: AppTheme.primaryLight, fontSize: 12)),
            onPressed: () {
              setState(() {
                _rutaSeleccionada = null;
                _puntosPolilinea = [];
              });
            },
          ),
          const SizedBox(height: 10),

          RutaCard(
            ruta: ruta,
            isSelected: true,
            onSelect: () {},
            onAgregarParada: () => _abrirAgregarParadaDialog(ruta),
            onReasignarChofer: () => _reasignarChoferDialog(ruta),
            onIniciar: () => _iniciarRuta(ruta),
            onCancelar: () => _cancelarRuta(ruta),
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Itinerario de Paradas (${ruta.paradas.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ruta.paradas.length > 1 && (ruta.isPendiente || ruta.isEnCurso)) ...[
                    TextButton.icon(
                      icon: const Icon(Icons.auto_mode, size: 14, color: Color(0xFF38BDF8)),
                      label: const Text('Re-optimizar (Google Routes)', style: TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                      onPressed: () => _reoptimizarRutaDesdeDashboard(ruta),
                    ),
                    const SizedBox(width: 4),
                  ],
                  TextButton.icon(
                    icon: const Icon(Icons.add_location_alt, size: 14, color: AppTheme.primaryLight),
                    label: const Text('+ Agregar Parada', style: TextStyle(fontSize: 11, color: AppTheme.primaryLight)),
                    onPressed: () => _abrirAgregarParadaDialog(ruta),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          ParadasListWidget(
            ruta: ruta,
            onParadaClick: (parada) {
              if (parada.pedido != null) {
                _mapWidgetKey.currentState?.enfocarCoordenada(
                  LatLng(parada.pedido!.latitudDestino, parada.pedido!.longitudDestino),
                  16.0,
                );
              }
            },
            onVerEpod: (parada) => _abrirEpodDialog(parada),
            onEliminarParada: (parada) => _eliminarParada(parada),
          ),
        ],
      ),
    );
  }
}

class _SysTag extends StatelessWidget {
  final String label;

  const _SysTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFF10B981),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 9, fontFamily: 'monospace'),
        ),
      ],
    );
  }
}
