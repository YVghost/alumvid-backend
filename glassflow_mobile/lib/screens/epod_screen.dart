import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';

class EpodScreen extends StatefulWidget {
  final Map<String, dynamic> despacho;

  const EpodScreen({super.key, required this.despacho});

  @override
  State<EpodScreen> createState() => _EpodScreenState();
}

class _EpodScreenState extends State<EpodScreen> {
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: const Color(0xFF60A5FA),
    exportBackgroundColor: const Color(0xFF0A0E17),
  );

  final TextEditingController _comentariosController = TextEditingController();
  bool _enviando = false;
  String? _fotoBase64;

  @override
  void dispose() {
    _signatureController.dispose();
    _comentariosController.dispose();
    super.dispose();
  }

  void _simularCapturaFoto() {
    // Generar Base64 de evidencia fotografica con marca de agua
    setState(() {
      _fotoBase64 =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Evidencia fotografica capturada con exito.'),
        backgroundColor: Color(0xFF059669),
      ),
    );
  }

  Future<void> _finalizarEntrega() async {
    if (_fotoBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CP-LOG-01: La fotografia del vidrio es obligatoria.'),
          backgroundColor: Color(0xFFE11D48),
        ),
      );
      return;
    }

    if (_signatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CP-LOG-01: La firma digital tactil del receptor es obligatoria.'),
          backgroundColor: Color(0xFFE11D48),
        ),
      );
      return;
    }

    setState(() => _enviando = true);

    try {
      // 1. Obtener firma en Base64
      final firmaBytes = await _signatureController.toPngBytes();
      if (firmaBytes == null) throw Exception('Error procesando firma');
      final firmaBase64 = 'data:image/png;base64,${base64Encode(firmaBytes)}';

      // 2. Obtener posicion satelital actual del GPS
      double lat;
      double lon;
      try {
        final pos = await LocationService.determinarPosicionActual();
        lat = pos.latitude;
        lon = pos.longitude;
      } catch (_) {
        // En emulador sin GPS activo, fallback a la coordenada del pedido
        final Map<String, dynamic> ped = (widget.despacho['pedido'] is Map)
            ? widget.despacho['pedido'] as Map<String, dynamic>
            : <String, dynamic>{};
        lat = (ped['latitudDestino'] as num?)?.toDouble() ?? -0.180653;
        lon = (ped['longitudDestino'] as num?)?.toDouble() ?? -78.467838;
      }

      // 3. Enviar peticion al backend
      final res = await ApiService.cerrarEntrega(
        despachoId: widget.despacho['id'],
        fotoPodUrl: _fotoBase64!,
        firmaUrl: firmaBase64,
        latitud: lat,
        longitud: lon,
        comentarios: _comentariosController.text.trim(),
      );

      if (!mounted) return;

      if (res['alertaDesviacion'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Entrega registrada con ALERTA: Desvio de ${res['desviacionMetros'].round()}m.'),
            backgroundColor: const Color(0xFFD97706),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entrega documentada y finalizada con exito.'),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFFE11D48),
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: const Text(
          'Documentacion e-PoD',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. FOTO DE ENTREGA
            const Text(
              '1. Evidencia Fotografica del Vidrio Entregado',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _simularCapturaFoto,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Center(
                  child: _fotoBase64 != null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, color: Color(0xFF34D399), size: 36),
                            SizedBox(height: 6),
                            Text(
                              'Foto capturada satisfactoriamente',
                              style: TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, color: Color(0xFF60A5FA), size: 32),
                            SizedBox(height: 6),
                            Text(
                              'Tocar para capturar foto de entrega',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. FIRMA DIGITAL TACTIL
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '2. Firma Tactil del Receptor',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () => _signatureController.clear(),
                  child: const Text('Limpiar', style: TextStyle(color: Color(0xFFFB7185), fontSize: 12)),
                ),
              ],
            ),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF1E293B)),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Signature(
                controller: _signatureController,
                height: 140,
                backgroundColor: const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 20),

            // 3. COMENTARIOS
            const Text(
              '3. Observaciones de Entrega',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _comentariosController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ej. Recibido por maestro de obra sin roturas.',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF111827),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF1E293B)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _enviando ? null : _finalizarEntrega,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _enviando
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'Confirmar y Enviar e-PoD',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
