import 'package:flutter/material.dart';
import '../models/ruta.dart';
import '../theme/app_theme.dart';

class RutaCard extends StatelessWidget {
  final Ruta ruta;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onAgregarParada;
  final VoidCallback onReasignarChofer;
  final VoidCallback onIniciar;
  final VoidCallback onCancelar;

  const RutaCard({
    super.key,
    required this.ruta,
    required this.isSelected,
    required this.onSelect,
    required this.onAgregarParada,
    required this.onReasignarChofer,
    required this.onIniciar,
    required this.onCancelar,
  });

  Color _getStatusColor() {
    switch (ruta.estado) {
      case 'EN_CURSO':
        return AppTheme.statusEnCurso;
      case 'COMPLETADA':
        return AppTheme.statusCompletada;
      case 'CANCELADA':
        return AppTheme.statusCancelada;
      case 'PENDIENTE':
      default:
        return AppTheme.statusPendiente;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? AppTheme.primaryLight : AppTheme.border,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      color: isSelected ? const Color(0xFF1E293B) : AppTheme.surface,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado: Código de ruta y Estado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          ruta.isEnCurso
                              ? Icons.local_shipping
                              : ruta.isCompletada
                                  ? Icons.task_alt
                                  : Icons.alt_route,
                          color: statusColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ruta.codigoRuta,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (ruta.isEnCurso) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          ruta.estado,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Información del Chofer
              Row(
                children: [
                  const Icon(Icons.person, color: AppTheme.textMuted, size: 14),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      ruta.choferNombre != null && ruta.choferNombre!.isNotEmpty
                          ? ruta.choferNombre!
                          : 'Sin chofer asignado',
                      style: TextStyle(
                        color: ruta.choferNombre != null ? AppTheme.textMain : AppTheme.statusAlerta,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (ruta.choferTelefono != null && ruta.choferTelefono!.isNotEmpty)
                    Text(
                      '(${ruta.choferTelefono})',
                      style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Barra de Progreso de Paradas
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Paradas: ${ruta.paradasEntregadas} de ${ruta.totalParadas} completadas',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                      Text(
                        '${(ruta.porcentajeAvance * 100).toInt()}%',
                        style: TextStyle(
                          color: ruta.isCompletada ? AppTheme.statusCompletada : AppTheme.primaryLight,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ruta.porcentajeAvance,
                      backgroundColor: const Color(0xFF0F172A),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        ruta.isCompletada ? AppTheme.statusCompletada : AppTheme.primaryLight,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Botones de Acción Operativa Rápida
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Botón Agregar Parada
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.add_location_alt, size: 14, color: AppTheme.primaryLight),
                    label: const Text('+ Parada', style: TextStyle(fontSize: 11, color: AppTheme.primaryLight)),
                    onPressed: onAgregarParada,
                  ),



                  // Botón Reasignar Chofer
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.swap_horiz, size: 14, color: AppTheme.textMuted),
                    label: const Text('Chofer', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    onPressed: onReasignarChofer,
                  ),

                  // Iniciar / Cancelar
                  if (ruta.isPendiente)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.statusEnCurso,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onIniciar,
                      child: const Text('Iniciar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  else if (ruta.isEnCurso)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.statusAlerta,
                        side: const BorderSide(color: AppTheme.statusAlerta),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onCancelar,
                      child: const Text('Cancelar', style: TextStyle(fontSize: 10)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
