import 'package:flutter/material.dart';
import '../models/despacho.dart';
import '../models/ruta.dart';
import '../theme/app_theme.dart';
import 'parada_card_widget.dart';

class ParadasListWidget extends StatelessWidget {
  final Ruta ruta;
  final Function(Despacho) onParadaClick;
  final Function(Despacho) onVerEpod;
  final Function(Despacho) onEliminarParada;

  const ParadasListWidget({
    super.key,
    required this.ruta,
    required this.onParadaClick,
    required this.onVerEpod,
    required this.onEliminarParada,
  });

  @override
  Widget build(BuildContext context) {
    if (ruta.paradas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.location_off, color: AppTheme.textDim, size: 36),
            SizedBox(height: 8),
            Text(
              'Esta ruta no contiene paradas configuradas.',
              style: TextStyle(color: AppTheme.textDim, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: ruta.paradas.length,
      itemBuilder: (context, index) {
        final parada = ruta.paradas[index];

        return ParadaCardWidget(
          parada: parada,
          orden: index + 1,
          onVerEpod: parada.isEntregado ? () => onVerEpod(parada) : null,
          onEliminar: (ruta.isPendiente && ruta.paradas.length > 1)
              ? () => onEliminarParada(parada)
              : null,
        );
      },
    );
  }
}
