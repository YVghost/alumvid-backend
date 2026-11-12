import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/despacho.dart';
import '../theme/app_theme.dart';

class ParadaCardWidget extends StatelessWidget {
  final Despacho parada;
  final int orden;
  final VoidCallback? onEliminar;
  final VoidCallback? onVerEpod;

  const ParadaCardWidget({
    super.key,
    required this.parada,
    required this.orden,
    this.onEliminar,
    this.onVerEpod,
  });

  Future<void> _abrirEnGoogleMaps(double lat, double lon) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('No se pudo abrir Google Maps: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ped = parada.pedido;
    final cliente = ped?.cliente ?? 'Sin cliente especificado';
    final direccion = ped?.direccionTexto ?? 'Dirección no registrada';
    final lat = ped?.latitudDestino ?? parada.latitudEntrega ?? -0.1807;
    final lon = ped?.longitudDestino ?? parada.longitudEntrega ?? -78.4678;
    final coordenadasValidas = lat != 0.0 && lon != 0.0;

    Color estadoColor = AppTheme.statusPendiente;
    String estadoTexto = 'PENDIENTE';
    if (parada.isEntregado) {
      estadoColor = AppTheme.statusCompletada;
      estadoTexto = 'ENTREGADO';
    } else if (parada.isEnCurso) {
      estadoColor = AppTheme.statusEnCurso;
      estadoTexto = 'EN CAMINO';
    } else if (parada.estado == 'CANCELADA' || parada.estado == 'CANCELADO') {
      estadoColor = AppTheme.statusAlerta;
      estadoTexto = 'CANCELADA';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Barra Superior de la Parada
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppTheme.primary,
                      child: Text(
                        '$orden',
                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cliente,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Parada programada',
                          style: TextStyle(fontSize: 10, color: AppTheme.textDim),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: estadoColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: estadoColor),
                      ),
                      child: Text(
                        estadoTexto,
                        style: TextStyle(color: estadoColor, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (parada.isEntregado && onVerEpod != null) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.verified, color: AppTheme.statusCompletada, size: 20),
                        tooltip: 'Ver Expediente e-PoD',
                        onPressed: onVerEpod,
                      ),
                    ],
                    if (onEliminar != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppTheme.statusAlerta, size: 20),
                        tooltip: 'Eliminar Parada',
                        onPressed: onEliminar,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // 2. Qué se va a entregar (Material / Producto de inventario)
          if (parada.comentarios != null && parada.comentarios!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF131D2E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, color: AppTheme.primaryLight, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: [
                            const TextSpan(
                              text: 'Entrega: ',
                              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryLight, fontSize: 12),
                            ),
                            TextSpan(
                              text: parada.comentarios!,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),

          // 3. Previsualización de Ubicación estilo WhatsApp
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: InkWell(
              onTap: coordenadasValidas ? () => _abrirEnGoogleMaps(lat, lon) : null,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mini mapa interactivo fijado (Preview estilo WhatsApp)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                      child: SizedBox(
                        height: 100,
                        width: double.infinity,
                        child: AbsorbPointer(
                          absorbing: true, // No intercepta clics, el clic abre Google Maps
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(lat, lon),
                              initialZoom: 15.0,
                              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                                userAgentPackageName: 'com.alumvid.admin',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(lat, lon),
                                    width: 34,
                                    height: 34,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: AppTheme.statusAlerta,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
                                        ],
                                      ),
                                      child: const Icon(Icons.location_on, color: Colors.white, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Franja inferior de la tarjeta de WhatsApp
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.pin_drop, color: AppTheme.statusAlerta, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    direccion,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Ver en Google Maps',
                                  style: TextStyle(color: AppTheme.primaryLight, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.open_in_new, color: AppTheme.primaryLight, size: 12),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
