import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'navegacion_destino_screen.dart';

/// Pantalla que presenta el itinerario completo de una Hoja de Ruta asignada (ej. Ruta 1).
/// Permite al chofer inspeccionar la totalidad de paradas/destinos y elegir con cual
/// destino iniciar su recorrido de distribucion.
class DetalleRutaScreen extends StatefulWidget {
  final Map<String, dynamic> ruta;
  final Map<String, dynamic> choferData;

  const DetalleRutaScreen({
    super.key,
    required this.ruta,
    required this.choferData,
  });

  @override
  State<DetalleRutaScreen> createState() => _DetalleRutaScreenState();
}

class _DetalleRutaScreenState extends State<DetalleRutaScreen> {
  late Map<String, dynamic> _rutaActual;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rutaActual = widget.ruta;
    _recargarDetalleRuta();
  }

  Future<void> _recargarDetalleRuta() async {
    final rutaId = _rutaActual['id']?.toString();
    if (rutaId == null) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final res = await ApiService.obtenerRutaPorId(rutaId);
      if (mounted) {
        setState(() {
          _rutaActual = res;
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
        return const Color(0xFF94A3B8);
    }
  }

  Future<void> _iniciarDestinoSeleccionado(Map<String, dynamic> despacho) async {
    final despachoId = despacho['id']?.toString() ?? '';
    final estadoDespacho = despacho['estado'] ?? 'PENDIENTE';

    // Si la parada está pendiente, notificar inicio formal al backend
    if (estadoDespacho == 'PENDIENTE') {
      try {
        await ApiService.aceptarEIniciarRuta(despachoId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Atencion: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: const Color(0xFFF59E0B),
          ),
        );
      }
    }

    if (!mounted) return;

    // Abrir la pantalla de navegacion urbana en tiempo real (estilo Uber con OSRM)
    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NavegacionDestinoScreen(
          despacho: despacho,
          ruta: _rutaActual,
          choferData: widget.choferData,
        ),
      ),
    );

    // Al regresar de la entrega documentada o de la navegacion, refrescar la lista
    if (actualizado == true || mounted) {
      _recargarDetalleRuta();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String codigoRuta = _rutaActual['codigoRuta'] ?? 'Ruta';
    final String estadoRuta = _rutaActual['estado'] ?? 'PENDIENTE';
    final List<dynamic> paradas = (_rutaActual['paradas'] as List<dynamic>?) ?? [];

    // Contabilizar paradas entregadas
    final int entregadas = paradas.where((p) => p['estado'] == 'ENTREGADO').length;
    final int totalParadas = paradas.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              codigoRuta,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            Text(
              '$totalParadas Destinos de Entrega Programados',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
            onPressed: _recargarDetalleRuta,
            tooltip: 'Actualizar paradas',
          ),
        ],
      ),
      body: _cargando && paradas.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : RefreshIndicator(
              onRefresh: _recargarDetalleRuta,
              color: const Color(0xFF2563EB),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. TARJETA RESUMEN DE LA RUTA
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      border: Border.all(color: const Color(0xFF1E293B)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              codigoRuta,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _obtenerColorEstado(estadoRuta).withValues(alpha: 0.15),
                                border: Border.all(color: _obtenerColorEstado(estadoRuta).withValues(alpha: 0.4)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                estadoRuta,
                                style: TextStyle(
                                  color: _obtenerColorEstado(estadoRuta),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Progreso: $entregadas de $totalParadas entregas documentadas',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 10),
                        // Barra de progreso
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: totalParadas > 0 ? (entregadas / totalParadas) : 0.0,
                            minHeight: 6,
                            backgroundColor: const Color(0xFF1E293B),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                          ),
                        ),
                        if (_rutaActual['comentarios'] != null &&
                            _rutaActual['comentarios'].toString().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Instrucciones: ${_rutaActual['comentarios']}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
                  const Text(
                    'DESTINOS DE ENTREGA DE ESTA RUTA',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF60A5FA),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Seleccione con cual destino iniciara su recorrido:',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 12),

                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE11D48).withValues(alpha: 0.1),
                        border: Border.all(color: const Color(0xFFE11D48)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFFFB7185), fontSize: 12)),
                    ),

                  // 2. LISTA DE PARADAS / DESTINOS
                  if (paradas.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: const Text(
                        'Esta ruta no contiene destinos asignados aun.',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    )
                  else
                    ...paradas.map((d) {
                      final String estado = d['estado'] ?? 'PENDIENTE';
                      final Map<String, dynamic> pedido =
                          (d['pedido'] as Map<String, dynamic>?) ?? {};
                      final String cliente = pedido['cliente'] ?? 'Cliente';
                      final String direccion = pedido['direccionTexto'] ?? 'Quito';
                      final num? orden = d['ordenParada'] as num?;
                      final bool esEntregado = estado == 'ENTREGADO';
                      final bool esEnCurso = estado == 'EN_CURSO';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          border: Border.all(
                            color: esEnCurso
                                ? const Color(0xFF2563EB)
                                : esEntregado
                                    ? const Color(0xFF059669).withValues(alpha: 0.4)
                                    : const Color(0xFF1E293B),
                            width: esEnCurso ? 1.8 : 1.0,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Parada #${orden ?? 1}',
                                          style: const TextStyle(
                                            color: Color(0xFF38BDF8),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '#${d['id'].toString().substring(0, 6)}',
                                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _obtenerColorEstado(estado).withValues(alpha: 0.15),
                                      border: Border.all(color: _obtenerColorEstado(estado).withValues(alpha: 0.4)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      estado,
                                      style: TextStyle(
                                        color: _obtenerColorEstado(estado),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                cliente,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.place, color: Color(0xFF94A3B8), size: 15),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      direccion,
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Boton de accion segun estado
                              if (esEntregado)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle, color: Color(0xFF34D399), size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'Entrega Finalizada y Documentada con e-PoD',
                                        style: TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: esEnCurso
                                          ? const Color(0xFF0284C7)
                                          : const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: Icon(
                                      esEnCurso ? Icons.navigation : Icons.play_arrow,
                                      size: 18,
                                    ),
                                    label: Text(
                                      esEnCurso
                                          ? 'Continuar Navegacion Urbana a este Destino'
                                          : 'Iniciar Entrega a este Destino',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                    onPressed: () => _iniciarDestinoSeleccionado(d),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
