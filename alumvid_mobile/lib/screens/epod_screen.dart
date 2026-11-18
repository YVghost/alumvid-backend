import 'package:alumvid_admin_desktop/shared/tema.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';

import '../services/api_service.dart';
import '../services/location_service.dart';
import '../utils/app_toast.dart';

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
    exportBackgroundColor: AppColors.background,
  );

  final TextEditingController _comentariosController = TextEditingController();
  bool _enviando = false;
  String? _fotoBase64;
  Uint8List? _fotoBytes;

  @override
  void dispose() {
    _signatureController.dispose();
    _comentariosController.dispose();
    super.dispose();
  }

  void _mostrarToastDiscreto(String mensaje, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      AppToast.error(context, mensaje);
    } else {
      AppToast.success(context, mensaje);
    }
  }

  Future<void> _capturarFoto({ImageSource source = ImageSource.camera}) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _fotoBytes = bytes;
          _fotoBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        });
        _mostrarToastDiscreto('Evidencia fotográfica capturada con éxito.');
      }
    } catch (e) {
      _mostrarToastDiscreto(
        'No se pudo acceder a la cámara/galería: $e',
        isError: true,
      );
    }
  }

  void _seleccionarOrigenFoto() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Evidencia Fotográfica de Entrega',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.primaryLight,
                ),
                title: Text(
                  'Tomar Foto con Cámara',
                  style: TextStyle(color: AppColors.text, fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _capturarFoto(source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: Color(0xFF34D399),
                ),
                title: Text(
                  'Elegir de Galería',
                  style: TextStyle(color: AppColors.text, fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _capturarFoto(source: ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finalizarEntrega() async {
    if (_fotoBase64 == null) {
      _mostrarToastDiscreto(
        'CP-LOG-01: La fotografía del material entregado es obligatoria.',
        isError: true,
      );
      return;
    }

    if (_signatureController.isEmpty) {
      _mostrarToastDiscreto(
        'CP-LOG-01: La firma digital táctil del receptor es obligatoria.',
        isError: true,
      );
      return;
    }

    setState(() => _enviando = true);

    try {
      // 1. Obtener firma en Base64
      final firmaBytes = await _signatureController.toPngBytes();
      if (firmaBytes == null) throw Exception('Error procesando firma táctil');
      final firmaBase64 = 'data:image/png;base64,${base64Encode(firmaBytes)}';

      // 2. Obtener posición satelital actual del GPS
      double lat;
      double lon;
      try {
        final pos = await LocationService.determinarPosicionActual();
        lat = pos.latitude;
        lon = pos.longitude;
      } catch (_) {
        final Map<String, dynamic> ped = (widget.despacho['pedido'] is Map)
            ? widget.despacho['pedido'] as Map<String, dynamic>
            : <String, dynamic>{};
        lat = (ped['latitudDestino'] as num?)?.toDouble() ?? -0.180653;
        lon = (ped['longitudDestino'] as num?)?.toDouble() ?? -78.467838;
      }

      // 3. Enviar petición al backend
      final res = await ApiService.cerrarEntrega(
        despachoId: widget.despacho['id'].toString(),
        fotoPodUrl: _fotoBase64!,
        firmaUrl: firmaBase64,
        latitud: lat,
        longitud: lon,
        comentarios: _comentariosController.text.trim(),
      );

      if (!mounted) return;

      if (res['alertaDesviacion'] == true) {
        _mostrarToastDiscreto(
          'Entrega registrada con ALERTA: Desvío de ${res['desviacionMetros'].round()}m.',
        );
      } else {
        _mostrarToastDiscreto('Entrega documentada y finalizada con éxito.');
      }

      Navigator.pop(context, true);
    } catch (e) {
      _mostrarToastDiscreto(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild semantic colors when the appearance changes.

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'Documentación e-PoD',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. FOTO DE ENTREGA
            Text(
              '1. Evidencia Fotográfica de Entrega (Cámara en Vivo) *',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _seleccionarOrigenFoto,
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _fotoBytes != null
                        ? const Color(0xFF10B981)
                        : AppColors.card,
                    width: _fotoBytes != null ? 1.5 : 1.0,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _fotoBytes != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_fotoBytes!, fit: BoxFit.cover),
                            Container(color: Colors.black38),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF34D399),
                                    size: 36,
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Foto de entrega capturada\n(Tocar para cambiar)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt_rounded,
                              color: Color(0xFF60A5FA),
                              size: 36,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Tocar para tomar fotografía con la cámara',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Evidencia física obligatoria para cerrar la entrega',
                              style: TextStyle(
                                color: AppColors.textDim,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. FIRMA DIGITAL TÁCTIL
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '2. Firma Táctil del Receptor *',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(
                    Icons.clear_rounded,
                    size: 14,
                    color: Color(0xFFFB7185),
                  ),
                  label: const Text(
                    'Limpiar',
                    style: TextStyle(color: Color(0xFFFB7185), fontSize: 12),
                  ),
                  onPressed: () => _signatureController.clear(),
                ),
              ],
            ),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.card),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Signature(
                controller: _signatureController,
                height: 140,
                backgroundColor: AppColors.surface,
              ),
            ),
            const SizedBox(height: 20),

            // 3. COMENTARIOS
            Text(
              '3. Observaciones de Entrega',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _comentariosController,
              style: TextStyle(color: AppColors.text, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ej. Recibido por maestro de obra sin roturas.',
                hintStyle: TextStyle(color: AppColors.textDim, fontSize: 13),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.card),
                ),
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: _enviando ? null : _finalizarEntrega,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: _enviando
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.text,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(
                _enviando
                    ? 'Verificando y cerrando entrega...'
                    : 'Confirmar y Enviar e-PoD',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
