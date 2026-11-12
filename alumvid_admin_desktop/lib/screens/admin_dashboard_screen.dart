import 'dart:async';
import 'package:flutter/material.dart';
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
import '../views/pedidos_view.dart';
import '../views/retazos_view.dart';
import '../views/ubicaciones_view.dart';
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
  Timer? _telemetriaPollingTimer;
  bool _recalculandoPolilinea = false;

  bool _esCoordenadaQuito(double lat, double lon) {
    return lat > -0.5 && lat < 0.2 && lon > -78.8 && lon < -78.2;
  }

  String _filtroEstado = 'EN_CURSO';
  bool _cargando = true;
  DateTimeRange? _rangoFiltro = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now(),
  );

  bool _estaEnRango(DateTime? dt, DateTimeRange? range) {
    if (range == null) return true;
    if (dt == null) return false;
    // Ajustar a hora de Ecuador (UTC-5) para comparar fechas correctamente
    final ecDt = dt.toUtc().subtract(const Duration(hours: 5));
    final start = DateTime(range.start.year, range.start.month, range.start.day, 0, 0, 0);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    final localDt = DateTime(ecDt.year, ecDt.month, ecDt.day, ecDt.hour, ecDt.minute, ecDt.second);
    return localDt.isAfter(start.subtract(const Duration(seconds: 1))) &&
        localDt.isBefore(end.add(const Duration(seconds: 1)));
  }

  List<Ruta> get _rutasDelPeriodo {
    if (_rangoFiltro == null) {
      return List<Ruta>.from(_rutas);
    }

    return _rutas.where((r) {
      // Filtrar estrictamente por fecha de creación, inicio o fin según el rango seleccionado
      return _estaEnRango(r.fechaCreacion, _rangoFiltro) ||
          _estaEnRango(r.fechaInicio, _rangoFiltro) ||
          _estaEnRango(r.fechaFin, _rangoFiltro);
    }).toList();
  }

  List<Ruta> get _rutasDelDia => _rutasDelPeriodo;

  void _abrirAuditoriaHistorico() {
    showDialog(
      context: context,
      builder: (_) => AuditoriaHistoricoDialog(
        todasLasRutas: _rutas,
        rangoInicial: _rangoFiltro ?? DateTimeRange(start: DateTime.now(), end: DateTime.now()),
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
    _telemetriaPollingTimer?.cancel();
    _wsService.dispose();
    super.dispose();
  }

  void _iniciarSuscripcionWebSocket() {
    _wsService.addTelemetriaListener((telemetria) {
      if (!mounted) return;
      if (!_esCoordenadaQuito(telemetria.latitud, telemetria.longitud)) return;
      setState(() {
        final key = (telemetria.choferId != null && telemetria.choferId!.isNotEmpty)
            ? telemetria.choferId!
            : (telemetria.choferNombre ?? 'chofer');
        _telemetriaChoferes[key] = telemetria;
        if (telemetria.choferNombre != null && telemetria.choferNombre!.isNotEmpty) {
          _telemetriaChoferes[telemetria.choferNombre!] = telemetria;
        }
      });
      _actualizarPolilineaEnVivo(telemetria);
    });

    _wsService.addTableroListener(() {
      _recargarDatosSilencioso();
    });

    _wsService.connect();
  }

  Future<void> _inicializarDatos() async {
    setState(() => _cargando = true);
    // 1. Cargar telemetría GPS primero para tener coordenadas reales del chofer en memoria
    await _cargarTelemetriaActiva();
    // 2. Cargar rutas y demás datos operativos
    await Future.wait([
      _cargarRutas(),
      _cargarChoferes(),
      _cargarEstadisticasInventario(),
    ]);
    if (mounted) {
      setState(() => _cargando = false);
      _telemetriaPollingTimer?.cancel();
      _telemetriaPollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) _cargarTelemetriaActiva();
      });
    }
  }

  Future<void> _cargarTelemetriaActiva() async {
    try {
      final list = await ApiService.obtenerTelemetriaActiva();
      if (!mounted) return;
      setState(() {
        for (final tel in list) {
          if (!_esCoordenadaQuito(tel.latitud, tel.longitud)) continue;
          final key = (tel.choferId != null && tel.choferId!.isNotEmpty)
              ? tel.choferId!
              : (tel.choferNombre ?? 'chofer');
          _telemetriaChoferes[key] = tel;
          if (tel.choferNombre != null && tel.choferNombre!.isNotEmpty) {
            _telemetriaChoferes[tel.choferNombre!] = tel;
          }
        }
      });

      if (_rutaSeleccionada != null && list.isNotEmpty) {
        for (final tel in list) {
          if (_esCoordenadaQuito(tel.latitud, tel.longitud)) {
            _actualizarPolilineaEnVivo(tel);
          }
        }
      }
    } catch (_) {}
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
      await ApiService.obtenerProductos(page: 0, size: 1);
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
    _cargarTelemetriaActiva();
  }

  Future<void> _seleccionarRuta(Ruta ruta) async {
    setState(() {
      _rutaSeleccionada = ruta;
      _puntosPolilinea = [];
    });

    if (ruta.paradas.isNotEmpty) {
      // Buscar telemetría activa del chofer asignado en la zona de Quito
      TelemetriaGps? telChofer;
      if (ruta.choferId != null && _telemetriaChoferes.containsKey(ruta.choferId)) {
        telChofer = _telemetriaChoferes[ruta.choferId];
      } else if (ruta.choferNombre != null && _telemetriaChoferes.containsKey(ruta.choferNombre)) {
        telChofer = _telemetriaChoferes[ruta.choferNombre];
      } else {
        for (final t in _telemetriaChoferes.values) {
          if (_esCoordenadaQuito(t.latitud, t.longitud)) {
            telChofer = t;
            break;
          }
        }
      }

      // La polilínea NACE ÚNICA Y EXCLUSIVAMENTE EN EL CHOFER.
      // Jamás debe nacer en la bodega ni conectar la bodega a la ruta.
      if (telChofer != null && _esCoordenadaQuito(telChofer.latitud, telChofer.longitud)) {
        await _recalcularTrazoDesdeChofer(LatLng(telChofer.latitud, telChofer.longitud));
      } else {
        // Si aún no hay señal GPS del chofer, no se dibuja línea desde bodega
        if (mounted) setState(() => _puntosPolilinea = []);
      }
    }
  }

  void _actualizarPolilineaEnVivo(TelemetriaGps telemetria) {
    if (_rutaSeleccionada == null) return;
    final ruta = _rutaSeleccionada!;

    final bool coincideChofer = (ruta.choferId != null && ruta.choferId == telemetria.choferId) ||
        (ruta.choferNombre != null && ruta.choferNombre == telemetria.choferNombre) ||
        (ruta.isEnCurso && _telemetriaChoferes.length <= 2);

    if (!coincideChofer) return;

    final posChofer = LatLng(telemetria.latitud, telemetria.longitud);

    // Recalcular el trazo desde el chofer hacia las paradas pendientes con OSRM
    _recalcularTrazoDesdeChofer(posChofer);
  }

  Future<void> _recalcularTrazoDesdeChofer(LatLng posChofer) async {
    if (_recalculandoPolilinea || _rutaSeleccionada == null) return;
    _recalculandoPolilinea = true;
    try {
      final paradasPendientes = _rutaSeleccionada!.paradas
          .where((p) => p.pedido != null && !p.isEntregado && p.estado != 'CANCELADA')
          .toList();
      if (paradasPendientes.isEmpty) return;

      List<LatLng> nuevosPuntos = [];
      double origLat = posChofer.latitude;
      double origLon = posChofer.longitude;

      for (final p in paradasPendientes) {
        final destLat = p.pedido!.latitudDestino;
        final destLon = p.pedido!.longitudDestino;
        final tramo = await ApiService.trazarRutaVial(origLat, origLon, destLat, destLon);
        for (final c in tramo) {
          nuevosPuntos.add(LatLng(c[0], c[1]));
        }
        origLat = destLat;
        origLon = destLon;
      }

      if (mounted && nuevosPuntos.isNotEmpty) {
        setState(() => _puntosPolilinea = nuevosPuntos);
      }
    } catch (_) {
    } finally {
      _recalculandoPolilinea = false;
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
        AppToast.success(context, 'Ruta re-optimizada exitosamente con Google Routes API');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error al re-optimizar ruta: $e');
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
          'title': 'Gestión y Asignación de Rutas',
          'subtitle': 'Planificación de hojas de ruta, paradas georreferenciadas y asignación de choferes',
        };
      case 3:
        return {
          'title': 'Pedidos & Ventas Comerciales',
          'subtitle': 'Gestión de órdenes de clientes y reservas de stock',
        };
      case 4:
        return {
          'title': 'Retazos & Cortes',
          'subtitle': 'Gestión de piezas de aluminio y vidrio templado para reutilización',
        };
      case 5:
        return {
          'title': 'Ubicaciones Físicas de Bodega',
          'subtitle': 'Mapa de racks y compartimentos de almacenamiento',
        };
      case 6:
        return {
          'title': 'Inventario & Stock',
          'subtitle': 'Control de existencias de perfiles de aluminio y láminas de vidrio',
        };
      case 7:
        return {
          'title': 'Gestión de Usuarios, Cédulas y Seguridad RBAC',
          'subtitle': 'Control de acceso basado en roles y registro civil ecuatoriano',
        };
      case 8:
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
    return Row(
      children: [
        // Barra Lateral Slim fija (no invasiva)
        _buildSlimSidebar(),

        // Contenedor Principal
        Expanded(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _buildContenidoPestanaActiva(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileFullLayout() {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: _buildContenidoPestanaActiva(),
        ),
      ],
    );
  }

  // BARRA LATERAL (SIDEBAR) SLIM & ELEGANTE - NO INVASIVA
  Widget _buildSlimSidebar() {
    final menuItems = [
      {'index': 0, 'label': 'monitoreo', 'icon': Icons.radar_rounded},
      {'index': 1, 'label': 'despachos', 'icon': Icons.view_kanban_rounded},
      {'index': 2, 'label': 'rutas', 'icon': Icons.alt_route_rounded},
      {'index': 3, 'label': 'pedidos', 'icon': Icons.receipt_long_rounded},
      {'index': 4, 'label': 'retazos', 'icon': Icons.content_cut_rounded},
      {'index': 5, 'label': 'bodega', 'icon': Icons.grid_view_rounded},
      {'index': 6, 'label': 'inventario', 'icon': Icons.inventory_2_rounded},
      {'index': 7, 'label': 'usuarios', 'icon': Icons.people_alt_rounded},
      {'index': 8, 'label': 'simulador', 'icon': Icons.phone_android_rounded},
    ];

    return Container(
      width: 82,
      decoration: const BoxDecoration(
        color: Color(0xFF090E1A),
        border: Border(right: BorderSide(color: Color(0xFF1E293B), width: 1.2)),
      ),
      child: Column(
        children: [
          // Logo AlumVid Pin Superior
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF101728),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1D72FE).withValues(alpha: 0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1D72FE).withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.location_on_rounded, color: Color(0xFF38BDF8), size: 26),
              ),
            ),
          ),

          // Lista de Opciones de Navegación Vertical
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: menuItems.length,
              itemBuilder: (context, idx) {
                final item = menuItems[idx];
                final int tabIdx = item['index'] as int;
                final String label = item['label'] as String;
                final IconData icon = item['icon'] as IconData;
                final bool active = _selectedTabIndex == tabIdx;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: active ? const Color(0xFF1D72FE) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _selectedTabIndex = tabIdx),
                      hoverColor: Colors.white.withValues(alpha: 0.05),
                      child: Container(
                        height: 58,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 22,
                              color: active ? Colors.white : const Color(0xFF8DA4C4),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                                color: active ? Colors.white : const Color(0xFF8DA4C4),
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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

          // Configuración / Ajustes Inferior
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _mostrarDialogoConfiguracion,
                hoverColor: Colors.white.withValues(alpha: 0.05),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.settings_outlined, size: 20, color: Color(0xFF8DA4C4)),
                      SizedBox(height: 3),
                      Text(
                        'configuración',
                        style: TextStyle(fontSize: 9.5, color: Color(0xFF8DA4C4)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
  }

  void _mostrarDialogoConfiguracion() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101728),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF1E293B))),
        title: const Row(
          children: [
            Icon(Icons.settings_rounded, color: Color(0xFF38BDF8), size: 20),
            SizedBox(width: 8),
            Text('Ecosistema AlumVid', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Microservicios Conectados:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const _SysTag(label: 'Gateway: 8085'),
            const SizedBox(height: 3),
            const _SysTag(label: 'Usuarios: 8081'),
            const SizedBox(height: 3),
            const _SysTag(label: 'Inventario: 8082'),
            const SizedBox(height: 3),
            const _SysTag(label: 'Logística: 8083'),
            const SizedBox(height: 3),
            const _SysTag(label: 'Retazos: 8084'),
            const SizedBox(height: 3),
            const _SysTag(label: 'Pedidos: 8087'),
            const SizedBox(height: 3),
            const _SysTag(label: 'Ubicaciones: 8086'),
            const SizedBox(height: 3),
            const _SysTag(label: 'PostGIS 3.4 Activo'),
            const Divider(color: Color(0xFF1E293B), height: 20),
            Row(
              children: [
                const Text('Estado Streaming: ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                Text(
                  _wsService.isConnected ? 'WebSocket Activo' : 'Polling Activo',
                  style: TextStyle(
                    color: _wsService.isConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            icon: const Icon(Icons.logout, size: 14),
            label: const Text('Cerrar Sesión'),
            onPressed: () {
              Navigator.pop(ctx);
              _cerrarSesion();
            },
          ),
        ],
      ),
    );
  }

  // CABECERA SUPERIOR - ESTILO CLEAN (MOCKUP)
  Widget _buildTopBar() {
    final titles = _titulosPestana;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF090E1A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Título de la Pantalla Activa
          Text(
            titles['title']!,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
          ),

          // Avatar y Menú de Perfil
          PopupMenuButton<String>(
            tooltip: 'Menú de Usuario',
            offset: const Offset(0, 48),
            color: const Color(0xFF101728),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF1E293B)),
            ),
            onSelected: (val) {
              if (val == 'refresh') _inicializarDatos();
              if (val == 'auditoria') _abrirAuditoriaHistorico();
              if (val == 'config') _mostrarDialogoConfiguracion();
              if (val == 'logout') _cerrarSesion();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.user.email, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      _wsService.isConnected ? 'Streaming WebSocket Activo' : 'Sincronización Polling',
                      style: TextStyle(
                        fontSize: 11,
                        color: _wsService.isConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 1),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF38BDF8)),
                    SizedBox(width: 10),
                    Text('Actualizar Datos', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'auditoria',
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 16, color: Color(0xFF38BDF8)),
                    SizedBox(width: 10),
                    Text('Auditoría Histórica', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'config',
                child: Row(
                  children: [
                    Icon(Icons.hub_rounded, size: 16, color: Color(0xFF38BDF8)),
                    SizedBox(width: 10),
                    Text('Servicios & Sistema', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 1),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 16, color: Color(0xFFEF4444)),
                    SizedBox(width: 10),
                    Text('Cerrar Sesión', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF101728),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 12,
                    backgroundColor: Color(0xFF1D72FE),
                    child: Icon(Icons.person, size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.user.email,
                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
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
          rutas: _rutasDelPeriodo,
          todasLasRutas: _rutas,
          choferes: _choferes,
          rangoFiltro: _rangoFiltro,
          onCambiarRangoFiltro: (newRange) {
            setState(() => _rangoFiltro = newRange);
          },
          onRefresh: _inicializarDatos,
          onIrAMonitoreo: (ruta) {
            setState(() {
              _selectedTabIndex = 0;
              if (ruta != null) {
                _seleccionarRuta(ruta);
              }
            });
          },
        );
      case 3:
        return const PedidosView();
      case 4:
        return const RetazosView();
      case 5:
        return const UbicacionesView();
      case 6:
        return const InventarioView();
      case 7:
        return UsuariosView(currentUser: widget.user);
      case 8:
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

          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
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
