import 'package:flutter/material.dart';
import '../services/api_service.dart';
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

  @override
  void initState() {
    super.initState();
    _despachoActual = widget.despacho;
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
            const SizedBox(height: 24),

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
            ] else if (estado == 'EN_CURSO') ...[
              Container(
                padding: const EdgeInsets.all(14),
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
                        'Telemetria en tiempo real activa. La central esta recibiendo sus coordenadas.',
                        style: TextStyle(color: Color(0xFF93C5FD), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
            ] else if (estado == 'ENTREGADO') ...[
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
            ] else if (estado == 'CANCELADA') ...[
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
