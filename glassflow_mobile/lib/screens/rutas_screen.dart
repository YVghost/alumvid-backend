import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'detalle_ruta_screen.dart';
import 'login_screen.dart';

class RutasScreen extends StatefulWidget {
  final Map<String, dynamic> choferData;

  const RutasScreen({super.key, required this.choferData});

  @override
  State<RutasScreen> createState() => _RutasScreenState();
}

class _RutasScreenState extends State<RutasScreen> {
  List<dynamic> _despachos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarRutas();
  }

  Future<void> _cargarRutas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final choferId = widget.choferData['id'];
      final List<dynamic> res = await ApiService.obtenerDespachosHoy(choferId);
      res.sort((a, b) {
        final ordA = (a['ordenParada'] as num?)?.toInt() ?? 999;
        final ordB = (b['ordenParada'] as num?)?.toInt() ?? 999;
        return ordA.compareTo(ordB);
      });
      setState(() {
        _despachos = res;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() => _cargando = false);
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
        return const Color(0xFF34D399);
      case 'CANCELADA':
        return const Color(0xFFFB7185);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombreChofer = widget.choferData['nombre'] ?? 'Chofer';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nombreChofer,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const Text(
              'Rutas de Entrega Asignadas',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
            onPressed: _cargarRutas,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFFB7185)),
            onPressed: _cerrarSesion,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, style: const TextStyle(color: Color(0xFFFB7185))),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _cargarRutas,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : _despachos.isEmpty
                  ? const Center(
                      child: Text(
                        'No posee rutas de despacho programadas para hoy.',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargarRutas,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _despachos.length,
                        itemBuilder: (context, index) {
                          final d = _despachos[index];
                          final estado = d['estado'] ?? 'PENDIENTE';
                          final pedido = d['pedido'] ?? {};
                          final colorEstado = _obtenerColorEstado(estado);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111827),
                              border: Border.all(color: const Color(0xFF1E293B)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(14),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    d['ordenParada'] != null
                                        ? 'PARADA #${d['ordenParada']} • #${d['id'].toString().substring(0, 6)}'
                                        : 'PEDIDO #${d['id'].toString().substring(0, 6)}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF60A5FA),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: colorEstado.withValues(alpha: 0.15),
                                      border: Border.all(color: colorEstado.withValues(alpha: 0.3)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      estado,
                                      style: TextStyle(
                                        color: colorEstado,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pedido['cliente'] ?? 'Cliente',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Destino: ${pedido['direccionTexto'] ?? '-'}',
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DetalleRutaScreen(despacho: d),
                                  ),
                                );
                                _cargarRutas();
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
