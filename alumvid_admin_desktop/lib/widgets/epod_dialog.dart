import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/despacho.dart';
import '../theme/app_theme.dart';

class EpodDialog extends StatelessWidget {
  final Despacho despacho;

  const EpodDialog({super.key, required this.despacho});

  Widget _buildImageOrBase64(String? dataUri, String placeholder) {
    if (dataUri == null || dataUri.trim().isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        alignment: Alignment.center,
        child: Text(
          placeholder,
          style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
        ),
      );
    }

    try {
      if (dataUri.startsWith('data:image')) {
        final commaIndex = dataUri.indexOf(',');
        if (commaIndex != -1) {
          final base64Str = dataUri.substring(commaIndex + 1);
          final bytes = base64Decode(base64Str);
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              height: 200,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          );
        }
      } else if (dataUri.startsWith('http')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            dataUri,
            height: 200,
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => _buildImageOrBase64(null, 'No se pudo cargar la imagen remota'),
          ),
        );
      }
    } catch (_) {}

    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Text('Formato de imagen no soportado', style: TextStyle(color: AppTheme.textDim)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    final pedido = despacho.pedido;
    final desvio = despacho.desviacionMetros ?? 0.0;
    final isAlerta = despacho.hasAlertaDesviacion || desvio > 150.0;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isAlerta ? AppTheme.statusAlerta : AppTheme.primaryLight),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Encabezado del Modal
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.statusCompletada.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.verified, color: AppTheme.statusCompletada, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Comprobante e-PoD (Proof of Delivery)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            'Parada #${despacho.ordenParada} • ${pedido?.cliente ?? "Cliente"}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.primaryLight),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const Divider(color: AppTheme.border, height: 24),

              // Banner de Auditoría Espacial PostGIS
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isAlerta
                      ? AppTheme.statusAlerta.withValues(alpha: 0.15)
                      : AppTheme.statusCompletada.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isAlerta ? AppTheme.statusAlerta : AppTheme.statusCompletada,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isAlerta ? Icons.warning : Icons.g_mobiledata,
                      color: isAlerta ? AppTheme.statusAlerta : AppTheme.statusCompletada,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAlerta
                                ? 'ALERTA DE DESVIACIÓN GEOGRÁFICA (>150m)'
                                : 'ENTREGA CONFORME EN GEOCERCA (POSTGIS)',
                            style: TextStyle(
                              color: isAlerta ? AppTheme.statusAlerta : AppTheme.statusCompletada,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Desviación calculada: ${desvio.toStringAsFixed(1)} metros respecto al destino del cliente.',
                            style: const TextStyle(color: AppTheme.textMain, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Información del despacho
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161F30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _buildInfoRow('Dirección del Cliente:', pedido?.direccionTexto ?? '—'),
                    const SizedBox(height: 6),
                    _buildInfoRow(
                      'Fecha y Hora de Entrega:',
                      despacho.fechaEntrega != null ? dateFormat.format(despacho.fechaEntrega!) : '—',
                    ),
                    const SizedBox(height: 6),
                    _buildInfoRow('Chofer Responsable:', despacho.chofer?.nombre ?? '—'),
                    if (despacho.comentarios != null && despacho.comentarios!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildInfoRow('Observaciones:', despacho.comentarios!),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Fotografía de Evidencia del Vidrio entregado
              const Text(
                '1. Evidencia Fotográfica en Sitio (Cámara en Vivo):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
              const SizedBox(height: 8),
              _buildImageOrBase64(despacho.fotoPodUrl, 'Sin fotografía adjunta.'),

              const SizedBox(height: 16),

              // Firma Digitalizada del Receptor
              const Text(
                '2. Firma Digital del Cliente (Captura Táctil):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: _buildImageOrBase64(despacho.firmaUrl, 'Sin firma registrada.'),
              ),

              const SizedBox(height: 20),

              // Botón de cierre
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar Auditoría'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
